import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/models/food.dart';

/// On-device, offline-first search index over the bundled generic foods asset.
///
/// On first use it loads `assets/data/foods_generic.json`, builds a sqflite
/// database backed by an FTS5 virtual table over `(name, brand)`, and persists
/// it under the application support directory. The build runs once: a hash of
/// the bundled asset is stored in [SharedPreferences] and the DB is only
/// rebuilt when that asset changes.
///
/// ## Bundled sqlite3 (FTS5 guaranteed)
///
/// This index runs on the `sqflite_common_ffi` factory backed by
/// `sqlite3_flutter_libs`, NOT the default `sqflite` factory. The default
/// factory uses the OS-provided SQLite, and some Android OEM/older builds ship
/// a SQLite without the FTS5 module — `CREATE VIRTUAL TABLE ... USING fts5`
/// then throws `no such module: fts5` and the index would silently degrade to
/// empty (backend-only) on those devices. The bundled sqlite3 includes FTS5 on
/// every platform, so the on-device search works everywhere. Tests may inject
/// their own [DatabaseFactory]; production callers get the ffi factory by
/// default (initialized once, lazily).
///
/// Every public path degrades gracefully — a missing/empty asset or a sqflite
/// failure yields an empty result instead of throwing, so callers can fall back
/// to the backend search.
///
/// ## Offline-consistency contract
///
/// This index participates in a three-layer system (local FTS index, the
/// offline food-log queue, and the per-request server query-result cache).
/// To keep search and the diary coherent it MUST obey the following rules
/// (see `docs/exec-plans/nutrition-revamp-2026.md` → OFFLINE CONSISTENCY):
///
/// 1. READ-ONLY. The FTS index is a search cache only — never a write target.
///    Nothing logged, edited, or created by the user is persisted here; the
///    only writer is [_buildIndex], which rebuilds the table from the bundled
///    asset. Treat every row as disposable: it can be dropped and rebuilt at
///    any time without data loss.
/// 2. WRITES GO THROUGH THE QUEUE. Food LOG writes never touch this index;
///    they always flow through `offline_food_log_queue` (optimistic insert
///    with a temp id, reconciled against the server on replay).
/// 3. RECONCILIATION REWRITES food_id. When a queued log references a food
///    that exists only locally (an FTS row) or as a temp custom food, replay
///    must resolve or create the canonical server-side food id and rewrite the
///    entry's `food_id`. A local FTS id is a search affordance, not a durable
///    diary key — it is not authoritative for any logged entry.
/// 4. SERVER CACHE IS NOT AUTHORITATIVE. The backend query-result cache is
///    per-request and short-lived; like this index it serves search, never the
///    diary. The diary's source of truth is the server, reached via the queue.
class LocalFoodIndex {
  LocalFoodIndex({
    String assetPath = 'assets/data/foods_generic.json',
    Future<String> Function(String)? loadAsset,
    Future<String> Function()? dbDirectoryProvider,
    DatabaseFactory? databaseFactory,
  }) : _assetPath = assetPath,
       _loadAsset = loadAsset ?? rootBundle.loadString,
       _dbDirectoryProvider = dbDirectoryProvider ?? _defaultDbDirectory,
       _databaseFactory = databaseFactory;

  static const _ftsTable = 'foods_fts';
  static const _hashPrefsKey = 'foods_index_asset_hash';
  static const _dbFileName = 'foods_fts5.db';

  final String _assetPath;
  final Future<String> Function(String) _loadAsset;
  final Future<String> Function() _dbDirectoryProvider;
  final DatabaseFactory? _databaseFactory;

  Database? _db;
  Future<Database?>? _opening;
  bool _failed = false;

  static Future<String> _defaultDbDirectory() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// Lazily initializes the bundled ffi sqlite3 (FTS5-capable) exactly once,
  /// process-wide. Guards against repeated `sqfliteFfiInit()` calls.
  static bool _ffiInitialized = false;
  static DatabaseFactory _defaultFactory() {
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    return databaseFactoryFfi;
  }

  DatabaseFactory get _factory => _databaseFactory ?? _defaultFactory();

  /// Searches the local index for foods whose name or brand matches [query] as
  /// a prefix. Returns at most [limit] rows, each mapped to a [Food] with
  /// `trustTier == 'verified'`. Returns an empty list on any failure or when
  /// the query has no searchable terms.
  Future<List<Food>> search(String query, {int limit = 20}) async {
    final matchExpr = _toPrefixMatch(query);
    if (matchExpr == null) return const <Food>[];

    final db = await _ensureDb();
    if (db == null) return const <Food>[];

    try {
      final rows = await db.query(
        _ftsTable,
        columns: const [
          'id',
          'name',
          'brand',
          'caloriesPer100g',
          'proteinGramsPer100g',
          'carbsGramsPer100g',
          'fatGramsPer100g',
          'source',
          'dataType',
        ],
        where: '$_ftsTable MATCH ?',
        whereArgs: [matchExpr],
        limit: limit,
      );
      return rows.map(_rowToFood).toList(growable: false);
    } catch (_) {
      return const <Food>[];
    }
  }

  /// Builds an FTS5 prefix MATCH expression, quoting the term so punctuation
  /// cannot break out into FTS5 operators. Returns null when no alphanumeric
  /// content remains (e.g. empty or symbol-only queries).
  String? _toPrefixMatch(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    // Quote each term (FTS5 string literal) then append the prefix star.
    return terms.map((t) => '"$t"*').join(' ');
  }

  Food _rowToFood(Map<String, Object?> row) {
    double? toDouble(Object? v) => (v as num?)?.toDouble();
    final brand = (row['brand'] as String?)?.trim();
    return Food(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      brand: (brand == null || brand.isEmpty) ? null : brand,
      source: (row['source'] ?? 'fdc').toString(),
      caloriesPer100g: toDouble(row['caloriesPer100g']),
      proteinPer100g: toDouble(row['proteinGramsPer100g']),
      carbsPer100g: toDouble(row['carbsGramsPer100g']),
      fatPer100g: toDouble(row['fatGramsPer100g']),
      trustTier: 'verified',
    );
  }

  Future<Database?> _ensureDb() {
    if (_db != null) return Future.value(_db);
    if (_failed) return Future.value(null);
    return _opening ??= _openOnce();
  }

  Future<Database?> _openOnce() async {
    try {
      final raw = await _safeLoadAsset();
      if (raw == null || raw.trim().isEmpty) {
        _failed = true;
        return null;
      }
      final assetHash = md5.convert(utf8.encode(raw)).toString();

      final dir = await _dbDirectoryProvider();
      final dbPath = '$dir/$_dbFileName';

      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_hashPrefsKey);
      final exists = await _factory.databaseExists(dbPath);

      if (storedHash == assetHash && exists) {
        _db = await _factory.openDatabase(dbPath);
        return _db;
      }

      // Asset changed (or first run / missing file): rebuild from scratch.
      if (exists) {
        await _factory.deleteDatabase(dbPath);
      }
      final db = await _factory.openDatabase(dbPath);
      await _buildIndex(db, raw);
      await prefs.setString(_hashPrefsKey, assetHash);
      _db = db;
      return _db;
    } catch (_) {
      _failed = true;
      return null;
    } finally {
      _opening = null;
    }
  }

  Future<String?> _safeLoadAsset() async {
    try {
      return await _loadAsset(_assetPath);
    } catch (_) {
      return null;
    }
  }

  Future<void> _buildIndex(Database db, String raw) async {
    await db.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $_ftsTable USING fts5('
      'name, brand, '
      "id UNINDEXED, "
      'caloriesPer100g UNINDEXED, '
      'proteinGramsPer100g UNINDEXED, '
      'carbsGramsPer100g UNINDEXED, '
      'fatGramsPer100g UNINDEXED, '
      'source UNINDEXED, '
      'dataType UNINDEXED'
      ')',
    );

    final decoded = jsonDecode(raw);
    if (decoded is! List) return;

    final batch = db.batch();
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final row = Map<String, dynamic>.from(entry);
      batch.insert(_ftsTable, {
        'name': (row['name'] ?? '').toString(),
        'brand': (row['brand'] ?? '').toString(),
        'id': (row['id'] ?? '').toString(),
        'caloriesPer100g': (row['caloriesPer100g'] as num?)?.toDouble(),
        'proteinGramsPer100g': (row['proteinGramsPer100g'] as num?)?.toDouble(),
        'carbsGramsPer100g': (row['carbsGramsPer100g'] as num?)?.toDouble(),
        'fatGramsPer100g': (row['fatGramsPer100g'] as num?)?.toDouble(),
        'source': (row['source'] ?? 'fdc').toString(),
        'dataType': row['dataType']?.toString(),
      });
    }
    await batch.commit(noResult: true);
  }

  /// Closes the underlying database, if open. Mainly for tests.
  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null) {
      try {
        await db.close();
      } catch (_) {
        // Ignore close failures; the handle is being discarded anyway.
      }
    }
  }
}
