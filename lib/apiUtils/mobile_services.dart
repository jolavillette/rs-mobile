import 'package:flutter/foundation.dart';
import 'package:retroshare/apiUtils/service_ids.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A core service the app has no page for: on a phone it costs CPU, mobile
/// data, battery or storage for nothing the user can see. The app turns it
/// off at every login, unless the user turned it on in Mobile Services.
class OptionalService {
  const OptionalService(this.type, this.name, this.role);

  /// 16-bit service type.
  final int type;
  final String name;

  /// What the service does, shown under its switch and in the warning.
  final String role;

  int get fullId => rsFullServiceId(type);
}

const optionalServices = <OptionalService>[
  OptionalService(
    RsServiceTypes.forums,
    'Forums',
    "Synchronizes your friends' forums.",
  ),
  OptionalService(
    RsServiceTypes.channels,
    'Channels',
    "Synchronizes your friends' channels, the heaviest of these services.",
  ),
  OptionalService(
    RsServiceTypes.boards,
    'Boards',
    "Synchronizes your friends' boards.",
  ),
  OptionalService(
    RsServiceTypes.circles,
    'Circles',
    "Synchronizes your friends' circles.",
  ),
  OptionalService(
    RsServiceTypes.calendar,
    'Calendar',
    "Synchronizes your friends' calendars.",
  ),
  OptionalService(
    RsServiceTypes.messages,
    'Mail',
    'Mail between friends.',
  ),
  OptionalService(
    RsServiceTypes.gxsMails,
    'Distant mail (GXS Trans)',
    'Stores and relays the encrypted distant mail of the network for 15 days.',
  ),
  OptionalService(
    RsServiceTypes.globalRouter,
    'Global router',
    'Routes, relays and caches distant mail for other nodes.',
  ),
  OptionalService(
    RsServiceTypes.fileDatabase,
    'File lists',
    'Exchanges the lists of shared files with your friends.',
  ),
];

/// Whether [permissions] (rsServiceControl) let the service talk to friends.
bool isServiceOn(Map<String, dynamic> permissions) {
  final allowed = permissions['mPeersAllowed'];
  return permissions['mDefaultAllowed'] == true ||
      (allowed is List && allowed.isNotEmpty);
}

/// Whether [permissions] belong to a service this core runs: for an unknown
/// service the core answers with empty permissions (service id 0).
bool isServiceKnown(Map<String, dynamic> permissions, OptionalService service) =>
    permissions['mServiceId'] == service.fullId;

String _optedInKey(String locationId) => 'optional_services_on_$locationId';

/// The optional services the user turned on for this node (location).
Future<Set<int>> optedInServices(String locationId) async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_optedInKey(locationId)) ?? const <String>[])
      .map(int.tryParse)
      .whereType<int>()
      .toSet();
}

Future<void> setOptedIn(String locationId, int type, bool on) async {
  final prefs = await SharedPreferences.getInstance();
  final types = await optedInServices(locationId);
  on ? types.add(type) : types.remove(type);
  await prefs.setStringList(
    _optedInKey(locationId),
    types.map((t) => '$t').toList(),
  );
}

/// Turns off every optional service the user did not turn on in the app.
/// Called at each login: a service turned on another way (the web UI for
/// instance) goes off again. Errors are logged, never thrown: the login must
/// not fail on them.
Future<void> turnOffOptionalServices(AuthToken token, String locationId) async {
  final optedIn = await optedInServices(locationId);
  for (final service in optionalServices) {
    if (optedIn.contains(service.type)) continue;
    try {
      final permissions =
          await RsServiceControl.getServicePermissions(service.fullId, token);
      if (!isServiceKnown(permissions, service) || !isServiceOn(permissions)) {
        continue;
      }
      final done =
          await RsServiceControl.setServiceEnabled(service.fullId, false, token);
      debugPrint(
        done
            ? 'Mobile services: ${service.name} turned off'
            : 'Mobile services: the core did not turn ${service.name} off',
      );
    } catch (error) {
      debugPrint('Mobile services: cannot turn ${service.name} off: $error');
    }
  }
}
