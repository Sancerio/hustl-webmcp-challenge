import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';

/// Wave G section vocabulary (§12.1): screens are built from flat sections —
/// a 13px UPPERCASE [SectionHeader] followed by a [SectionList] of rows
/// separated by hairline dividers. No card chrome, no fills, no outlines:
/// structure comes from type and hairlines only.

/// A confident sentence-case section title (17/w700 `onSurface`) — a real
/// heading, not a shouty uppercase admin label.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x2,
      AppSpacing.x3,
      AppSpacing.x2,
      AppSpacing.x1,
    ),
  });

  /// Natural-case title; rendered UPPERCASE.
  final String title;

  /// Optional right-aligned widget (e.g. a small "See all" text button).
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final header = Semantics(
      container: true,
      header: true,
      label: title,
      excludeSemantics: true,
      child: Text(
        title,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Padding(
      padding: padding,
      child: trailing == null
          ? Align(alignment: AlignmentDirectional.centerStart, child: header)
          : Row(
              children: [
                Expanded(child: header),
                trailing!,
              ],
            ),
    );
  }
}

/// A list group of rows separated by hairline dividers. With [card] set the
/// group is wrapped in a rounded surface card (iOS grouped style) so it reads
/// as a premium object instead of bare spreadsheet rows.
class SectionList extends StatelessWidget {
  const SectionList({
    super.key,
    required this.children,
    this.dividers = true,
    this.card = false,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;

  /// Whether to interleave hairline dividers between children.
  final bool dividers;

  /// Wrap the group in a rounded surface card with inset content.
  final bool card;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividers) rows.add(const Divider());
      rows.add(children[i]);
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );

    if (!card) {
      return Padding(padding: padding, child: column);
    }

    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.cardRadius,
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        child: column,
      ),
    );
  }
}

/// Convenience: header + flat list in one block.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.dividers = true,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(title, trailing: trailing),
        SectionList(dividers: dividers, children: children),
      ],
    );
  }
}
