import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/service_ids.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

class MobileServicesSettingsScreen extends StatefulWidget {
  const MobileServicesSettingsScreen({super.key});

  @override
  State<MobileServicesSettingsScreen> createState() =>
      _MobileServicesSettingsScreenState();
}

class _MobileServicesSettingsScreenState
    extends State<MobileServicesSettingsScreen> {
  // Full service ids: the core matches permissions on those only.
  static final int _forumsServiceId = rsFullServiceId(RsServiceTypes.forums);
  static final int _boardsServiceId = rsFullServiceId(RsServiceTypes.boards);
  static final int _channelsServiceId =
      rsFullServiceId(RsServiceTypes.channels);
  static final int _mailsServiceId = rsFullServiceId(RsServiceTypes.gxsMails);

  bool _isLoading = true;
  final Map<int, bool> _servicesEnabled = {};
  final Set<int> _servicesUpdating = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadServices());
  }

  Future<void> _loadServices() async {
    try {
      final authToken =
          Provider.of<AccountCredentials>(context, listen: false).authtoken;
      if (authToken == null) return;
      await RsServiceControl.setServiceEnabled(
        _mailsServiceId,
        false,
        authToken,
      );
      for (final serviceId in [
        _forumsServiceId,
        _channelsServiceId,
        _boardsServiceId,
      ]) {
        final permissions =
            await RsServiceControl.getServicePermissions(serviceId, authToken);
        _servicesEnabled[serviceId] = permissions['mDefaultAllowed'] == true;
      }
    } catch (error) {
      debugPrint('Failed to load service permissions: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load mobile services.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setServiceEnabled(int serviceId, bool enabled) async {
    setState(() => _servicesUpdating.add(serviceId));
    try {
      final authToken =
          Provider.of<AccountCredentials>(context, listen: false).authtoken;
      if (authToken == null) return;
      final success = await RsServiceControl.setServiceEnabled(
        serviceId,
        enabled,
        authToken,
      );
      if (!success) throw Exception('updateServicePermissions returned false');
      if (mounted) setState(() => _servicesEnabled[serviceId] = enabled);
    } catch (error) {
      debugPrint('Failed to update service permission: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update service setting.')),
        );
      }
    } finally {
      if (mounted) setState(() => _servicesUpdating.remove(serviceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Services')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose which services this mobile node synchronizes with friends.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(128),
              ),
            ),
            child: Column(
              children: [
                _serviceSwitch('Forums', _forumsServiceId),
                const Divider(height: 1, indent: 64),
                _serviceSwitch('Channels', _channelsServiceId),
                const Divider(height: 1, indent: 64),
                _serviceSwitch('Boards', _boardsServiceId),
                const Divider(height: 1, indent: 64),
                const SwitchListTile(
                  secondary: Icon(Icons.mail_outline_rounded),
                  title: Text('Mail'),
                  subtitle: Text('Not used by RetroShare Mobile'),
                  value: false,
                  onChanged: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceSwitch(String title, int serviceId) {
    final updating = _servicesUpdating.contains(serviceId);
    return SwitchListTile(
      secondary: updating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_alt_rounded),
      title: Text(title),
      subtitle: const Text('Synchronize with friends'),
      value: _servicesEnabled[serviceId] ?? false,
      onChanged: _isLoading || updating
          ? null
          : (enabled) => _setServiceEnabled(serviceId, enabled),
    );
  }
}
