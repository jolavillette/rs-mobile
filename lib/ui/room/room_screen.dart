import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identicon.dart';
import 'package:retroshare/common/person_delegate.dart';
import 'package:retroshare/common/styles.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare/ui/room/message_delegate.dart';
import 'package:retroshare/ui/room/messages_tab.dart';
import 'package:retroshare/ui/room/room_friends_tab.dart';
import 'package:retroshare/ui/room/room_history.dart';
import 'package:retroshare/ui/room/room_notifications.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _ChatMenuAction {
  search,
  clearChat,
  bubble,
  compact,
  participants,
  history,
  identity,
  notifications,
  invite,
  leave,
  close,
}

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    this.isRoom = false,
    required this.chat,
    this.onBack,
  });
  final bool isRoom;
  final Chat chat;
  final VoidCallback? onBack;

  @override
  RoomScreenState createState() => RoomScreenState();
}

class RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Animation<Color?> _iconAnimation;
  BubbleStyle _bubbleStyle = BubbleStyle.bubble;
  Timer? _refreshTimer;
  RoomChatLobby? _roomProvider;
  final GlobalKey<MessagesTabState> _messagesTabKey =
      GlobalKey<MessagesTabState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _roomProvider ??= Provider.of<RoomChatLobby>(context, listen: false);
    _iconAnimation = ColorTween(
            begin: Theme.of(context).colorScheme.onSurface,
            end: Theme.of(context).colorScheme.primary)
        .animate(_tabController.animation!);
  }

  Future<void> _loadBubbleStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final styleIndex = prefs.getInt('chat_bubble_style');
      if (styleIndex != null && mounted) {
        setState(() {
          _bubbleStyle = BubbleStyle.values[styleIndex];
        });
      }
    } catch (e) {
      debugPrint('Error loading bubble style: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(vsync: this, length: widget.isRoom ? 2 : 1);
    _loadBubbleStyle();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.chat.chatId == null) {
        debugPrint(
          'Chat ID is null, cannot update participants or current chat.',
        );
        return;
      }
      try {
        final roomProvider = Provider.of<RoomChatLobby>(context, listen: false);
        final chatLobby = Provider.of<ChatLobby>(context, listen: false);

        if (widget.isRoom) {
          final lobbyId = widget.chat.chatId!;
          chatLobby.resetUnreadCount(lobbyId);
          unawaited(roomProvider.refreshRoomIdentity(lobbyId));
          // The count in the header follows people joining and leaving
          // while the room is open.
          unawaited(roomProvider.refreshParticipantCount(lobbyId));
          _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
            if (mounted) roomProvider.refreshParticipantCount(lobbyId);
          });
        } else if (widget.chat.chatId != null) {
          // Trigger immediate status check for 1:1 chat
          await roomProvider.refreshDistantChatStatus(
            widget.chat.chatId!,
            ChatId(distantChatId: widget.chat.chatId, type: ChatIdType.type2),
          );

          // Start periodic refresh while chat is open
          _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
            if (mounted) {
              roomProvider.refreshDistantChatStatus(
                widget.chat.chatId!,
                ChatId(
                    distantChatId: widget.chat.chatId, type: ChatIdType.type2),
              );
            }
          });
        }
        if (roomProvider.currentChat?.chatId != widget.chat.chatId) {
          roomProvider.updateCurrentChat(widget.chat);
        }
      } catch (e) {
        debugPrint('Error during initState updates: $e');
      }
    });
  }

  @override
  void deactivate() {
    super.deactivate();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    // Clear current chat so new messages are counted as unread
    _roomProvider?.clearCurrentChat(widget.chat.chatId);
    super.dispose();
  }

  MemoryImage? _safeDecodeBase64(String? base64String) {
    if (base64String == null || base64String.isEmpty) {
      return null;
    }
    try {
      return MemoryImage(base64Decode(base64String));
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return null;
    }
  }

  /// The LED and the words of the desktop's distant chat window for the
  /// tunnel status [status] (RS_DISTANT_CHAT_STATUS_*).
  static (Color, String) _tunnelState(int? status) {
    switch (status) {
      case 2: // CAN_TALK
        return (
          Colors.green,
          'End-to-end encrypted conversation established',
        );
      case 1: // TUNNEL_DN
        return (Colors.amber, 'Tunnel is pending');
      case 3: // REMOTELY_CLOSED
        return (Colors.red, 'Your partner closed the conversation');
      default:
        return (Colors.grey, 'Remote status unknown');
    }
  }

  ChatId? _apiChatId() {
    final chatId = widget.chat.chatId;
    if (chatId == null) return null;
    return ChatId(
      distantChatId: widget.isRoom ? null : chatId,
      lobbyId: widget.isRoom ? ChatLobbyId(xstr64: chatId) : null,
      type: widget.isRoom ? ChatIdType.type3 : ChatIdType.type2,
    );
  }

  Future<void> _clearChat() async {
    final chatId = widget.chat.chatId;
    final apiChatId = _apiChatId();
    if (chatId == null || apiChatId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This permanently removes the message history for this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Provider.of<RoomChatLobby>(context, listen: false)
          .clearChatHistory(chatId, apiChatId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat cleared')),
      );
    } catch (e) {
      debugPrint('Error clearing chat history: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear chat')),
      );
    }
  }

  /// The identity used in this room only, as the desktop's identity chooser
  /// in a room window.
  Future<void> _chooseRoomIdentity() async {
    final lobbyId = widget.chat.chatId;
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final own = Provider.of<Identities>(context, listen: false).ownIdentity;
    if (lobbyId == null || authToken == null || own.isEmpty) return;
    String? current;
    try {
      final response = await rsApiCall(
        '/rsChats/getIdentityForChatLobby',
        authToken: authToken,
        params: {
          'lobby_id': {'xstr64': lobbyId},
        },
      );
      current = response['nick']?.toString();
    } catch (e) {
      debugPrint('Cannot read the identity of room $lobbyId: $e');
    }
    if (!mounted) return;
    final picked = await showDialog<Identity>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Identity in this room'),
        children: [
          for (final id in own)
            ListTile(
              leading: Icon(
                id.mId == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(id.name ?? id.mId),
              subtitle: Text(id.signed ? 'Signed' : 'Pseudonymous'),
              onTap: () => Navigator.of(dialogContext).pop(id),
            ),
        ],
      ),
    );
    if (picked == null || picked.mId == current || !mounted) return;
    final roomProvider = Provider.of<RoomChatLobby>(context, listen: false);
    var changed = false;
    try {
      final response = await rsApiCall(
        '/rsChats/setIdentityForChatLobby',
        authToken: authToken,
        params: {
          'lobby_id': {'xstr64': lobbyId},
          'nick': picked.mId,
        },
      );
      changed = response['retval'] == true;
    } catch (e) {
      debugPrint('Cannot change the identity of room $lobbyId: $e');
    }
    if (changed) roomProvider.setRoomIdentity(lobbyId, picked.mId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed
              ? 'You now appear as ${picked.name ?? picked.mId} in this room.'
              : 'The identity could not be changed: this room may accept '
                  'signed identities only.',
        ),
      ),
    );
  }

  /// Invites online friends into this room, as the web UI's Invite friends.
  Future<void> _inviteFriends() async {
    final lobbyId = widget.chat.chatId;
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (lobbyId == null || authToken == null) return;
    final nodes = Provider.of<FriendLocations>(context, listen: false)
        .friendlist
        .where((l) => l.isOnline)
        .toList()
      ..sort(
        (a, b) => a.accountName.toLowerCase().compareTo(
              b.accountName.toLowerCase(),
            ),
      );
    final picked = <String>{};
    final invite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Invite friends'),
          content: nodes.isEmpty
              ? const Text('No friend is online.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final node in nodes)
                        CheckboxListTile(
                          value: picked.contains(node.rsPeerId),
                          title: Text(node.accountName),
                          subtitle: Text(node.locationName),
                          onChanged: (on) => setDialogState(() {
                            if (on == true) {
                              picked.add(node.rsPeerId);
                            } else {
                              picked.remove(node.rsPeerId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: picked.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
    if (invite != true || picked.isEmpty) return;
    var sent = 0;
    for (final peerId in picked) {
      try {
        await rsApiCall(
          '/rsChats/invitePeerToLobby',
          authToken: authToken,
          params: {
            'lobby_id': {'xstr64': lobbyId},
            'peer_id': peerId,
          },
        );
        sent++;
      } catch (e) {
        debugPrint('Cannot invite $peerId: $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent == picked.length
              ? 'Invitation sent to $sent friend${sent == 1 ? '' : 's'}.'
              : 'Invitation sent to $sent of ${picked.length} friends.',
        ),
      ),
    );
  }

  /// Leaves this room (unsubscribes), after a confirmation.
  Future<void> _leaveRoom() async {
    final lobbyId = widget.chat.chatId;
    if (lobbyId == null) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave room'),
        content: Text('Leave ${widget.chat.chatName ?? 'this room'}?'),
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
    if (leave != true || !mounted) return;
    await Provider.of<ChatLobby>(context, listen: false).unsubscribed(lobbyId);
    if (!mounted) return;
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  /// Ends this private chat as closing its window does on the desktop: the
  /// tunnel closes, the chat leaves the list and its screen closes.
  Future<void> _closeChat() async {
    final chatId = widget.chat.chatId;
    if (chatId == null) return;
    final roomProvider = Provider.of<RoomChatLobby>(context, listen: false);
    // Once the partner has closed it there is nothing left to end.
    if (roomProvider.distantChatStatus(chatId) != 3) {
      final close = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Close conversation?'),
          content: const Text(
            'Closing this chat ends the conversation. Unsent messages will '
            'be dropped.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (close != true || !mounted) return;
    }
    await roomProvider.removeDistantChat(chatId);
    if (!mounted) return;
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _handleMenuAction(_ChatMenuAction action) async {
    switch (action) {
      case _ChatMenuAction.search:
        _tabController.animateTo(0);
        _messagesTabKey.currentState?.showMessageSearch();
        return;
      case _ChatMenuAction.clearChat:
        await _clearChat();
        return;
      case _ChatMenuAction.participants:
        _tabController.animateTo(1);
        return;
      case _ChatMenuAction.history:
        final lobbyId = widget.chat.chatId;
        final apiChatId = _apiChatId();
        if (lobbyId != null && apiChatId != null) {
          await retrieveRoomHistory(context, lobbyId, apiChatId);
        }
        return;
      case _ChatMenuAction.identity:
        await _chooseRoomIdentity();
        return;
      case _ChatMenuAction.notifications:
        final lobbyId = widget.chat.chatId;
        if (lobbyId != null) await chooseRoomNotifications(context, lobbyId);
        return;
      case _ChatMenuAction.invite:
        await _inviteFriends();
        return;
      case _ChatMenuAction.leave:
        await _leaveRoom();
        return;
      case _ChatMenuAction.close:
        await _closeChat();
        return;
      case _ChatMenuAction.bubble:
      case _ChatMenuAction.compact:
        final style = action == _ChatMenuAction.bubble
            ? BubbleStyle.bubble
            : BubbleStyle.compact;
        setState(() => _bubbleStyle = style);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('chat_bubble_style', style.index);
        } catch (e) {
          debugPrint('Error saving bubble style: $e');
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = Provider.of<RoomChatLobby>(context, listen: false);
    final interlocutorIdentity =
        roomProvider.allIdentity[widget.chat.interlocutorId];
    final avatarImage = _safeDecodeBase64(interlocutorIdentity?.avatar);
    final hasAvatar = avatarImage != null;

    // A private chat shows the state of its tunnel, as the desktop's LED.
    final chatId = widget.chat.chatId;
    final (tunnelColor, tunnelText) = _tunnelState(
      widget.isRoom || chatId == null
          ? null
          : context.select<RoomChatLobby, int?>(
              (lobby) => lobby.distantChatStatus(chatId),
            ),
    );

    final displayName = widget.isRoom
        ? widget.chat.chatName
        : interlocutorIdentity?.name ??
            widget.chat.chatName ??
            widget.chat.interlocutorId;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: appBarHeight,
              padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: personDelegateHeight,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 25,
                      ),
                      onPressed: () {
                        if (widget.isRoom && _tabController.index == 1) {
                          _tabController.animateTo(0);
                        } else if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                  if (!widget.isRoom)
                    GestureDetector(
                      onTap: interlocutorIdentity == null
                          ? null
                          : () {
                              Navigator.pushNamed(
                                context,
                                '/profile',
                                arguments: {'id': interlocutorIdentity},
                              );
                            },
                      child: Stack(
                        children: [
                          SizedBox(
                            width: appBarHeight,
                            height: appBarHeight,
                            child: CircleAvatar(
                              radius: appBarHeight * 0.35,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              backgroundImage: avatarImage,
                              child: !hasAvatar
                                  ? Identicon(
                                      id: widget.chat.interlocutorId,
                                      size: appBarHeight * 0.7,
                                      borderRadius: appBarHeight * 0.35,
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Tooltip(
                              message: tunnelText,
                              child: Container(
                                height: 14,
                                width: 14,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    width: 2,
                                  ),
                                  color: tunnelColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.isRoom || interlocutorIdentity == null
                          ? null
                          : () {
                              Navigator.pushNamed(
                                context,
                                '/profile',
                                arguments: {'id': interlocutorIdentity},
                              );
                            },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName ?? 'Chat',
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!widget.isRoom)
                            Text(
                              tunnelText,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                  // The participants, as the web UI's Participants (n): the
                  // count shows, a tap switches to their list and back.
                  if (widget.isRoom)
                    Consumer<RoomChatLobby>(
                      builder: (context, lobby, _) {
                        final lobbyId = widget.chat.chatId ?? '';
                        final count = lobby.lobbyParticipantCount(lobbyId) ??
                            lobby.lobbyParticipants[lobbyId]?.length ??
                            0;
                        return AnimatedBuilder(
                          animation: _tabController.animation!,
                          builder: (BuildContext context, Widget? child) {
                            return Tooltip(
                              message: 'Participants',
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      _iconAnimation.value ?? Colors.grey,
                                ),
                                icon: const Icon(Icons.people_outline),
                                label: Text('$count'),
                                onPressed: () {
                                  _tabController
                                      .animateTo(1 - _tabController.index);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  PopupMenuButton<_ChatMenuAction>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: _handleMenuAction,
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<_ChatMenuAction>>[
                      const PopupMenuItem<_ChatMenuAction>(
                        value: _ChatMenuAction.search,
                        child: ListTile(
                          leading: Icon(Icons.search),
                          title: Text('Search'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem<_ChatMenuAction>(
                        value: _ChatMenuAction.clearChat,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Clear chat'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (widget.isRoom) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.participants,
                          child: ListTile(
                            leading: Icon(Icons.people_outline),
                            title: Text('Participants'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.history,
                          child: ListTile(
                            leading: Icon(Icons.history),
                            title: Text('History from friends'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.identity,
                          child: ListTile(
                            leading: Icon(Icons.badge_outlined),
                            title: Text('Identity in this room'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (roomNotificationsAvailable)
                          const PopupMenuItem<_ChatMenuAction>(
                            value: _ChatMenuAction.notifications,
                            child: ListTile(
                              leading: Icon(Icons.notifications_outlined),
                              title: Text('Notifications'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.invite,
                          child: ListTile(
                            leading: Icon(Icons.person_add_alt),
                            title: Text('Invite friends'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.leave,
                          child: ListTile(
                            leading: Icon(Icons.logout),
                            title: Text('Leave room'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      if (!widget.isRoom) const PopupMenuDivider(),
                      if (!widget.isRoom)
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.bubble,
                          child: Text('Bubble'),
                        ),
                      if (!widget.isRoom)
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.compact,
                          child: Text('Bubble Compact'),
                        ),
                      if (!widget.isRoom) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem<_ChatMenuAction>(
                          value: _ChatMenuAction.close,
                          child: ListTile(
                            leading: Icon(Icons.close),
                            title: Text('Close chat'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  MessagesTab(
                    key: _messagesTabKey,
                    chat: widget.chat,
                    isRoom: widget.isRoom,
                    bubbleStyle: _bubbleStyle,
                  ),
                  if (widget.isRoom) RoomFriendsTab(chat: widget.chat),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
