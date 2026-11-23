import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/common/show_dialog.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/provider/subscribed.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Chat, Identity;

/// People, as in the web UI: identities, filtered to my contacts, my own
/// identities or every identity known, and a People | Chats switch to the
/// distant chats with them.
class PeopleTab extends StatefulWidget {
  const PeopleTab({required this.open, this.onOpenRoom, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  /// Opens a chat in the detail pane on a desktop layout.
  final Future<void> Function(Chat chat, bool isRoom)? onOpenRoom;

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

enum _View { people, chats }

enum _Filter {
  contacts('Contacts', Icons.people_outline),
  own('My Identities', Icons.person_outline),
  all('All Users', Icons.groups_outlined);

  const _Filter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Rows shown at most: "All Users" can be tens of thousands of identities on
/// an old node, the search narrows the list.
const _listCap = 200;

class _PeopleTabState extends State<PeopleTab> {
  _View _view = _View.people;
  _Filter _filter = _Filter.contacts;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final ids = Provider.of<Identities>(context, listen: false);
    if (ids.ownIdentity.isEmpty) ids.fetchOwnidenities();
  }

  bool _matches(String? name) =>
      (name ?? '').toLowerCase().contains(_search.toLowerCase());

  int _byName(Identity a, Identity b) =>
      (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());

  Future<void> _startChat(Identity identity) async {
    final current =
        Provider.of<Identities>(context, listen: false).currentIdentity;
    if (current == null) return;
    final chat = await Provider.of<RoomChatLobby>(context, listen: false)
        .getChat(current, identity);
    if (chat == null || !mounted) return;
    await _openChat(chat);
  }

  Future<void> _openChat(Chat chat) async {
    if (widget.onOpenRoom != null) {
      await widget.onOpenRoom!(chat, false);
    } else {
      widget.open('/room', arguments: {'isRoom': false, 'chatData': chat});
    }
  }

  Future<void> _setContact(Identity identity, bool isContact) async {
    try {
      await Provider.of<RoomChatLobby>(context, listen: false)
          .toggleContacts(identity.mId, isContact);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The contact list could not be changed.')),
      );
    }
  }

  void _useIdentity(Identity identity) {
    Provider.of<Identities>(context, listen: false)
      ..updateSelectedIdentity(identity)
      ..updateCurrentIdentity();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${identity.name ?? 'This identity'} is now active.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomChat = context.watch<RoomChatLobby>();
    final unreadChats = roomChat.distantUnreadCount;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RsScale.s4,
            RsScale.s3,
            RsScale.s4,
            RsScale.s2,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search',
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                  if (_view == _View.people && _filter == _Filter.own) ...[
                    const SizedBox(width: RsScale.s2),
                    IconButton.filled(
                      tooltip: 'Create New Identity',
                      icon: const Icon(Icons.add),
                      onPressed: () => widget.open('/create_identity'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: RsScale.s2),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_View>(
                      segments: [
                        const ButtonSegment(
                          value: _View.people,
                          icon: Icon(Icons.people_outline),
                          label: Text('People'),
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
                      onSelectionChanged: (s) =>
                          setState(() => _view = s.first),
                    ),
                  ),
                  if (_view == _View.people) ...[
                    const SizedBox(width: RsScale.s2),
                    PopupMenuButton<_Filter>(
                      tooltip: 'Showing ${_filter.label}',
                      initialValue: _filter,
                      onSelected: (f) => setState(() => _filter = f),
                      itemBuilder: (_) => [
                        for (final f in _Filter.values)
                          PopupMenuItem(
                            value: f,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(f.icon),
                              title: Text(f.label),
                            ),
                          ),
                      ],
                      child: Chip(
                        avatar: Icon(_filter.icon, size: 18),
                        label: Text(_filter.label),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _view == _View.chats
              ? _chatsList(context, roomChat)
              : _filter == _Filter.own
                  ? _ownList(context)
                  : _identityList(context, roomChat),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  /// My identities: the active one marked; the others can be made active or
  /// deleted. The active identity is never deleted.
  Widget _ownList(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final ids = context.watch<Identities>();
    final current = ids.currentIdentity?.mId;
    final own = ids.ownIdentity.where((i) => _matches(i.name)).toList()
      ..sort(_byName);
    if (own.isEmpty) return _empty('No identities found');
    return RefreshIndicator(
      onRefresh: ids.fetchOwnidenities,
      child: ListView.builder(
        itemCount: own.length,
        itemBuilder: (context, i) {
          final identity = own[i];
          final active = identity.mId == current;
          return ListTile(
            leading: IdentityAvatar(identity: identity),
            title: Text(identity.name ?? identity.mId),
            subtitle: Text(
              '${active ? 'Active identity' : 'My Identity'}'
              ' · ${identity.signed ? 'signed' : 'pseudonymous'}',
            ),
            selected: active,
            onTap: () => widget.open('/profile', arguments: {'id': identity}),
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) {
                switch (action) {
                  case 'use':
                    _useIdentity(identity);
                  case 'edit':
                    widget.open(
                      '/updateIdentity',
                      arguments: {'id': identity},
                    );
                  case 'delete':
                    showdeleteDialog(context, identity);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'use',
                  enabled: !active,
                  child: Text(active ? 'Active identity' : 'Use this identity'),
                ),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  enabled: !active,
                  child: Text(
                    active
                        ? 'Delete (make another identity active first)'
                        : 'Delete',
                    style: active ? null : TextStyle(color: rs.down),
                  ),
                ),
              ],
              child: active
                  ? Padding(
                      padding: const EdgeInsets.all(RsScale.s2),
                      child: Icon(Icons.check_circle, color: rs.brand),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(RsScale.s2),
                      child: Icon(Icons.more_vert, color: rs.inkDim),
                    ),
            ),
            titleTextStyle: active
                ? text.titleSmall?.copyWith(color: rs.brand)
                : null,
          );
        },
      ),
    );
  }

  /// Contacts, or every identity known: tap for the profile, the menu to
  /// chat or to add or remove the contact.
  Widget _identityList(BuildContext context, RoomChatLobby roomChat) {
    final ownIds =
        context.watch<Identities>().ownIdentity.map((i) => i.mId).toSet();
    final List<Identity> base;
    if (_filter == _Filter.contacts) {
      base = roomChat.friendsIdsList;
    } else {
      final byId = <String, Identity>{
        for (final i in [
          ...roomChat.friendsSignedIdsList,
          ...roomChat.notContactIds,
          ...roomChat.friendsIdsList,
        ])
          i.mId: i,
      };
      base = byId.values.toList();
    }
    final list = base
        .where((i) => !ownIds.contains(i.mId) && _matches(i.name))
        .toList()
      ..sort(_byName);
    if (list.isEmpty) {
      return _empty(
        _filter == _Filter.contacts ? 'No contacts found' : 'No identities found',
      );
    }
    final shown = list.take(_listCap).toList();
    final hidden = list.length - shown.length;
    return RefreshIndicator(
      onRefresh: roomChat.fetchAndUpdate,
      child: ListView.builder(
        itemCount: shown.length + (hidden > 0 ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == shown.length) {
            return Padding(
              padding: const EdgeInsets.all(RsScale.s4),
              child: Text(
                '$hidden more identities — search to narrow the list',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          final identity = shown[i];
          return ListTile(
            leading: IdentityAvatar(identity: identity),
            title: Text(identity.name ?? identity.mId),
            subtitle: Text(identity.isContact ? 'Contact' : 'Identity'),
            onTap: () => widget.open('/profile', arguments: {'id': identity}),
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) {
                switch (action) {
                  case 'chat':
                    _startChat(identity);
                  case 'contact':
                    _setContact(identity, !identity.isContact);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'chat', child: Text('Start chat')),
                PopupMenuItem(
                  value: 'contact',
                  child: Text(
                    identity.isContact
                        ? 'Remove from contacts'
                        : 'Add to contacts',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The distant chats: with identities, through GXS tunnels.
  Widget _chatsList(BuildContext context, RoomChatLobby roomChat) {
    final rooms = context
        .watch<ChatLobby>()
        .subscribedlist
        .map((c) => c.chatId)
        .toSet();
    final seen = <String>{};
    final chats = <Chat>[];
    for (final chat in roomChat.distanceChat.values) {
      final chatId = chat.chatId;
      if (chat.isPublic ||
          chatId == null ||
          chatId.isEmpty ||
          RegExp(r'^0+$').hasMatch(chatId) ||
          rooms.contains(chatId) ||
          !seen.add(chatId)) {
        continue;
      }
      final identity = roomChat.allIdentity[chat.interlocutorId];
      if (_matches(identity?.name ?? chat.chatName)) chats.add(chat);
    }
    if (chats.isEmpty) return _empty('No active chats');
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, i) {
        final chat = chats[i];
        final identity = roomChat.allIdentity[chat.interlocutorId] ??
            Identity(
              mId: chat.interlocutorId,
              signed: false,
              isContact: false,
              name: chat.chatName,
            );
        final messages = roomChat.messagesList[chat.chatId];
        // Messages are rich text: the preview is their text only.
        final last = messages != null && messages.isNotEmpty
            ? messages.last.msg
                ?.replaceAll(RegExp('<[^>]*>'), '')
                .replaceAll('&nbsp;', ' ')
                .trim()
            : null;
        final unread = chat.unreadCount;
        return ListTile(
          leading: IdentityAvatar(identity: identity),
          title: Text(identity.name ?? chat.chatName ?? identity.mId),
          subtitle: Text(
            last != null && last.isNotEmpty
                ? last
                : (identity.isContact ? 'Saved Contact' : 'Distant Chat'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () async {
            final current =
                Provider.of<Identities>(context, listen: false).currentIdentity;
            if (current == null) return;
            final chatData = await Provider.of<RoomChatLobby>(
              context,
              listen: false,
            ).getChat(current, chat);
            if (chatData == null || !mounted) return;
            await _openChat(chatData);
          },
        );
      },
    );
  }
}
