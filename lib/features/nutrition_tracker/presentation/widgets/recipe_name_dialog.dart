import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Prompts for a recipe name with a single text field, defaulting to "Meal".
/// Returns the trimmed name, or null if the user cancels. Shared by every
/// "save a recipe" entry point (the diary selection bar and the plate review).
Future<String?> promptRecipeName(
  BuildContext context, {
  String initialName = 'Meal',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RecipeNameDialog(initialName: initialName),
  );
}

/// Single-field dialog body for [promptRecipeName]. The field starts fully
/// selected so the default ("Meal") can be overtyped in one gesture; an empty
/// name falls back to the default.
class _RecipeNameDialog extends StatefulWidget {
  const _RecipeNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RecipeNameDialog> createState() => _RecipeNameDialogState();
}

class _RecipeNameDialogState extends State<_RecipeNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialName.length,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    context.pop(name.isEmpty ? widget.initialName : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this recipe'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        maxLength: 80,
        inputFormatters: [LengthLimitingTextInputFormatter(80)],
        decoration: const InputDecoration(
          labelText: 'Recipe name',
          hintText: 'Meal',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
