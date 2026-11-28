import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = Provider.of<AccountCredentials>(context).loggedinAccount;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Preferences'),
        backgroundColor: theme.colorScheme.surface,
        shadowColor: Colors.transparent,
        leading: BackButton(
          color: theme.colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // The desktop's title: profile name (node name).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                account == null
                    ? 'RetroShare'
                    : '${account.pgpName} (${account.locationName})',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            // Settings Options Container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(128),
                  ),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                child: Column(
                  children: [
                    // The sections of the desktop's Preferences, with
                    // their names and in their order.
                    _settingsTile(
                      context: context,
                      icon: Icons.person_rounded,
                      iconBgColor: Colors.blue,
                      title: 'Node',
                      subtitle: 'Profile, this node, RetroShare ID',
                      onTap: () {
                        Navigator.pushNamed(context, '/node');
                      },
                    ),
                    _divider(theme),
                    _settingsTile(
                      context: context,
                      icon: Icons.wifi_rounded,
                      iconBgColor: Colors.teal,
                      title: 'Network',
                      subtitle: 'IP Address, Port, DHT status',
                      onTap: () {
                        Navigator.pushNamed(context, '/network_settings');
                      },
                    ),
                    _divider(theme),
                    _settingsTile(
                      context: context,
                      icon: Icons.chat_rounded,
                      iconBgColor: Colors.orange,
                      title: 'Chats',
                      subtitle: 'Theme, bubble style',
                      onTap: () {
                        Navigator.pushNamed(context, '/chat_settings');
                      },
                    ),
                    _divider(theme),
                    _settingsTile(
                      context: context,
                      icon: Icons.palette_rounded,
                      iconBgColor: Colors.pink,
                      title: 'Appearance',
                      subtitle: 'Device, light or dark theme',
                      onTap: () {
                        Navigator.pushNamed(context, '/appearance');
                      },
                    ),
                    _divider(theme),
                    _settingsTile(
                      context: context,
                      icon: Icons.widgets_rounded,
                      iconBgColor: Colors.indigo,
                      title: 'Permissions',
                      subtitle: 'Every service the core runs',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/mobile_services_settings',
                        );
                      },
                    ),
                    _divider(theme),
                    _settingsTile(
                      context: context,
                      icon: Icons.info_rounded,
                      iconBgColor: Colors.grey,
                      title: 'About',
                      subtitle: 'Versions and libraries',
                      onTap: () {
                        Navigator.pushNamed(context, '/about');
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 64,
      endIndent: 16,
      color: theme.colorScheme.outlineVariant.withAlpha(100),
    );
  }

  Widget _settingsTile({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBgColor.withAlpha(30),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconBgColor,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
