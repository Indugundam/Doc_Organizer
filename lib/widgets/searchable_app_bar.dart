import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

/// AppBar that swaps its title for a search field when the search icon is
/// tapped. Shared by [HomeScreen] and [FolderScreen] so both filter the
/// same way.
class SearchableAppBar extends StatefulWidget implements PreferredSizeWidget {
  const SearchableAppBar({
    super.key,
    required this.title,
    required this.hintText,
    required this.onQueryChanged,
    this.actions = const [],
  });

  final String title;
  final String hintText;
  final ValueChanged<String> onQueryChanged;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<SearchableAppBar> createState() => _SearchableAppBarState();
}

class _SearchableAppBarState extends State<SearchableAppBar> {
  bool _searching = false;
  final _controller = TextEditingController();

  void _stopSearching() {
    _controller.clear();
    widget.onQueryChanged('');
    setState(() => _searching = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: _searching
          ? TextField(
              controller: _controller,
              autofocus: true,
              onChanged: widget.onQueryChanged,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.all(4),
              ),
            )
          : Text(widget.title),
      actions: [
        IconButton(
          icon: Icon(
            _searching
                ? FluentIcons.dismiss_24_regular
                : FluentIcons.search_24_regular,
          ),
          tooltip: _searching ? 'Close search' : 'Search',
          onPressed: () {
            if (_searching) {
              _stopSearching();
            } else {
              setState(() => _searching = true);
            }
          },
        ),
        if (!_searching) ...widget.actions,
      ],
    );
  }
}
