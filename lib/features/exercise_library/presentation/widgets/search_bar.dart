import 'package:flutter/material.dart';

class ExerciseSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged; // Callback for text changes
  final VoidCallback? onFilterTap; // Open filter sheet
  final int activeFilterCount; // number of active filters

  const ExerciseSearchBar({
    super.key,
    this.onChanged,
    this.onFilterTap,
    this.activeFilterCount = 0,
  });

  @override
  State<ExerciseSearchBar> createState() => _ExerciseSearchBarState();
}

class _ExerciseSearchBarState extends State<ExerciseSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Optionally, listen to controller changes here if more complex logic (like debounce) is needed
    // _controller.addListener(() { ... });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: TextField(
        controller: _controller,
        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search exercises...',
          hintStyle: TextStyle(color: theme.colorScheme.onSurface),
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface),
          suffixIcon: widget.onFilterTap == null
              ? null
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Filter',
                      icon: const Icon(Icons.filter_list),
                      color: theme.colorScheme.onSurface,
                      onPressed: widget.onFilterTap,
                    ),
                    if (widget.activeFilterCount > 0)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.activeFilterCount.toString(),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
          fillColor: theme.colorScheme.surfaceContainerHighest,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}
