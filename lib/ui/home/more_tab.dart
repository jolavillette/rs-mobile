import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:retroshare/common/logout.dart';
import 'package:retroshare/common/quit.dart';
import 'package:retroshare/common/rs_tokens.dart';

/// More: Preferences (named and ordered as the desktop's), Statistics and,
/// on Android, Quit; on iOS, Log out.
class MoreTab extends StatelessWidget {
  const MoreTab({required this.open, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: RsScale.s2),
      children: [
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Preferences'),
          onTap: () => open('/settings'),
        ),
        ListTile(
          leading: const Icon(Icons.query_stats_outlined),
          title: const Text('Statistics'),
          onTap: () => open('/statistics'),
        ),
        const Divider(),
        if (Platform.isAndroid)
          ListTile(
            leading: Icon(Icons.power_settings_new, color: context.rs.downInk),
            title: Text('Quit', style: TextStyle(color: context.rs.downInk)),
            onTap: () => confirmAndQuit(context),
          ),
        if (Platform.isIOS)
          ListTile(
            leading: Icon(Icons.logout, color: context.rs.downInk),
            title: Text('Log out', style: TextStyle(color: context.rs.downInk)),
            onTap: () => confirmAndLogOut(context),
          ),
      ],
    );
  }
}
