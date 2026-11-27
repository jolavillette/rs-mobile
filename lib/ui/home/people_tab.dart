import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare/ui/identities/own_identities_list.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Chat, Identity;

/// People: identities, filtered to my own identities (shown first: where
/// the active one is chosen and where they are created, edited and deleted),
/// my contacts or every identity known. The distant chats with them are in
/// Chat.
class PeopleTab extends StatefulWidget {
  const PeopleTab({required this.open, this.onOpenRoom, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  /// Opens a chat in the detail pane on a desktop layout.
  final Future<void> Function(Chat chat, bool isRoom)? onOpenRoom;

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

enum _Filter {
  own('My Identities', Icons.person_outline),
  contacts('Contacts', Icons.people_outline),
  all('All Users', Icons.groups_outlined);

  const _Filter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Rows shown at most: "All Users" can be tens of thousands of identities on
/// an old node, the search narrows the list.
const _listCap = 200;

class _PeopleTabState extends State<PeopleTab> {
  _Filter _filter = _Filter.own;
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

  Future<bool> _setContact(Identity identity, bool isContact) async {
    try {
      await Provider.of<RoomChatLobby>(context, listen: false)
          .toggleContacts(identity.mId, isContact);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The contact list could not be changed.'),
          ),
        );
      }
      return false;
    }
  }

  /// Picks one of the identities known to the node that is not a contact
  /// yet, and makes it a contact.
  Future<void> _addContact() async {
    final roomChat = Provider.of<RoomChatLobby>(context, listen: false);
    final own = Provider.of<Identities>(context, listen: false)
        .ownIdentity
        .map((i) => i.mId)
        .toSet();
    final candidates = <String, Identity>{
      for (final i in [
        ...roomChat.friendsSignedIdsList,
        ...roomChat.notContactIds,
      ])
        if (!i.isContact && !own.contains(i.mId)) i.mId: i,
    }.values.toList()
      ..sort(_byName);
    final picked = await showModalBottomSheet<Identity>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddContactSheet(candidates: candidates),
    );
    if (picked == null || !mounted) return;
    if (!await _setContact(picked, true) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${picked.name ?? 'The identity'} is now a contact.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomChat = context.watch<RoomChatLobby>();

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
                  if (_filter == _Filter.own) ...[
                    const SizedBox(width: RsScale.s2),
                    IconButton.filled(
                      tooltip: 'Create New Identity',
                      icon: const Icon(Icons.add),
                      onPressed: () => widget.open('/create_identity'),
                    ),
                  ],
                  if (_filter == _Filter.contacts) ...[
                    const SizedBox(width: RsScale.s2),
                    IconButton.filled(
                      tooltip: 'Add a contact',
                      icon: const Icon(Icons.person_add_alt),
                      onPressed: _addContact,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: RsScale.s2),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Filter>(
                  segments: [
                    for (final f in _Filter.values)
                      ButtonSegment(value: f, label: Text(f.label)),
                  ],
                  selected: {_filter},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filter == _Filter.own
              ? OwnIdentitiesList(open: widget.open, search: _search)
              : _identityList(context, roomChat),
        ),
      ],
    );
  }

  Widget _empty(String text) => Center(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

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
        _filter == _Filter.contacts
            ? (_search.isEmpty
                ? 'No contacts yet: + adds one'
                : 'No contacts found')
            : 'No identities found',
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
}

/// The identities that can become contacts, with a search: the web UI picks
/// them in All Users, this sheet does it from the Contacts list.
class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.candidates});

  final List<Identity> candidates;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final search = _search.toLowerCase();
    final list = widget.candidates
        .where((i) => (i.name ?? i.mId).toLowerCase().contains(search))
        .toList();
    final shown = list.take(_listCap).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RsScale.s4,
                RsScale.s4,
                RsScale.s4,
                RsScale.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a contact', style: text.titleMedium),
                  const SizedBox(height: RsScale.s1),
                  Text(
                    'Identities your node knows of: from your friends, the '
                    'chat rooms and the forums.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: RsScale.s3),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name',
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text('No identity found', style: text.bodyMedium),
                    )
                  : ListView.builder(
                      itemCount:
                          shown.length + (list.length > shown.length ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == shown.length) {
                          return Padding(
                            padding: const EdgeInsets.all(RsScale.s4),
                            child: Text(
                              '${list.length - shown.length} more identities '
                              '— search to narrow the list',
                              textAlign: TextAlign.center,
                              style: text.bodySmall,
                            ),
                          );
                        }
                        final identity = shown[i];
                        return ListTile(
                          leading: IdentityAvatar(identity: identity),
                          title: Text(identity.name ?? identity.mId),
                          subtitle: Text(
                            identity.signed
                                ? 'Signed identity'
                                : 'Pseudonymous identity',
                          ),
                          trailing: const Icon(Icons.person_add_alt),
                          onTap: () => Navigator.of(context).pop(identity),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
