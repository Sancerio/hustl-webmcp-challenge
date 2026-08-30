import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:hustl_app/app/theme/app_motion.dart';
import 'package:hustl_app/app/theme/app_radius.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';
import 'package:hustl_app/core/services/haptics.dart';
import 'package:hustl_app/core/widgets/hustl_menu_button.dart';
import 'package:intl/intl.dart';

/// Canonical day key used to look up per-day fill ratios.
String diaryWeekDayKey(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).toIso8601String().substring(0, 10);

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The diary date title (§12.2): 20/w700, settings-free. The label itself is
/// tappable (when [onPickDate] is given) to open a month calendar and jump to
/// any day. When the user has navigated off today a quiet "Today" text button
/// appears on the right.
class DiaryDateTitle extends StatelessWidget {
  const DiaryDateTitle({
    super.key,
    required this.date,
    required this.onToday,
    this.onPickDate,
    this.trailingAction,
  });

  final DateTime date;
  final VoidCallback onToday;

  /// Optional: tapping the date label opens a calendar to jump to any day.
  final VoidCallback? onPickDate;

  /// Optional quiet action (e.g. a day-options kebab) shown before the account
  /// avatar.
  final Widget? trailingAction;

  String _label(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    if (_isSameDay(date, now.add(const Duration(days: 1)))) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());

    return Padding(
      // Match the tab-root app-bar trailing rhythm: a small right inset so the
      // avatar sits flush with Train/History/Progress/Library.
      padding: const EdgeInsets.only(left: AppSpacing.x2, right: AppSpacing.x1),
      child: Row(
        children: [
          Expanded(
            child: _DateLabel(label: _label(date), onPickDate: onPickDate),
          ),
          if (!isToday)
            TextButton(onPressed: onToday, child: const Text('Today')),
          if (trailingAction != null) trailingAction!,
          // The account avatar (top-right), consistent with every tab root.
          // This is a tab root, so HustlMenuButton renders the avatar (never a
          // back button).
          const HustlMenuButton(),
        ],
      ),
    );
  }
}

/// The date label itself. When [onPickDate] is given it becomes a tappable
/// affordance (a quiet trailing chevron hints at the calendar) that opens a
/// month calendar to jump to any day; otherwise it is a plain label.
class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.label, this.onPickDate});

  final String label;
  final VoidCallback? onPickDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      label,
      style: theme.textTheme.titleLarge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (onPickDate == null) return text;

    return InkWell(
      onTap: () {
        Haptics.selection();
        onPickDate!();
      },
      borderRadius: AppRadius.pillRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x1,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: text),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The calendar week banner (§12.2): 7 day ovals Mon–Sun. Fill is an
/// adherence-NEUTRAL monochrome tint encoding consumption vs target (outline
/// when nothing is logged, deeper neutral fill as the day fills toward its
/// target — never a red/orange warning). The current day carries a blue
/// primary ring, the selected day is the solid blue oval, and tapping a day
/// jumps to it.
/// A horizontal swipe (or the screen-reader week actions) moves a whole week.
class DiaryWeekBanner extends StatelessWidget {
  const DiaryWeekBanner({
    super.key,
    required this.date,
    required this.onSelectDay,
    this.fillRatioByDay = const {},
  });

  /// The selected diary day; the banner shows its Mon–Sun week.
  final DateTime date;

  final ValueChanged<DateTime> onSelectDay;

  /// `yyyy-MM-dd` -> consumed/target calorie ratio (missing = nothing known).
  final Map<String, double> fillRatioByDay;

  DateTime get _monday {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  void _shiftWeek(int deltaDays) {
    Haptics.selection();
    onSelectDay(date.add(Duration(days: deltaDays)));
  }

  @override
  Widget build(BuildContext context) {
    final monday = _monday;
    final days = List<DateTime>.generate(
      7,
      (i) => monday.add(Duration(days: i)),
    );

    return Semantics(
      container: true,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Previous week'): () =>
            _shiftWeek(-7),
        const CustomSemanticsAction(label: 'Next week'): () => _shiftWeek(7),
      },
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) _shiftWeek(-7);
          if (velocity < -200) _shiftWeek(7);
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x1,
            2,
            AppSpacing.x1,
            AppSpacing.x1 + 4,
          ),
          child: Row(
            children: [
              _WeekChevron(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous week',
                onTap: () => _shiftWeek(-7),
              ),
              for (final day in days)
                Expanded(
                  child: _DayOval(
                    day: day,
                    isSelected: _isSameDay(day, date),
                    isToday: _isSameDay(day, DateTime.now()),
                    fillRatio: fillRatioByDay[diaryWeekDayKey(day)] ?? 0,
                    onTap: () {
                      Haptics.selection();
                      onSelectDay(day);
                    },
                  ),
                ),
              _WeekChevron(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next week',
                onTap: () => _shiftWeek(7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small, low-emphasis chevron flanking the week strip for discoverable
/// week paging (mirrors the swipe gesture). Quiet by design — it never competes
/// with the day ovals.
class _WeekChevron extends StatelessWidget {
  const _WeekChevron({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 22,
      color: scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: tooltip,
    );
  }
}

class _DayOval extends StatelessWidget {
  const _DayOval({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.fillRatio,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final double fillRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isFuture = day.isAfter(DateTime.now());

    // Adherence-neutral consumption encoding: outline -> deeper neutral tint.
    final ratio = fillRatio.clamp(0.0, 1.0);
    final Color fill;
    if (isSelected) {
      fill = scheme.primary;
    } else if (ratio <= 0) {
      fill = Colors.transparent;
    } else {
      fill = scheme.onSurface.withValues(alpha: 0.08 + 0.24 * ratio);
    }

    final Color numberColor;
    if (isSelected) {
      numberColor = scheme.onPrimary;
    } else if (isFuture) {
      numberColor = scheme.onSurfaceVariant;
    } else {
      numberColor = scheme.onSurface;
    }

    final semanticsLabel = [
      DateFormat('EEEE, MMMM d').format(day),
      if (isToday) 'today',
    ].join(', ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('E').format(day).substring(0, 1),
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: AppMotion.fast,
              key: ValueKey('diary-week-day-${diaryWeekDayKey(day)}'),
              width: 34,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: AppRadius.pillRadius,
                border: Border.all(
                  color: isToday ? scheme.primary : scheme.outlineVariant,
                  width: isToday ? 1.5 : 1,
                ),
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: numberColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned diary header: the date title stays put while the week banner
/// underneath collapses (shrinks + fades) as the log scrolls.
class DiaryWeekHeaderDelegate extends SliverPersistentHeaderDelegate {
  DiaryWeekHeaderDelegate({
    required this.topPadding,
    required this.title,
    required this.banner,
  });

  final double topPadding;
  final Widget title;
  final Widget banner;

  static const double titleHeight = 48;
  static const double bannerHeight = 72;

  @override
  double get minExtent => topPadding + titleHeight;

  @override
  double get maxExtent => topPadding + titleHeight + bannerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final t = (shrinkOffset / bannerHeight).clamp(0.0, 1.0);

    return Container(
      color: scheme.surface,
      // The hairline is painted, not laid out, so heights match the extents.
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          SizedBox(
            height: titleHeight,
            child: Align(alignment: Alignment.centerLeft, child: title),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1 - t,
              child: Opacity(
                opacity: 1 - t,
                child: SizedBox(height: bannerHeight, child: banner),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant DiaryWeekHeaderDelegate oldDelegate) =>
      oldDelegate.topPadding != topPadding ||
      oldDelegate.title != title ||
      oldDelegate.banner != banner;
}
