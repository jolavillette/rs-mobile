import 'package:flutter/material.dart';
import 'package:retroshare/common/rs_tokens.dart';

/// One entry of the [ScrollNavBar].
class ScrollNavItem {
  const ScrollNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selectedIcon,
    this.color,
  });

  final String label;
  final Widget icon;
  final Widget? selectedIcon;
  final VoidCallback onTap;

  /// Ink of an entry that is not a page, as Quit.
  final Color? color;
}

/// The bottom navigation of the home: every entry of the menu on one line,
/// scrolled sideways when the screen is too narrow for all of them. The
/// entries are narrow enough for the next one to show at the edge.
class ScrollNavBar extends StatefulWidget {
  const ScrollNavBar({
    required this.items,
    required this.selectedIndex,
    super.key,
  });

  final List<ScrollNavItem> items;
  final int selectedIndex;

  @override
  State<ScrollNavBar> createState() => _ScrollNavBarState();
}

class _ScrollNavBarState extends State<ScrollNavBar> {
  static const double _itemWidth = 72;
  static const double _height = 64;

  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _showSelected();
  }

  @override
  void didUpdateWidget(ScrollNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _showSelected();
  }

  /// Scrolls the selected entry into view, once it is laid out.
  void _showSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.selectedIndex >= _keys.length) return;
      final entry = _keys[widget.selectedIndex].currentContext;
      if (entry == null) return;
      Scrollable.ensureVisible(
        entry,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    while (_keys.length < widget.items.length) {
      _keys.add(GlobalKey());
    }
    return Material(
      color: rs.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: rs.lineSoft)),
          ),
          child: SizedBox(
            height: _height,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  // Few entries on a wide bar are spread over its width.
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        _entry(context, i),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, int index) {
    final rs = context.rs;
    final item = widget.items[index];
    final selected = index == widget.selectedIndex;
    final ink = item.color ?? (selected ? rs.ink : rs.inkDim);
    return InkWell(
      key: _keys[index],
      onTap: item.onTap,
      child: SizedBox(
        width: _itemWidth,
        height: _height,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? rs.selectSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(RsScale.rFull),
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: ink, size: 24),
                child: Center(
                  child: selected ? item.selectedIcon ?? item.icon : item.icon,
                ),
              ),
            ),
            const SizedBox(height: RsScale.s1),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: RsScale.tMicro,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
