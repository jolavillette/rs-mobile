import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:share_plus/share_plus.dart';

class FriendLocationDetailScreen extends StatefulWidget {
  const FriendLocationDetailScreen({super.key, required this.location});

  final Location location;

  @override
  State<FriendLocationDetailScreen> createState() => _FriendLocationDetailScreenState();
}

class _FriendLocationDetailScreenState extends State<FriendLocationDetailScreen> {
  bool _isLoading = true;

  /// RsPeerDetails of the node, as rsPeers/getPeerDetails returns it; empty
  /// until loaded, or when the core does not know the node.
  Map<String, dynamic> _det = const {};
  String _version = '';

  /// The node's RetroShare ID (short invite): what another node pastes or
  /// scans to add it as a friend.
  String _retroshareId = '';
  bool _connecting = false;

  /// Short: small and easy to scan. Long: the whole certificate, with the
  /// friend's PGP key.
  bool _longFormat = false;

  Future<void> _openChat() async {
    final peerId = widget.location.rsPeerId;
    if (peerId.isEmpty) return;

    await Navigator.pushNamed(
      context,
      '/peer_chat',
      arguments: {'location': widget.location},
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchPeerDetails();
    // The buttons follow the node's state: read it again while the page
    // is open.
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_connecting) _fetchPeerDetails();
    });
  }

  Timer? _refresh;

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _fetchPeerDetails() async {
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final peerId = widget.location.rsPeerId;
    var det = const <String, dynamic>{};
    var version = '';
    var retroshareId = '';
    if (authToken != null && peerId.isNotEmpty) {
      try {
        final res = await rsApiCall(
          '/rsPeers/getPeerDetails',
          authToken: authToken,
          params: {'sslId': peerId},
        );
        if (res['retval'] == true && res['det'] is Map) {
          det = Map<String, dynamic>.from(res['det'] as Map);
        }
      } catch (e) {
        debugPrint('Error fetching peer details: $e');
      }
      // The state first: the buttons depend on it, and must not wait for
      // the version and the RetroShare ID, which may take long or never
      // come for a node that is away.
      if (!mounted) return;
      setState(() {
        _det = det;
        _isLoading = false;
      });
      try {
        final res = await rsApiCall(
          '/rsGossipDiscovery/getPeerVersion',
          authToken: authToken,
          params: {'id': peerId},
        );
        if (res['retval'] == true) version = res['version']?.toString() ?? '';
      } catch (e) {
        debugPrint('Error fetching peer version: $e');
      }
      try {
        if (_longFormat) {
          final res = await rsApiCall(
            '/rsPeers/GetRetroshareInvite',
            authToken: authToken,
            params: {'sslId': peerId},
          );
          retroshareId =
              (res['retval']?.toString() ?? '').replaceAll('\n', '');
        } else {
          final res = await rsApiCall(
            '/rsPeers/GetShortInvite',
            authToken: authToken,
            params: {'sslId': peerId},
          );
          final invite = res['invite']?.toString() ?? '';
          // The core answers with a link; the ID is its rsInvite parameter.
          final key = Uri.tryParse(invite)?.queryParameters['rsInvite'];
          retroshareId = key != null ? Uri.decodeComponent(key) : invite;
        }
      } catch (e) {
        debugPrint('Error fetching the RetroShare ID: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _det = det;
      _version = version;
      _retroshareId = retroshareId;
      _isLoading = false;
    });
  }

  /// The desktop's "Attempt to connect": asks the core to dial the node now,
  /// then reads its state again while the attempt runs.
  Future<void> _attemptToConnect() async {
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final peerId = widget.location.rsPeerId;
    if (authToken == null || peerId.isEmpty || _connecting) return;
    setState(() => _connecting = true);
    try {
      await rsApiCall(
        '/rsPeers/connectAttempt',
        authToken: authToken,
        params: {'sslId': peerId},
      );
    } catch (e) {
      debugPrint('Error asking for a connection attempt: $e');
    }
    for (final wait in const [2, 4, 6]) {
      await Future<void>.delayed(Duration(seconds: wait));
      if (!mounted) return;
      await _fetchPeerDetails();
    }
    if (mounted) setState(() => _connecting = false);
  }

  /// Removes this node only, or the friend with all their nodes, as the
  /// desktop's "Remove Friend Node" and "Remove Friend". Asks first.
  Future<void> _remove({required bool wholeFriend}) async {
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final friends = Provider.of<FriendLocations>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = widget.location.accountName.isNotEmpty
        ? widget.location.accountName
        : 'this friend';
    final node = widget.location.locationName.isNotEmpty
        ? widget.location.locationName
        : 'this node';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(wholeFriend ? 'Remove friend' : 'Remove node'),
        content: Text(
          wholeFriend
              ? 'Remove $name and all their nodes from your friends? '
                  'You will need their RetroShare ID to add them again.'
              : 'Remove the node "$node" of $name? Their other nodes stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || authToken == null) return;
    var removed = false;
    try {
      final res = wholeFriend
          ? await rsApiCall(
              '/rsPeers/removeFriend',
              authToken: authToken,
              params: {'pgpId': widget.location.rsGpgId},
            )
          : await rsApiCall(
              '/rsPeers/removeFriendLocation',
              authToken: authToken,
              params: {'sslId': widget.location.rsPeerId},
            );
      removed = res['retval'] == true;
    } catch (e) {
      debugPrint('Error removing a friend: $e');
    }
    if (!removed) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove it.')),
      );
      return;
    }
    await friends.fetchfriendLocation();
    navigator.pop();
  }

  bool get _connected {
    final state = _int('connectState');
    return state >= 4 || (_det.isEmpty && widget.location.isOnline);
  }

  void _setFormat(bool long) {
    if (long == _longFormat) return;
    setState(() => _longFormat = long);
    _fetchPeerDetails();
  }

  void _showRetroshareIdQr() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.location.locationName.isNotEmpty
              ? widget.location.locationName
              : 'RetroShare ID',
        ),
        content: SizedBox(
          width: 280,
          height: 280,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: _retroshareId),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _str(String key) => _det[key]?.toString() ?? '';
  int _int(String key) {
    final v = _det[key];
    if (v is num) return v.toInt();
    // 64-bit integers come as {"xint64": n, "xstr64": "n"}
    if (v is Map && v['xint64'] is num) return (v['xint64'] as num).toInt();
    return 0;
  }

  bool _bool(String key) => _det[key] == true;

  /// The desktop's connection status line (StatusDefs::connectStateString):
  /// how the link is made and in which direction, the core's own detail
  /// (address tried, failure), and whether the DHT found the node.
  String _connectionStatus() {
    if (_det.isEmpty) {
      return widget.location.isOnline ? 'Connected' : 'Not connected';
    }
    var s = '';
    var connected = false;
    switch (_int('connectState')) {
      case 2:
        s = 'Trying TCP';
      case 3:
        s = 'Trying UDP';
      case 4:
        s = 'Connected: TCP';
        connected = true;
      case 5:
        s = 'Connected: UDP';
        connected = true;
      case 6:
        s = 'Connected: Tor';
        connected = true;
      case 7:
        s = 'Connected: I2P';
        connected = true;
      case 8:
        s = 'Connected: Unknown';
        connected = true;
      default:
        final state = _int('state');
        if (state & 0x4 != 0) {
          s = 'Connected';
        } else if (state & 0x8 != 0) {
          s = 'Unreachable';
        } else if (state & 0x2 != 0) {
          s = 'Available';
        } else if (state & 0x1 != 0) {
          s = 'Offline';
        } else {
          s = 'Neighbor';
        }
    }
    if (connected) {
      s += _bool('actAsServer')
          ? ' inbound connection'
          : ' outbound connection';
    }
    final extra = _str('connectStateString');
    if (extra.isNotEmpty) s = s.isEmpty ? extra : '$s: $extra';
    if (_bool('foundDHT')) s = s.isEmpty ? 'DHT: Contact' : '$s, DHT: Contact';
    return s;
  }

  String _lastContact() {
    final ts = _int('lastConnect');
    if (ts <= 0) return 'Never';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  static String _hostPort(String host, int port) {
    if (host.isEmpty) return 'None';
    if (port <= 0) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  static String _ago(int seconds) {
    if (seconds < 60) return '$seconds s ago';
    if (seconds < 3600) return '${seconds ~/ 60} min ago';
    if (seconds < 86400) return '${seconds ~/ 3600} h ago';
    return '${seconds ~/ 86400} d ago';
  }

  /// One entry of RsPeerDetails::ipAddressList reads
  /// "ipv4://1.2.3.4:1234    123 sec loc" (or "ext"): the address, then how
  /// long ago the node was seen there and whether it is a local or an
  /// external address. Entries in another form are shown as they are.
  static String _knownAddress(String entry) {
    final m = RegExp(
      r'^\s*(?:ipv4|ipv6)://(\[[^\]]+\]|[^:/\s]+):(\d+)'
      r'(?:\s+(\d+)\s+sec\s+(loc|ext))?',
      caseSensitive: false,
    ).firstMatch(entry);
    if (m == null) return entry.trim();
    var host = m.group(1)!;
    if (host.startsWith('[')) host = host.substring(1, host.length - 1);
    final address =
        _hostPort(host.replaceAll('%25', '%'), int.parse(m.group(2)!));
    final where = m.group(4)?.toLowerCase() == 'loc'
        ? 'local'
        : m.group(4) != null
            ? 'external'
            : '';
    final seen = m.group(3) != null ? _ago(int.parse(m.group(3)!)) : '';
    final notes = [where, seen].where((v) => v.isNotEmpty).join(', ');
    return notes.isEmpty ? address : '$address ($notes)';
  }

  static String _statusText(int status, bool isOnline) {
    if (!isOnline && status == 0) return 'Offline';
    switch (status) {
      case 3:
        return 'Online';
      case 1:
        return 'Away';
      case 2:
        return 'Busy';
      case 4:
        return 'Inactive';
      default:
        return isOnline ? 'Online' : 'Offline';
    }
  }

  static Color _statusColor(int status, bool isOnline) {
    if (!isOnline && status == 0) return Colors.grey;
    switch (status) {
      case 3:
        return Colors.lightGreenAccent;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.red;
      case 4:
        return Colors.orange;
      default:
        return isOnline ? Colors.lightGreenAccent : Colors.grey;
    }
  }

  static IconData _statusIcon(int status, bool isOnline) {
    if (!isOnline && status == 0) return Icons.cloud_off;
    switch (status) {
      case 3:
        return Icons.cloud_done;
      case 1:
        return Icons.access_time;
      case 2:
        return Icons.do_not_disturb;
      case 4:
        return Icons.nights_stay;
      default:
        return isOnline ? Icons.cloud_done : Icons.cloud_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isValidationPending =
        widget.location.statusMessage == 'Validation pending';
    final statusStr = isValidationPending
        ? 'Validation pending'
        : _statusText(widget.location.status, widget.location.isOnline);
    final statusClr = isValidationPending
        ? Colors.amber
        : _statusColor(widget.location.status, widget.location.isOnline);
    final statusIcn = isValidationPending
        ? Icons.hourglass_top
        : _statusIcon(widget.location.status, widget.location.isOnline);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        shadowColor: Colors.transparent,
        title: Text(
          'Friend Details',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 14.5,
          ),
        ),
        leading: BackButton(
          color: theme.colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // SafeArea: the last buttons stay above Android's navigation bar.
      body: SafeArea(
        child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // --- Status badge ---
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest,
                  boxShadow: [
                    BoxShadow(
                      color: statusClr.withOpacity(0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(color: statusClr, width: 3),
                ),
                child: Icon(
                  isValidationPending ? Icons.hourglass_top : Icons.devices,
                  size: 40,
                  color: statusClr,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // --- Account name ---
            Text(
              widget.location.accountName.isNotEmpty
                  ? widget.location.accountName
                  : 'Unknown',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),

            // --- Location name ---
            Text(
              widget.location.locationName.isNotEmpty
                  ? widget.location.locationName
                  : 'No location name',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 12),

            // --- Status chip ---
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: statusClr.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusClr.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcn, size: 18, color: statusClr),
                  const SizedBox(width: 8),
                  Text(
                    statusStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusClr,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            if (!isValidationPending)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        widget.location.rsPeerId.isEmpty ? null : _openChat,
                    icon: const Icon(Icons.message_outlined),
                    label: const Text('Send message'),
                  ),
                ),
              ),
            if (!isValidationPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: SizedBox(
                  width: double.infinity,
                  // Filled, as Send message: an outlined button that is
                  // active looked greyed, and whiter once disabled.
                  child: FilledButton.icon(
                    // Greyed once connected, and while an attempt runs.
                    onPressed: _connecting || _connected
                        ? null
                        : _attemptToConnect,
                    icon: const Icon(Icons.link),
                    label: Text(
                      _connecting ? 'Trying to connect...' : 'Attempt to connect',
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // --- Node info, as the desktop's node details ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(context, 'Node info'),
                  _infoTile(
                    context,
                    'Name',
                    widget.location.accountName.isNotEmpty
                        ? widget.location.accountName
                        : '—',
                    Icons.person,
                  ),
                  _infoTile(
                    context,
                    'Node name',
                    widget.location.locationName.isNotEmpty
                        ? widget.location.locationName
                        : '—',
                    Icons.devices,
                  ),
                  _infoTile(
                    context,
                    'Status',
                    _isLoading ? 'Loading...' : _connectionStatus(),
                    widget.location.isOnline ? Icons.link : Icons.link_off,
                    maxLines: 4,
                  ),
                  _infoTile(
                    context,
                    'Last contact',
                    _isLoading ? 'Loading...' : _lastContact(),
                    Icons.schedule,
                  ),
                  _infoTile(
                    context,
                    'RetroShare version',
                    _isLoading
                        ? 'Loading...'
                        : (_version.isNotEmpty ? _version : 'Unknown'),
                    Icons.info_outline,
                  ),
                  _infoTile(
                    context,
                    'Node ID',
                    widget.location.rsPeerId.isNotEmpty
                        ? widget.location.rsPeerId
                        : '—',
                    Icons.vpn_key,
                  ),
                  _infoTile(
                    context,
                    'PGP ID',
                    widget.location.rsGpgId.isNotEmpty
                        ? widget.location.rsGpgId
                        : '—',
                    Icons.security,
                  ),
                  if (widget.location.statusMessage.isNotEmpty &&
                      !isValidationPending)
                    _infoTile(
                      context,
                      'Status message',
                      widget.location.statusMessage,
                      Icons.chat,
                      maxLines: 4,
                    ),
                  const SizedBox(height: 12),
                  _sectionTitle(context, 'Connectivity'),
                  if (_isLoading)
                    _infoTile(
                      context,
                      'Addresses',
                      'Loading...',
                      Icons.settings_ethernet,
                    )
                  else if (_bool('isHiddenNode'))
                    _infoTile(
                      context,
                      'Hidden address',
                      _hostPort(
                        _str('hiddenNodeAddress'),
                        _int('hiddenNodePort'),
                      ),
                      Icons.vpn_lock,
                    )
                  else ...[
                    _infoTile(
                      context,
                      'Local address',
                      _hostPort(_str('localAddr'), _int('localPort')),
                      Icons.settings_ethernet,
                    ),
                    _infoTile(
                      context,
                      'External address',
                      _hostPort(_str('extAddr'), _int('extPort')),
                      Icons.language,
                    ),
                    if (_str('dyndns').isNotEmpty)
                      _infoTile(
                        context,
                        'Dynamic DNS',
                        _str('dyndns'),
                        Icons.dns,
                      ),
                  ],
                  if (!_isLoading) _knownAddressesTile(context),
                  if (_retroshareId.isNotEmpty || _longFormat) ...[
                    const SizedBox(height: 12),
                    _sectionTitle(context, 'RetroShare ID'),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Short')),
                        ButtonSegment(value: true, label: Text('Long')),
                      ],
                      selected: {_longFormat},
                      onSelectionChanged: (s) => _setFormat(s.first),
                    ),
                    const SizedBox(height: 10),
                    _infoTile(
                      context,
                      'Give it to another node to add this one as a friend',
                      _retroshareId.isEmpty ? 'Not available' : _retroshareId,
                      Icons.badge_outlined,
                      maxLines: 6,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => SharePlus.instance
                                .share(ShareParams(text: _retroshareId)),
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showRetroshareIdQr,
                            icon: const Icon(Icons.qr_code),
                            label: const Text('QR code'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.location.rsPeerId.isEmpty
                          ? null
                          : () => _remove(wholeFriend: false),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove node'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.location.rsGpgId.isEmpty
                          ? null
                          : () => _remove(wholeFriend: true),
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('Remove friend'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _knownAddressesTile(BuildContext context) {
    final entries = (_det['ipAddressList'] as List?)
            ?.map((e) => _knownAddress(e.toString()))
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    return _infoTile(
      context,
      'Known addresses (${entries.length})',
      entries.isEmpty ? 'No address history' : entries.join('\n'),
      Icons.history,
      maxLines: 30,
    );
  }

  Widget _infoTile(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: valueColor ?? theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: maxLines,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Oxygen',
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy to clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
