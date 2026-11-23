import 'dart:io' show Platform;

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:retroshare/common/quit.dart';
import 'package:retroshare/common/rs_tokens.dart';

/// More, as in the web UI: the destinations that do not need a tab.
class MoreTab extends StatelessWidget {
  const MoreTab({required this.open, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final theme = AdaptiveTheme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: RsScale.s2),
      children: [
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () => open('/settings'),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RsScale.s4,
            RsScale.s3,
            RsScale.s4,
            RsScale.s2,
          ),
          child: Text('Appearance', style: text.labelMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RsScale.s4),
          child: SegmentedButton<AdaptiveThemeMode>(
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
        ),
        const SizedBox(height: RsScale.s3),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About'),
          onTap: () => open('/about'),
        ),
        if (Platform.isAndroid)
          ListTile(
            leading: Icon(Icons.power_settings_new, color: context.rs.downInk),
            title: Text('Quit', style: TextStyle(color: context.rs.downInk)),
            onTap: () => confirmAndQuit(context),
          ),
      ],
    );
  }
}
