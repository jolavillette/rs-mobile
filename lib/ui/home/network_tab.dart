import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// The web UI's presence values: 0 offline, 1 away, 2 busy, 3 online,
/// 4 inactive.
String statusLabel(int status, bool isOnline) {
  final value = status == 0 && isOnline ? 3 : status;
  return const ['Offline', 'Away', 'Busy', 'Online', 'Inactive']
          .elementAtOrNull(value) ??
      (isOnline ? 'Online' : 'Offline');
}

Color statusColor(BuildContext context, int status, bool isOnline) {
  final rs = context.rs;
  final value = status == 0 && isOnline ? 3 : status;
  switch (value) {
    case 1:
    case 4:
      return rs.warn;
    case 2:
      return rs.down;
    case 3:
      return rs.up;
    default:
      return rs.inkFaint;
  }
}

/// A friend as the web UI lists it: one person (PGP key) with all their
/// devices (locations).
class _Friend {
  _Friend(this.gpgId, this.locations);

  final String gpgId;
  final List<Location> locations;

  String get name {
    for (final l in locations) {
      if (l.accountName.trim().isNotEmpty) return l.accountName.trim();
    }
    return 'Unknown';
  }

  bool get isOnline => locations.any((l) => l.isOnline);

  bool get pendingValidation =>
      locations.every((l) => l.statusMessage == 'Validation pending');

  /// The device to talk to: an online one first.
  Location get mainLocation =>
      locations.firstWhere((l) => l.isOnline, orElse: () => locations.first);

  int get status => mainLocation.status;

  String get customState => pendingValidation ? '' : mainLocation.statusMessage;
}

/// Network, as in the web UI: my presence, then my friends (online first) or
/// my direct chats with them.
class NetworkTab extends StatefulWidget {
  const NetworkTab({required this.open, this.onOpenPeerChat, super.key});

  final void Function(String route, {Object? arguments}) open;
  final Future<void> Function(Location location)? onOpenPeerChat;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

enum _View { network, chats }

class _NetworkTabState extends State<NetworkTab>
    with WidgetsBindingObserver {
  /// The friend list is read again at this pace while the app is on screen:
  /// connections, disconnections and names that arrive after the first
  /// connection show up without leaving the page.
  static const _refreshPeriod = Duration(seconds: 15);
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFriends();
      _startRefresh();
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshPeriod, (_) => _refreshFriends());
  }

  void _refreshFriends() {
    if (!mounted) return;
    unawaited(
      Provider.of<FriendLocations>(context, listen: false)
          .fetchfriendLocation(),
    );
  }

  _View _view = _View.network;
  String _search = '';

  /// Friends whose nodes the user unfolded; every friend starts folded, as
  /// the profiles of the desktop's friend list.
  final Set<String> _unfolded = {};

  List<_Friend> _friends(List<Location> locations) {
    final byGpg = <String, List<Location>>{};
    for (final l in locations) {
      final key = l.rsGpgId.isEmpty ? l.rsPeerId : l.rsGpgId;
      byGpg.putIfAbsent(key, () => []).add(l);
    }
    final friends = byGpg.entries.map((e) => _Friend(e.key, e.value)).toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final search = _search.toLowerCase();
    return friends
        .where((f) => f.name.toLowerCase().contains(search))
        .toList();
  }

  Future<void> _openChat(Location location) async {
    if (widget.onOpenPeerChat != null) {
      await widget.onOpenPeerChat!(location);
    } else {
      widget.open('/peer_chat', arguments: {'location': location});
    }
  }

  @override
  Widget build(BuildContext context) {
    final locations = context.watch<FriendLocations>().friendlist;
    final roomChat = context.watch<RoomChatLobby>();
    final friends = _friends(locations);
    final unreadChats = roomChat.peerUnreadCount;

    return Column(
      children: [
        const _OwnProfileCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RsScale.s4,
            RsScale.s2,
            RsScale.s4,
            RsScale.s2,
          ),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: _view == _View.network
                      ? 'Search friends'
                      : 'Search chats',
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: RsScale.s2),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_View>(
                  segments: [
                    const ButtonSegment(
                      value: _View.network,
                      icon: Icon(Icons.people_outline),
                      label: Text('Network'),
                    ),
                    ButtonSegment(
                      value: _View.chats,
                      icon: unreadChats > 0
                          ? Badge(
                              label: Text('$unreadChats'),
                              child: const Icon(Icons.forum_outlined),
                            )
                          : const Icon(Icons.forum_outlined),
                      label: const Text('Chats'),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _view == _View.network
              ? _networkList(context, friends)
              : _chatsList(context, friends, roomChat),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, String text) => Center(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  /// Friends, each with their nodes (devices) under them, as the desktop's
  /// friend list: folded at first, a tap on a friend unfolds their nodes.
  Widget _networkList(BuildContext context, List<_Friend> friends) {
    if (friends.isEmpty) return _empty(context, 'No friends found');
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (final f in friends) {
      final folded = !_unfolded.contains(f.gpgId);
      final online = f.locations.where((l) => l.isOnline).length;
      final count = f.locations.length;
      final summary = f.pendingValidation
          ? 'Pending validation'
          : '$count node${count == 1 ? '' : 's'}'
              '${online > 0 ? ', $online online' : ''}'
              '${f.customState.isNotEmpty ? ' · ${f.customState}' : ''}';
      rows.add(
        ListTile(
          leading: _AvatarWithStatus(
            name: f.name,
            color: f.pendingValidation
                ? rs.warn
                : statusColor(context, f.status, f.isOnline),
          ),
          title: Text(
            f.name,
            style: TextStyle(
              color: f.isOnline ? rs.ink : rs.inkDim,
              fontWeight: f.isOnline ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          subtitle:
              Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(folded ? Icons.expand_more : Icons.expand_less),
          onTap: () => setState(() {
            if (!_unfolded.remove(f.gpgId)) _unfolded.add(f.gpgId);
          }),
        ),
      );
      if (folded) continue;
      final nodes = [...f.locations]..sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          return a.locationName
              .toLowerCase()
              .compareTo(b.locationName.toLowerCase());
        });
      for (final node in nodes) {
        rows.add(
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(
              left: RsScale.s6 + RsScale.s5,
              right: RsScale.s4,
            ),
            leading: Icon(
              Icons.circle,
              size: 10,
              color: statusColor(context, node.status, node.isOnline),
            ),
            minLeadingWidth: RsScale.s3,
            title: Text(
              node.locationName.isEmpty ? 'Unnamed node' : node.locationName,
              style: text.bodyMedium?.copyWith(
                color: node.isOnline ? rs.ink : rs.inkDim,
              ),
            ),
            subtitle: Text(
              node.statusMessage == 'Validation pending'
                  ? 'Validation pending'
                  : statusLabel(node.status, node.isOnline),
              style: text.bodySmall,
            ),
            trailing: node.isOnline
                ? IconButton(
                    tooltip: 'Chat with this node',
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    onPressed: () => _openChat(node),
                  )
                : null,
            onTap: () => widget.open(
              '/friend_location_detail',
              arguments: {'location': node},
            ),
          ),
        );
      }
    }
    return ListView(children: rows);
  }

  Widget _chatsList(
    BuildContext context,
    List<_Friend> friends,
    RoomChatLobby roomChat,
  ) {
    final chats = roomChat.peerChats;
    final withChat = <(_Friend, Location, Chat)>[];
    for (final f in friends) {
      for (final l in f.locations) {
        final chat = chats[l.rsPeerId] ?? chats[l.rsPeerId.toLowerCase()];
        if (chat != null) withChat.add((f, l, chat));
      }
    }
    if (withChat.isEmpty) return _empty(context, 'No active chats found');
    return ListView.builder(
      itemCount: withChat.length,
      itemBuilder: (context, i) {
        final (f, l, chat) = withChat[i];
        final unread = chat.unreadCount;
        return ListTile(
          leading: _AvatarWithStatus(
            name: f.name,
            color: statusColor(context, l.status, l.isOnline),
          ),
          title: Text(f.name),
          subtitle: Text(
            l.locationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () {
            roomChat.resetPeerUnreadCount(chat.chatId!);
            _openChat(l);
          },
        );
      },
    );
  }
}

class _AvatarWithStatus extends StatelessWidget {
  const _AvatarWithStatus({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: rs.brandPale,
            foregroundColor: rs.brandDeep,
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: rs.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// My presence, as on top of the web UI's Network page: name (location), a
/// status dot to change Online / Away / Busy, and my status message.
class _OwnProfileCard extends StatefulWidget {
  const _OwnProfileCard();

  @override
  State<_OwnProfileCard> createState() => _OwnProfileCardState();
}

class _OwnProfileCardState extends State<_OwnProfileCard> {
  int _status = 3;
  String _customState = '';

  AuthToken? get _authToken =>
      Provider.of<AccountCredentials>(context, listen: false).authtoken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authToken = _authToken;
    if (authToken == null) return;
    try {
      final status = await RsStatus.getOwnStatus(authToken);
      final custom = await RsChats.getOwnCustomStateString(authToken);
      if (!mounted) return;
      setState(() {
        _status = status == 0 ? 3 : status;
        _customState = custom;
      });
    } catch (e) {
      debugPrint('Cannot read my presence: $e');
    }
  }

  Future<void> _setStatus(int status) async {
    final authToken = _authToken;
    if (authToken == null) return;
    try {
      if (await RsStatus.sendStatus(status, authToken) && mounted) {
        setState(() => _status = status);
      }
    } catch (e) {
      debugPrint('Cannot set my presence: $e');
    }
  }

  Future<void> _editCustomState() async {
    final controller = TextEditingController(text: _customState);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Status message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Set custom status...'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final authToken = _authToken;
    if (value == null || authToken == null) return;
    try {
      await RsChats.setCustomStateString(value.trim(), authToken);
      if (mounted) setState(() => _customState = value.trim());
    } catch (e) {
      debugPrint('Cannot set my status message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final account = context.watch<AccountCredentials>().loggedinAccount;
    final name = account == null
        ? 'Loading...'
        : '${account.pgpName} (${account.locationName})';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        RsScale.s4,
        RsScale.s3,
        RsScale.s4,
        RsScale.s3,
      ),
      decoration: BoxDecoration(
        color: rs.surface,
        border: Border(bottom: BorderSide(color: rs.line)),
      ),
      child: Row(
        children: [
          PopupMenuButton<int>(
            tooltip: 'Status: ${statusLabel(_status, true)}. Tap to change.',
            onSelected: _setStatus,
            itemBuilder: (_) => [
              for (final (value, label) in const [
                (3, 'Online'),
                (1, 'Away'),
                (2, 'Busy'),
              ])
                CheckedPopupMenuItem(
                  value: value,
                  checked: _status == value,
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: statusColor(context, value, true),
                      ),
                      const SizedBox(width: RsScale.s2),
                      Text(label),
                    ],
                  ),
                ),
            ],
            child: _AvatarWithStatus(
              name: account?.pgpName ?? '',
              color: statusColor(context, _status, true),
            ),
          ),
          const SizedBox(width: RsScale.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                InkWell(
                  onTap: _editCustomState,
                  child: Text(
                    _customState.isEmpty
                        ? 'Set custom status...'
                        : _customState,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: _customState.isEmpty ? rs.inkFaint : rs.inkDim,
                      fontStyle: _customState.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
