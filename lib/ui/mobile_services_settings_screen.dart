import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/mobile_services.dart';
import 'package:retroshare/apiUtils/service_ids.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// Every service the core runs, in three groups: those the app needs (shown,
/// not switchable), those the app has no page for (off; the app turns them
/// off at every login, turning one on here asks for confirmation and is
/// remembered for this node), and any other service the core reports.
class MobileServicesSettingsScreen extends StatefulWidget {
  const MobileServicesSettingsScreen({super.key});

  @override
  State<MobileServicesSettingsScreen> createState() =>
      _MobileServicesSettingsScreenState();
}

class _MobileServicesSettingsScreenState
    extends State<MobileServicesSettingsScreen> {
  bool _isLoading = true;

  /// The services the core runs: 16-bit type -> the core's name.
  Map<int, String> _coreServices = {};

  /// On or off, by service type.
  final Map<int, bool> _on = {};
  final Set<int> _updating = {};

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
      final services = await coreServices(authToken);
      for (final type in services.keys) {
        final permissions = await RsServiceControl.getServicePermissions(
          rsFullServiceId(type),
          authToken,
        );
        _on[type] = isServiceOn(permissions);
      }
      _coreServices = services;
    } catch (error) {
      debugPrint('Failed to load the services: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load the services.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirmTurnOn(MobileService service) async {
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text('Turn on ${service.name}?'),
        content: Text(
          '${service.role}\n\n'
          'RetroShare Mobile cannot show it yet. Turned on, it makes this '
          'phone use more CPU, mobile data, battery and storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    return turnOn == true;
  }

  Future<void> _setServiceOn(MobileService service, bool on) async {
    final auth = Provider.of<AccountCredentials>(context, listen: false);
    final authToken = auth.authtoken;
    final locationId = auth.loggedinAccount?.locationId;
    if (authToken == null || locationId == null) return;
    if (on && !await _confirmTurnOn(service)) return;
    if (!mounted) return;

    setState(() => _updating.add(service.type));
    try {
      final done =
          await RsServiceControl.setServiceEnabled(service.fullId, on, authToken);
      if (!done) throw Exception('updateServicePermissions returned false');
      await setOptedIn(locationId, service.type, on);
      if (mounted) setState(() => _on[service.type] = on);
    } catch (error) {
      debugPrint('Failed to update service permission: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update service setting.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating.remove(service.type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needed =
        neededServices.where((s) => _coreServices.containsKey(s.type));
    final optional =
        optionalServices.where((s) => _coreServices.containsKey(s.type));
    final listed = {
      ...neededServices.map((s) => s.type),
      ...optionalServices.map((s) => s.type),
    };
    final others = (_coreServices.keys.where((t) => !listed.contains(t))
        .toList()
      ..sort());

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Every service the RetroShare core runs on this phone. The '
                  'services the app has no page for are off: they would use '
                  'CPU, mobile data, battery and storage for nothing you can '
                  'see. The app turns them off at every start, except the '
                  'ones you turn on here.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                _section(
                  'Needed by the app',
                  [for (final s in needed) _statusTile(s.name, s.role, s.type)],
                ),
                _section(
                  'No page in the app',
                  [for (final s in optional) _serviceSwitch(s)],
                ),
                if (others.isNotEmpty)
                  _section('Other services', [
                    for (final type in others)
                      _statusTile(
                        _coreServices[type]!.isEmpty
                            ? 'Service 0x${type.toRadixString(16).padLeft(4, '0')}'
                            : _coreServices[type]!,
                        'Not handled by the app.',
                        type,
                      ),
                  ]),
              ],
            ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    final theme = Theme.of(context);
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
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
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  tiles[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A service shown with its state, without a switch.
  Widget _statusTile(String name, String role, int type) {
    final theme = Theme.of(context);
    final on = _on[type] ?? false;
    return ListTile(
      leading: const Icon(Icons.lock_outline_rounded),
      title: Text(name),
      subtitle: Text(role),
      trailing: Text(
        on ? 'On' : 'Off',
        style: theme.textTheme.labelLarge?.copyWith(
          color: on ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
      ),
    );
  }

  Widget _serviceSwitch(MobileService service) {
    final updating = _updating.contains(service.type);
    return SwitchListTile(
      secondary: updating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_alt_rounded),
      title: Text(service.name),
      subtitle: Text(service.role),
      value: _on[service.type] ?? false,
      onChanged: updating ? null : (on) => _setServiceOn(service, on),
    );
  }
}
