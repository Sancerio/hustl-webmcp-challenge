import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/models/connection.dart';

/// The leading avatar for a connection row: the official brand mark for a known
/// [vendor], or the generic hub glyph for unknown loopback CLIs / clients.
///
/// SECURITY: for hosted vendors (Claude, ChatGPT) the brand is keyed off the
/// trusted [vendor], derived server-side from the VALIDATED OAuth redirect
/// domain — never the attacker-controlled name. Codex is the exception: it's a
/// loopback CLI with no verifiable domain, so its mark is a cosmetic hint from
/// the name (the row shows no "via <domain>", which stays the real trust signal).
///
/// The marks are the official monochrome logos (Claude/OpenAI from simple-icons,
/// Codex from LobeHub), tinted per brand: Claude in its terracotta; ChatGPT and
/// Codex in `onSurface` so the mark stays visible in both light and dark themes.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.vendor, this.size = 40});

  /// The trusted vendor that decides which mark renders.
  final ConnectionVendor vendor;

  /// Diameter of the circular holder.
  final double size;

  String? get _asset => switch (vendor) {
    ConnectionVendor.claude => 'assets/icons/brand_claude.svg',
    ConnectionVendor.chatgpt => 'assets/icons/brand_chatgpt.svg',
    ConnectionVendor.codex => 'assets/icons/brand_codex.svg',
    ConnectionVendor.unknown => null,
  };

  Color _tint(ColorScheme colors) => switch (vendor) {
    ConnectionVendor.claude => AppColors.brandClaudeTerracotta,
    ConnectionVendor.chatgpt => colors.onSurface,
    ConnectionVendor.codex => colors.onSurface,
    ConnectionVendor.unknown => colors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final asset = _asset;
    final glyphSize = size * 0.5;
    final tint = _tint(colors);

    // Decorative: the row's Semantics already announces vendor + access, so the
    // glyph must not add a redundant unlabeled node.
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: asset != null
            ? SvgPicture.asset(
                asset,
                width: glyphSize,
                height: glyphSize,
                colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
              )
            : Icon(Icons.hub_outlined, size: glyphSize, color: tint),
      ),
    );
  }
}
