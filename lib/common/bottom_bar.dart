import 'package:flutter/material.dart';
import 'package:retroshare/common/styles.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.child,
    this.minHeight = appBarHeight,
    this.maxHeight = appBarHeight,
  });
  final Widget child;
  final double minHeight;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // Android 15 and later draw apps edge to edge, under the system navigation
    // bar: grow by its height and keep the content above it.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: minHeight + bottomInset,
        maxHeight: maxHeight + bottomInset,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.black12
                  : Colors.white10,
              blurRadius: 20,
              spreadRadius: 5,
              offset: const Offset(
                0,
                15,
              ),
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(appBarHeight / 3),
            topRight: Radius.circular(appBarHeight / 3),
          ),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: child,
        ),
      ),
    );
  }
}
