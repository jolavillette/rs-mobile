import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/mobile_services.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// The core services the app has no page for. They are off: the app turns
/// them off at every login. Turning one on here asks for confirmation and is
/// remembered for this node, so the next login leaves it on.
class MobileServicesSettingsScreen extends StatefulWidget {
  const MobileServicesSettingsScreen({super.key});

  @override
  State<MobileServicesSettingsScreen> createState() =>
      _MobileServicesSettingsScreenState();
}

class _MobileServicesSettingsScreenState
    extends State<MobileServicesSettingsScreen> {
  bool _isLoading = true;

  /// On or off, by service type, for the services this core runs.
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
      for (final service in optionalServices) {
        final permissions = await RsServiceControl.getServicePermissions(
          service.fullId,
          authToken,
        );
        if (isServiceKnown(permissions, service)) {
          _on[service.type] = isServiceOn(permissions);
        }
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

  Future<bool> _confirmTurnOn(OptionalService service) async {
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

  Future<void> _setServiceOn(OptionalService service, bool on) async {
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
    final shown = optionalServices.where((s) => _on.containsKey(s.type));
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile Services')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'RetroShare Mobile has no page for these services, so they are '
            'off: on a phone they would use CPU, mobile data, battery and '
            'storage for nothing you can see. The app turns them off at every '
            'start, except the ones you turn on here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
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
                  for (final service in shown) ...[
                    if (service != shown.first)
                      const Divider(height: 1, indent: 64),
                    _serviceSwitch(service),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _serviceSwitch(OptionalService service) {
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
      onChanged:
          updating ? null : (on) => _setServiceOn(service, on),
    );
  }
}
