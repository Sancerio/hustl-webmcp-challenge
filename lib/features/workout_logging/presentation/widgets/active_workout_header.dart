import 'package:flutter/material.dart';
import '../../domain/models/workout_session.dart';

/// Scrolling body header for the active workout. Hosts the editable workout
/// name. The live elapsed duration now lives always-visible in the fixed app
/// bar (see `LiveElapsedLabel`), so this header no longer renders a duration
/// badge or runs its own ticker.
class ActiveWorkoutHeader extends StatefulWidget {
  final WorkoutSession session;
  final Function(String) onNameChanged;
  final Widget? leading;

  /// Retained for call-site compatibility; the header no longer ticks.
  final bool pauseTicker;

  const ActiveWorkoutHeader({
    super.key,
    required this.session,
    required this.onNameChanged,
    this.leading,
    this.pauseTicker = false,
  });

  @override
  State<ActiveWorkoutHeader> createState() => _ActiveWorkoutHeaderState();
}

class _ActiveWorkoutHeaderState extends State<ActiveWorkoutHeader> {
  late String _displayedWorkoutName;
  bool _isEditing = false;
  late TextEditingController _editingController;

  @override
  void initState() {
    super.initState();
    _displayedWorkoutName = widget.session.name;
    _editingController = TextEditingController(text: _displayedWorkoutName);
  }

  @override
  void didUpdateWidget(ActiveWorkoutHeader oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.session.name != widget.session.name) {
      _displayedWorkoutName = widget.session.name;
      _editingController.text = _displayedWorkoutName;
    }
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }

  void _startEditing() {
    _editingController.text = _displayedWorkoutName;
    setState(() {
      _isEditing = true;
    });
  }

  void _saveEditing() {
    final newName = _editingController.text.trim();
    if (newName.isNotEmpty) {
      widget.onNameChanged(newName);
      setState(() {
        _displayedWorkoutName = newName;
        _isEditing = false;
      });
    } else {
      // If empty, cancel editing and revert to previous name
      setState(() {
        _isEditing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: _isEditing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _editingController,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Workout name',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    autofocus: true,
                    onSubmitted: (_) => _saveEditing(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.check,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: _saveEditing,
                ),
              ],
            )
          : GestureDetector(
              onTap: _startEditing,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _displayedWorkoutName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      // Wrap long names onto a second line instead of cutting
                      // them off with an ellipsis after one line; only very long
                      // names still ellipsize.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 16, color: theme.colorScheme.primary),
                ],
              ),
            ),
    );
  }
}
