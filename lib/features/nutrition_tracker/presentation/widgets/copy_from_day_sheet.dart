import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/widgets/app_skeleton.dart';

import '../../domain/models/food_log_entry.dart';
import 'copy_day_item_picker.dart';

/// The user's choice from [CopyFromDaySheet]: which day was copied from and the
/// SELECTED source entries to copy. Multi-select copy is additive — the picked
/// items are added to the target day (no whole-day replace).
class CopyFromDayResult {
  const CopyFromDayResult(this.sourceDate, {required this.entries});
  final DateTime sourceDate;
  final List<FoodLogEntry> entries;
}

class _DayOption {
  const _DayOption(this.date, this.count);
  final DateTime date;
  final int count;
}

/// Two-stage "copy from another day" picker: stage 1 lists recent days that have
/// entries; tapping one advances IN-PLACE to stage 2, where the day's foods show
/// as checkable rows (all checked by default) so the user copies the whole day
/// in one tap or unchecks the few they don't want. Returns null if dismissed.
class CopyFromDaySheet extends StatefulWidget {
  const CopyFromDaySheet._({required this.targetDate, required this.loadDay});

  final DateTime targetDate;
  final Future<List<FoodLogEntry>> Function(DateTime date) loadDay;

  static Future<CopyFromDayResult?> show(
    BuildContext context, {
    required DateTime targetDate,
    required Future<List<FoodLogEntry>> Function(DateTime date) loadDay,
  }) {
    return showModalBottomSheet<CopyFromDayResult>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      builder: (_) =>
          CopyFromDaySheet._(targetDate: targetDate, loadDay: loadDay),
    );
  }

  @override
  State<CopyFromDaySheet> createState() => _CopyFromDaySheetState();
}

class _CopyFromDaySheetState extends State<CopyFromDaySheet> {
  // Probe this many recent days for entries to surface as quick-pick rows. Days
  // further back (up to the two-year floor) are reachable via "Pick a date".
  static const _lookbackDays = 30;
  // The calendar floor for "Pick a date": two years back, matching the diary.
  static const _calendarFloorYears = 2;
  bool _loading = true;
  List<_DayOption> _days = const [];

  // Stage 2: the day the user drilled into (null = stage 1 day list).
  DateTime? _selectedDay;
  bool _loadingEntries = false;
  List<FoodLogEntry> _dayEntries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _load() async {
    final target = _dayOnly(widget.targetDate);
    final candidates = [
      for (var i = 1; i <= _lookbackDays; i++)
        target.subtract(Duration(days: i)),
    ];
    final counts = await Future.wait(
      candidates.map((d) async {
        try {
          final entries = await widget.loadDay(d);
          return _DayOption(d, entries.length);
        } catch (_) {
          return _DayOption(d, 0);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _days = counts.where((o) => o.count > 0).toList(growable: false);
      _loading = false;
    });
  }

  Future<void> _openDay(_DayOption option) async {
    setState(() {
      _selectedDay = option.date;
      _loadingEntries = true;
      _dayEntries = const [];
    });
    List<FoodLogEntry> entries = const [];
    try {
      entries = await widget.loadDay(option.date);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _dayEntries = entries;
      _loadingEntries = false;
    });
  }

  /// Opens a calendar (two years back) so the user can reach any day beyond the
  /// recent quick-pick window, then drills straight into it.
  Future<void> _pickArbitraryDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayOnly(
        widget.targetDate,
      ).subtract(const Duration(days: 1)),
      firstDate: DateTime(now.year - _calendarFloorYears),
      lastDate: _dayOnly(widget.targetDate),
    );
    if (picked == null || !mounted) return;
    await _openDay(_DayOption(_dayOnly(picked), 0));
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final isYesterday =
        _dayOnly(date) == _dayOnly(now.subtract(const Duration(days: 1)));
    if (isYesterday) return 'Yesterday';
    // Include the year for days outside the current year so far-back picks
    // (now reachable via the calendar) read unambiguously.
    final pattern = date.year == now.year ? 'EEE, MMM d' : 'EEE, MMM d, y';
    return DateFormat(pattern).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _selectedDay == null ? _stageOne() : _stageTwo(),
      ),
    );
  }

  Widget _stageOne() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x3,
            AppSpacing.x1,
            AppSpacing.x3,
            AppSpacing.x2,
          ),
          child: Text(
            'Copy from another day',
            style: theme.textTheme.titleLarge,
          ),
        ),
        Flexible(child: _dayList(theme)),
      ],
    );
  }

  Widget _stageTwo() {
    if (_loadingEntries) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 200, height: 18),
            SizedBox(height: AppSpacing.x2),
            AppSkeleton(width: 160, height: 18),
          ],
        ),
      );
    }
    return CopyDayItemPicker(
      dayLabel: _dayLabel(_selectedDay!),
      entries: _dayEntries,
      onBack: () => setState(() => _selectedDay = null),
      onCopy: (selected) =>
          context.pop(CopyFromDayResult(_selectedDay!, entries: selected)),
    );
  }

  Widget _dayList(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.x3,
          0,
          AppSpacing.x3,
          AppSpacing.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeleton(width: 200, height: 18),
            SizedBox(height: AppSpacing.x2),
            AppSkeleton(width: 160, height: 18),
          ],
        ),
      );
    }
    // A "Pick a date" row always trails the recent quick-pick days so any day
    // back to the two-year floor is reachable, even with no recent entries.
    final pickADate = ListTile(
      leading: const Icon(Icons.event_outlined),
      title: const Text('Pick a date'),
      subtitle: Text(
        'Reach any earlier day',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _pickArbitraryDay,
    );

    if (_days.isEmpty) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x2,
          0,
          AppSpacing.x2,
          AppSpacing.x3,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x1,
              0,
              AppSpacing.x1,
              AppSpacing.x2,
            ),
            child: Text(
              'No recent days with food to copy.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          pickADate,
        ],
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.x2,
        0,
        AppSpacing.x2,
        AppSpacing.x3,
      ),
      itemCount: _days.length + 1,
      itemBuilder: (context, i) {
        if (i == _days.length) return pickADate;
        final option = _days[i];
        return ListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: Text(_dayLabel(option.date)),
          subtitle: Text(
            '${option.count} ${option.count == 1 ? 'item' : 'items'}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _openDay(option),
        );
      },
    );
  }
}
