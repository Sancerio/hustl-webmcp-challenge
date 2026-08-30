import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import '../screens/workout_progress_utils.dart';

/// Filter widget for selecting date ranges on Progress screen.
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({
    super.key,
    required this.range,
    required this.onChanged,
    this.onQuickRangeChanged,
  });

  final DateTimeRange? range;
  final ValueChanged<DateTimeRange?> onChanged;
  final ValueChanged<QuickDateRange?>? onQuickRangeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final label = range == null
        ? 'All time'
        : '${DateFormat.MMMd().format(range!.start)} – ${DateFormat.MMMd().format(range!.end)}';

    return Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.x1),
        PopupMenuButton<QuickDateRange?>(
          tooltip: 'Select time period',
          onSelected: (value) {
            if (value == null) {
              onQuickRangeChanged?.call(null);
              onChanged(null);
            } else {
              onQuickRangeChanged?.call(value);
              onChanged(quickDateRange(value));
            }
          },
          itemBuilder: (context) => [
            _buildMenuItem(null, 'All time', range == null),
            const PopupMenuDivider(),
            _buildMenuItem(
              QuickDateRange.last2Weeks,
              'Last 2 weeks',
              _isSelected(QuickDateRange.last2Weeks),
            ),
            _buildMenuItem(
              QuickDateRange.last1Month,
              'Last month',
              _isSelected(QuickDateRange.last1Month),
            ),
            _buildMenuItem(
              QuickDateRange.last3Months,
              'Last 3 months',
              _isSelected(QuickDateRange.last3Months),
            ),
            _buildMenuItem(
              QuickDateRange.last6Months,
              'Last 6 months',
              _isSelected(QuickDateRange.last6Months),
            ),
            _buildMenuItem(
              QuickDateRange.last1Year,
              'Last year',
              _isSelected(QuickDateRange.last1Year),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x1 + 4,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _showCustomPicker(context),
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: const Text('Custom'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ],
    );
  }

  bool _isSelected(QuickDateRange quickRange) {
    if (range == null) return false;
    final expected = quickDateRange(quickRange);
    return range!.start.year == expected.start.year &&
        range!.start.month == expected.start.month &&
        range!.start.day == expected.start.day &&
        range!.end.year == expected.end.year &&
        range!.end.month == expected.end.month &&
        range!.end.day == expected.end.day;
  }

  PopupMenuItem<QuickDateRange?> _buildMenuItem(
    QuickDateRange? value,
    String label,
    bool isSelected,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (isSelected) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }

  Future<void> _showCustomPicker(BuildContext context) async {
    final now = DateTime.now();
    DateTimeRange? initial = range;
    if (range != null) {
      final end = range!.end.isAfter(now) ? now : range!.end;
      final start = range!.start.isAfter(end) ? end : range!.start;
      initial = DateTimeRange(start: start, end: end);
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: initial,
    );
    if (picked != null) {
      onChanged(picked);
    }
  }
}
