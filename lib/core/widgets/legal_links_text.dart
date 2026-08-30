import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import 'hustl_snack.dart';

/// A sentence with tappable "Terms" and "Privacy Policy" links to the hosted
/// legal pages. Shared by the guest account sheet and the onboarding welcome
/// screen so both surfaces read identically and never drift.
///
/// Each link gets its own [Semantics] node (via [WidgetSpan]) rather than one
/// label covering the whole sentence, so a screen reader can target "Terms"
/// and "Privacy Policy" independently.
class LegalLinksText extends StatelessWidget {
  const LegalLinksText({
    super.key,
    required this.leading,
    this.trailing = '.',
    this.textAlign = TextAlign.center,
    this.style,
  });

  /// Text before the two links, e.g. "By continuing you agree to our".
  final String leading;

  /// Text after the two links, e.g. '.'.
  final String trailing;

  final TextAlign textAlign;
  final TextStyle? style;

  Future<void> _open(BuildContext context, String path) async {
    final uri = Uri.parse('${ApiConfig.authBaseUrl}$path');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      HustlSnack.show(
        context,
        "Couldn't open that page",
        variant: HustlSnackVariant.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        style ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    Widget link(String label, String path, String semanticLabel) {
      return Semantics(
        link: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => _open(context, path),
          child: Text(label, style: linkStyle),
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '$leading '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: link('Terms', '/terms/', 'Terms of service'),
          ),
          const TextSpan(text: ' and '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: link('Privacy Policy', '/privacy', 'Privacy policy'),
          ),
          TextSpan(text: trailing),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
