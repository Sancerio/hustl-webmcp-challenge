import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/services/token_storage.dart';
import '../../domain/models/workout_template.dart';
import '../../domain/repositories/template_repository.dart';
import '../repositories/local_template_repository.dart';
import '../datasources/template_sync_api.dart';
import '../../../../core/services/notification_service.dart';

class TemplateSyncService with WidgetsBindingObserver {
  final PreferencesService _prefs;
  final TokenStorage _tokens;
  final TemplateRepository _local;
  final TemplateSyncApi _api;
  // Notifications intentionally unused for sync errors; retained for future in-app surfaces.
  // ignore: unused_field
  final NotificationService? _notifications;
  Timer? _timer;
  bool _isSyncing = false;
  Duration _backoff = Duration.zero;
  static const Duration _minInterval = Duration(minutes: 10);
  static const Duration _maxBackoff = Duration(minutes: 30);

  TemplateSyncService(
    this._prefs,
    this._tokens,
    this._local,
    this._api,
    this._notifications,
  );

  Future<int> _getCursor() => _prefs.getTemplatesSyncVersion();
  Future<void> _setCursor(int v) => _prefs.setTemplatesSyncVersion(v);

  Future<List<Map<String, dynamic>>> _exportLocalDirty() async {
    final dirty = await _prefs.getTemplatesDirtyIds();
    if (dirty.isEmpty) return const [];
    final versionMap = await _prefs.getTemplatesVersionMap();
    final all = await _local.getWorkoutTemplates();
    final selected = all.where((t) => dirty.contains(t.id)).toList();
    selected.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return selected.map((t) => _toServerMap(t, versionMap[t.id])).toList();
  }

  Map<String, dynamic> _toServerMap(WorkoutTemplate t, int? clientVersion) {
    return {
      'id': t.id,
      'name': t.name,
      'description': t.description,
      'exercises': t.exercises,
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
      if (clientVersion != null) 'sync_version_client': clientVersion,
    };
  }

  Future<List<String>> _getDeletedIds() => _prefs.getTemplatesDeletedIds();

  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final access = await _tokens.getAccessToken();
      if (access == null || access.isEmpty) return; // unauthenticated
      final cursor = await _getCursor();
      final payload = await _exportLocalDirty();
      final deleted = await _getDeletedIds();

      if (payload.isNotEmpty || deleted.isNotEmpty) {
        final newCursor = await _api.batch(
          accessToken: access,
          upserts: payload,
          deletes: deleted,
        );
        final uploadedIds = payload
            .map((m) => m['id'] as String?)
            .whereType<String>();
        if (uploadedIds.isNotEmpty) {
          await _prefs.removeTemplatesDirtyIds(uploadedIds);
        }
        if (deleted.isNotEmpty) {
          await _prefs.removeTemplatesDeletedIds(deleted);
        }
        await _setCursor(newCursor);
        await _prefs.setTemplatesLastSyncAt(DateTime.now());
      }

      final delta = await _api.delta(accessToken: access, since: cursor);
      await _importServer(delta.items);
      await _setCursor(delta.cursor);
      await _prefs.setTemplatesLastSyncAt(DateTime.now());
      _backoff = Duration.zero;
    } catch (e) {
      _backoff = _backoff == Duration.zero
          ? const Duration(minutes: 2)
          : _backoff * 2;
      if (_backoff > _maxBackoff) _backoff = _maxBackoff;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _importServer(List<Map<String, dynamic>> server) async {
    if (server.isEmpty) return;
    for (final m in server) {
      try {
        final deletedAt = m['deleted_at'] as String?;
        final t = WorkoutTemplate.fromJson({
          'id': m['id'],
          'name': m['name'] ?? '',
          'description': m['description'] ?? '',
          'exercises': m['exercises'] ?? const [],
          'createdAt': (m['created_at'] ?? m['createdAt']) as String,
          'updatedAt': (m['updated_at'] ?? m['updatedAt']) as String,
        });
        // Upsert locally
        if (deletedAt != null) {
          if (_local is LocalTemplateRepository) {
            await (_local).deleteFromRemote(t.id);
          } else {
            await _local.deleteWorkoutTemplate(t.id);
          }
          await _prefs.removeTemplatesDirtyIds([t.id]);
          await _prefs.removeTemplatesDeletedIds([t.id]);
          await _prefs.removeTemplateSyncVersions([t.id]);
        } else {
          if (_local is LocalTemplateRepository) {
            await (_local).upsertFromRemote(t);
          } else {
            final existing = await _local.getWorkoutTemplate(t.id);
            if (existing == null) {
              await _local.createWorkoutTemplate(t);
            } else {
              await _local.updateWorkoutTemplate(t);
            }
          }
          // Clear dirty flag for this id
          await _prefs.removeTemplatesDirtyIds([t.id]);
          final sv = (m['sync_version'] as num?)?.toInt();
          if (sv != null) {
            await _prefs.setTemplateSyncVersion(t.id, sv);
          }
        }
      } catch (_) {
        // Skip malformed entries
      }
    }
  }

  void startAutoSync() {
    _timer?.cancel();
    _timer = Timer.periodic(_minInterval, (_) async {
      if (_backoff > Duration.zero) {
        _backoff -= _minInterval;
        if (_backoff.isNegative) _backoff = Duration.zero;
        return;
      }
      await syncNow();
    });
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }
}
