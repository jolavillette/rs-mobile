import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// Chat: the open chats (direct with friends, distant with identities) and
/// the chat rooms (Subscribed, Invitations, Public), with a search field and
/// a Create button.
class ChatsTab extends StatefulWidget {
  const ChatsTab({
    required this.open,
    this.onOpenRoom,
    this.onOpenPeerChat,
    super.key,
  });

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  /// Opens a room in the detail pane on a desktop layout.
  final Future<void> Function(Chat chat, bool isRoom)? onOpenRoom;

  /// Opens a direct chat in the detail pane on a desktop layout.
  final Future<void> Function(Location location)? onOpenPeerChat;

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

/// A pending invitation to a room, from the core.
class _Invite {
  _Invite(Map<dynamic, dynamic> json)
      : lobbyId = '${json['lobby_id']?['xstr64'] ?? ''}',
        name = '${json['lobby_name'] ?? ''}',
        topic = '${json['lobby_topic'] ?? ''}',
        peerId = '${json['peer_id'] ?? ''}';

  final String lobbyId;
  final String name;
  final String topic;
  final String peerId;
}

/// An open chat: direct with a friend's node ([peer]) or distant with an
/// identity ([identity]).
class _OpenChat {
  _OpenChat({
    required this.chat,
    required this.name,
    required this.preview,
    required this.lastTime,
    this.peer,
    this.identity,
  });

  final Chat chat;
  final String name;
  final String preview;
  final int lastTime;
  final Location? peer;
  final Identity? identity;
}

class _ChatsTabState extends State<ChatsTab> {
  String _search = '';
  List<_Invite> _invites = [];
  int _inviteCount = -1;

  AuthToken? get _authToken =>
      Provider.of<AccountCredentials>(context, listen: false).authtoken;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    final chatLobby = Provider.of<ChatLobby>(context, listen: false);
    await Future.wait([
      chatLobby.fetchAndUpdate(),
      chatLobby.fetchAndUpdateUnsubscribed(),
      _loadInvites(),
    ]);
  }

  Future<void> _loadInvites() async {
    final authToken = _authToken;
    if (authToken == null) return;
    try {
      final invites = await RsMsgs.getPendingChatLobbyInvites(authToken);
      if (!mounted) return;
      setState(() {
        _invites = [
          for (final i in (invites as List? ?? const []))
            if (i is Map) _Invite(i),
        ];
      });
    } catch (e) {
      debugPrint('Cannot read the room invitations: $e');
    }
  }

  bool _matches(String? name) =>
      (name ?? '').toLowerCase().contains(_search.toLowerCase());

  Future<void> _openRoom(dynamic room) async {
    final current =
        Provider.of<Identities>(context, listen: false).currentIdentity;
    if (current == null) return;
    final chatLobby = Provider.of<ChatLobby>(context, listen: false);
    try {
      final chat = await Provider.of<RoomChatLobby>(context, listen: false)
          .getChat(current, room);
      if (chat == null || !mounted) return;
      if (room is! Chat) chatLobby.recordJoinedChat(chat);
      if (widget.onOpenRoom != null) {
        await widget.onOpenRoom!(chat, true);
      } else {
        widget.open('/room', arguments: {'isRoom': true, 'chatData': chat});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join chat room: $e')),
      );
    }
  }

  Future<void> _leaveRoom(Chat room) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave room'),
        content: Text('Leave ${room.chatName ?? 'this room'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave room'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted || room.chatId == null) return;
    final chatLobby = Provider.of<ChatLobby>(context, listen: false);
    await chatLobby.unsubscribed(room.chatId!);
    await chatLobby.fetchAndUpdateUnsubscribed();
  }

  Future<void> _answerInvite(_Invite invite) async {
    final authToken = _authToken;
    if (authToken == null) return;
    var sender = 'A friend';
    try {
      sender = (await RsPeers.getPeerDetails(invite.peerId, authToken))
          .accountName;
    } catch (_) {}
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invitation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$sender invited you to join '
                '${invite.name.isEmpty ? 'a room' : invite.name}.'),
            if (invite.topic.isNotEmpty) ...[
              const SizedBox(height: RsScale.s2),
              Text(
                invite.topic,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (accept == null || !mounted) return;
    final chatLobby = Provider.of<ChatLobby>(context, listen: false);
    final current =
        Provider.of<Identities>(context, listen: false).currentIdentity;
    try {
      if (accept) {
        if (current == null) return;
        final ok = await RsMsgs.acceptLobbyInvite(
          invite.lobbyId,
          current.mId,
          authToken,
        );
        if (!ok) throw Exception('the core refused the invitation');
      } else {
        await RsMsgs.denyLobbyInvite(invite.lobbyId, authToken);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not answer the invitation: $e')),
      );
    }
    await chatLobby.checkForNewInvites();
    await _refresh();
  }

  Future<void> _joinPublic(VisibleChatLobbyRecord room) async {
    final peers = room.totalNumberOfPeers ?? 0;
    final join = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final text = Theme.of(dialogContext).textTheme;
        return AlertDialog(
          title: const Text('Join Room'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.lobbyName ?? '<unnamed>', style: text.titleMedium),
              const SizedBox(height: RsScale.s1),
              Text(
                (room.lobbyTopic ?? '').isEmpty ? 'No topic' : room.lobbyTopic!,
                style: text.bodyMedium,
              ),
              const SizedBox(height: RsScale.s2),
              Text(
                '$peers participant${peers == 1 ? '' : 's'}',
                style: text.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
    if (join == true && mounted) await _openRoom(room);
  }

  /// The direct and distant chats, the latest message first.
  List<_OpenChat> _openChats(
    RoomChatLobby roomChat,
    List<Location> friends,
    Set<String?> roomIds,
  ) {
    String preview(Chat chat) {
      final messages = roomChat.messagesList[chat.chatId];
      if (messages == null || messages.isEmpty) return '';
      // Messages are rich text: the preview is their text only.
      return (messages.last.msg ?? '')
          .replaceAll(RegExp('<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .trim();
    }

    int lastTime(Chat chat) {
      final messages = roomChat.messagesList[chat.chatId];
      if (messages == null || messages.isEmpty) return 0;
      return messages.last.recvTime ?? messages.last.sendTime ?? 0;
    }

    final result = <_OpenChat>[];
    final seen = <String>{};
    for (final chat in roomChat.distanceChat.values) {
      final chatId = chat.chatId;
      if (chat.isPublic ||
          chatId == null ||
          chatId.isEmpty ||
          RegExp(r'^0+$').hasMatch(chatId) ||
          roomIds.contains(chatId) ||
          !seen.add(chatId)) {
        continue;
      }
      final identity = roomChat.allIdentity[chat.interlocutorId] ??
          Identity(
            mId: chat.interlocutorId,
            signed: false,
            isContact: false,
            name: chat.chatName,
          );
      result.add(
        _OpenChat(
          chat: chat,
          name: identity.name ?? chat.chatName ?? identity.mId,
          preview: preview(chat),
          lastTime: lastTime(chat),
          identity: identity,
        ),
      );
    }
    for (final entry in roomChat.peerChats.entries) {
      final peer = friends
          .where((l) => l.rsPeerId.toLowerCase() == entry.key.toLowerCase())
          .firstOrNull;
      if (peer == null) continue;
      result.add(
        _OpenChat(
          chat: entry.value,
          name: peer.accountName.isEmpty ? peer.rsPeerId : peer.accountName,
          preview: preview(entry.value),
          lastTime: lastTime(entry.value),
          peer: peer,
        ),
      );
    }
    result.sort((a, b) => b.lastTime.compareTo(a.lastTime));
    return result;
  }

  Future<void> _openChat(_OpenChat open) async {
    final roomChat = Provider.of<RoomChatLobby>(context, listen: false);
    final peer = open.peer;
    if (peer != null) {
      if (open.chat.chatId != null) {
        roomChat.resetPeerUnreadCount(open.chat.chatId!);
      }
      if (widget.onOpenPeerChat != null) {
        await widget.onOpenPeerChat!(peer);
      } else {
        widget.open('/peer_chat', arguments: {'location': peer});
      }
      return;
    }
    final current =
        Provider.of<Identities>(context, listen: false).currentIdentity;
    if (current == null) return;
    final chat = await roomChat.getChat(current, open.chat);
    if (chat == null || !mounted) return;
    if (widget.onOpenRoom != null) {
      await widget.onOpenRoom!(chat, false);
    } else {
      widget.open('/room', arguments: {'isRoom': false, 'chatData': chat});
    }
  }

  Future<void> _closeChat(_OpenChat open) async {
    final chatId = open.chat.chatId;
    if (chatId == null) return;
    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close chat'),
        content: Text('Close the chat with ${open.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Close chat'),
          ),
        ],
      ),
    );
    if (close != true || !mounted) return;
    final roomChat = Provider.of<RoomChatLobby>(context, listen: false);
    if (open.peer != null) {
      roomChat.removePeerChat(chatId);
    } else {
      await roomChat.removeDistantChat(chatId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final chatLobby = context.watch<ChatLobby>();
    final roomChat = context.watch<RoomChatLobby>();
    final friends = context.watch<FriendLocations>().friendlist;

    // The invitations are read again whenever their count changes.
    if (chatLobby.pendingInviteCount != _inviteCount) {
      _inviteCount = chatLobby.pendingInviteCount;
      Future.microtask(_loadInvites);
    }

    final subscribed = chatLobby.subscribedlist
        .where((c) => _matches(c.chatName))
        .toList()
      ..sort(
        (a, b) => (a.chatName ?? '')
            .toLowerCase()
            .compareTo((b.chatName ?? '').toLowerCase()),
      );
    final subscribedIds = subscribed.map((c) => c.chatId).toSet();
    final openChats = _openChats(
      roomChat,
      friends,
      chatLobby.subscribedlist.map((c) => c.chatId).toSet(),
    ).where((c) => _matches(c.name)).toList();
    final invites = _invites.where((i) => _matches(i.name)).toList();
    final invitedIds = invites.map((i) => i.lobbyId).toSet();
    final public = chatLobby.unSubscribedlist
        .where(
          (r) =>
              !subscribedIds.contains(r.lobbyId?.xstr64) &&
              !invitedIds.contains(r.lobbyId?.xstr64) &&
              _matches(r.lobbyName),
        )
        .toList()
      ..sort(
        (a, b) => (b.totalNumberOfPeers ?? 0)
            .compareTo(a.totalNumberOfPeers ?? 0),
      );

    Widget section(IconData icon, String title) => Padding(
          padding: const EdgeInsets.fromLTRB(
            RsScale.s4,
            RsScale.s4,
            RsScale.s4,
            RsScale.s1,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: rs.inkDim),
              const SizedBox(width: RsScale.s2),
              Text(title, style: text.labelMedium),
            ],
          ),
        );

    Widget badge(String label, {Color? color}) => Badge(
          label: Text(label),
          backgroundColor: color,
        );

    return Column(
      children: [
        Container(
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
              Icon(Icons.forum_outlined, color: rs.inkDim),
              const SizedBox(width: RsScale.s3),
              Expanded(child: Text('Chat rooms', style: text.titleSmall)),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create'),
                onPressed: () => widget.open('/create_room'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RsScale.s4,
            RsScale.s2,
            RsScale.s4,
            0,
          ),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Search chat rooms',
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                if (openChats.isNotEmpty) ...[
                  section(
                    Icons.chat_outlined,
                    'Chats (${openChats.length})',
                  ),
                  for (final open in openChats)
                    ListTile(
                      leading: open.identity != null
                          ? IdentityAvatar(identity: open.identity!)
                          : CircleAvatar(
                              backgroundColor: rs.brandPale,
                              foregroundColor: rs.brandDeep,
                              child: Text(
                                open.name.isEmpty
                                    ? '?'
                                    : open.name[0].toUpperCase(),
                              ),
                            ),
                      title: Text(open.name),
                      subtitle: Text(
                        open.preview.isNotEmpty
                            ? open.preview
                            : open.peer != null
                                ? 'Direct chat · ${open.peer!.locationName}'
                                : 'Distant chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: open.chat.unreadCount > 0
                          ? badge('${open.chat.unreadCount}')
                          : null,
                      onTap: () => _openChat(open),
                      onLongPress: () => _closeChat(open),
                    ),
                ],
                if (subscribed.isNotEmpty) ...[
                  section(
                    Icons.bookmark_outline,
                    'Subscribed (${subscribed.length})',
                  ),
                  for (final room in subscribed)
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(room.chatName ?? '<unnamed>'),
                      subtitle: Text(
                        (room.lobbyTopic ?? '').isEmpty
                            ? 'No topic'
                            : room.lobbyTopic!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: room.unreadCount > 0
                          ? badge('${room.unreadCount}')
                          : null,
                      onTap: () => _openRoom(room),
                      onLongPress: () => _leaveRoom(room),
                    ),
                ],
                if (invites.isNotEmpty) ...[
                  section(
                    Icons.mail_outline,
                    'Invitations (${invites.length})',
                  ),
                  for (final invite in invites)
                    ListTile(
                      leading: const Icon(Icons.drafts_outlined),
                      title: Text(
                        invite.name.isEmpty ? '<unnamed>' : invite.name,
                      ),
                      subtitle: Text(
                        invite.topic.isEmpty
                            ? 'You were invited to join'
                            : invite.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: badge('!', color: rs.warn),
                      onTap: () => _answerInvite(invite),
                    ),
                ],
                if (public.isNotEmpty) ...[
                  section(Icons.public, 'Public (${public.length})'),
                  for (final room in public)
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: Text(room.lobbyName ?? '<unnamed>'),
                      subtitle: Text(
                        (room.lobbyTopic ?? '').isEmpty
                            ? 'No topic'
                            : room.lobbyTopic!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: (room.totalNumberOfPeers ?? 0) > 0
                          ? badge(
                              '${room.totalNumberOfPeers}',
                              color: rs.inkFaint,
                            )
                          : null,
                      onTap: () => _joinPublic(room),
                    ),
                ],
                if (openChats.isEmpty &&
                    subscribed.isEmpty &&
                    invites.isEmpty &&
                    public.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(RsScale.s6),
                    child: Text(
                      'No chats and no chat rooms',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
