import 'package:flutter/material.dart';

/// What a screen shows while it waits: the platform's progress circle, in
/// the colour of the theme.
class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 32,
      child: CircularProgressIndicator(strokeWidth: 3),
    );
  }
}
