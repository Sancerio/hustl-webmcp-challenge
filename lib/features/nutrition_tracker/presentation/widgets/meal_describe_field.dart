import 'package:flutter/material.dart';
import 'package:hustl_app/app/theme/app_spacing.dart';

/// Lets the user type or dictate a meal description and request an estimate.
///
/// Dictation comes from the OS keyboard's microphone — this widget adds no
/// speech packages or mic permissions of its own. The [onEstimate] callback
/// fires with the trimmed description; the parent owns the consent gate, the
/// AI call, and the busy state.
class MealDescribeField extends StatefulWidget {
  const MealDescribeField({
    super.key,
    required this.onEstimate,
    required this.enabled,
  });

  final ValueChanged<String> onEstimate;
  final bool enabled;

  @override
  State<MealDescribeField> createState() => _MealDescribeFieldState();
}

class _MealDescribeFieldState extends State<MealDescribeField> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onEstimate(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Describe your meal',
            hintText: 'e.g. grilled chicken with rice and broccoli',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.x1),
        FilledButton.icon(
          onPressed: widget.enabled && _hasText ? _submit : null,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Estimate'),
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          'Tip: tap the keyboard mic to dictate. Always review before logging.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
