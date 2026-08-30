import 'package:flutter/material.dart';

import '../../domain/models/connection.dart';
import 'brand_mark.dart';
import 'connect_help_data.dart';

/// The leading mark for a connect client: the trusted vendor brand mark when
/// known, or a quiet glyph holder (tinted circle + fallback icon) for CLIs that
/// have no brand mark. Shared by the picker tile and the article heading.
class ConnectClientGlyph extends StatelessWidget {
  const ConnectClientGlyph({super.key, required this.client, this.size = 40});

  final ConnectHelpClient client;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (client.vendor != ConnectionVendor.unknown) {
      return BrandMark(vendor: client.vendor, size: size);
    }
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(client.fallbackIcon, size: size / 2, color: colors.primary),
    );
  }
}
