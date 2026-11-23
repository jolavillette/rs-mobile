import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';

/// Preferences > Appearance, as on the desktop: the theme.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AdaptiveTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<AdaptiveThemeMode>(
            segments: const [
              ButtonSegment(
                value: AdaptiveThemeMode.system,
                label: Text('Device'),
              ),
              ButtonSegment(
                value: AdaptiveThemeMode.light,
                label: Text('Light'),
              ),
              ButtonSegment(
                value: AdaptiveThemeMode.dark,
                label: Text('Dark'),
              ),
            ],
            selected: {theme.mode},
            showSelectedIcon: false,
            onSelectionChanged: (modes) => theme.setThemeMode(modes.first),
          ),
        ],
      ),
    );
  }
}
