import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/provider/room.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// The participants of a room, as the desktop lists them: any of them can be
/// chatted with privately (a distant chat, whether the identity is a contact
/// or not), added to or removed from the contacts, or looked at.
class RoomFriendsTab extends StatefulWidget {
  const RoomFriendsTab({super.key, required this.chat});
  final Chat chat;
  @override
  RoomFriendsTabState createState() => RoomFriendsTabState();
}

class RoomFriendsTabState extends State<RoomFriendsTab> {
  Future<void>? _participantsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatId = widget.chat.chatId;
    if (chatId != null) {
      _participantsFuture ??=
          Provider.of<RoomChatLobby>(context, listen: false)
              .updateParticipants(chatId);
    }
  }

  /// Opens a distant chat with [participant], from the active identity.
  Future<void> _startPrivateChat(Identity participant) async {
    final current =
        Provider.of<Identities>(context, listen: false).currentIdentity;
    if (current == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chat = await Provider.of<RoomChatLobby>(context, listen: false)
          .getChat(current, participant);
      if (chat == null || !mounted) return;
      await Navigator.pushNamed(
        context,
        '/room',
        arguments: {'isRoom': false, 'chatData': chat},
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start a private chat: $e')),
      );
    }
  }

  Future<void> _setContact(Identity participant, bool isContact) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Provider.of<RoomChatLobby>(context, listen: false)
          .toggleContacts(participant.mId, isContact);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isContact ? 'Added to contacts.' : 'Removed from contacts.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The contact list could not be changed.')),
      );
    }
  }

  void _showActions(Identity participant) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: IdentityAvatar(identity: participant),
              title: Text(
                participant.name ?? participant.mId,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Start private chat'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startPrivateChat(participant);
              },
            ),
            ListTile(
              leading: Icon(
                participant.isContact
                    ? Icons.person_remove_outlined
                    : Icons.person_add_alt,
              ),
              title: Text(
                participant.isContact
                    ? 'Remove from contacts'
                    : 'Add to contacts',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _setContact(participant, !participant.isContact);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View details'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.pushNamed(
                  context,
                  '/profile',
                  arguments: {'id': participant},
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = widget.chat.chatId;
    if (chatId == null) {
      return const Center(child: Text('Error: Invalid chat room.'));
    }

    return FutureBuilder(
      future: _participantsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading participants: ${snapshot.error}'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return Consumer<RoomChatLobby>(
          builder: (context, lobbyData, _) {
            final participants = lobbyData.lobbyParticipants[chatId] ?? [];
            final currentIdentity =
                Provider.of<Identities>(context, listen: false).currentIdentity;
            final text = Theme.of(context).textTheme;
            if (participants.isEmpty) {
              return Center(
                child: Text(
                  'No participant yet.\nYou can invite your friends.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge,
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              // The first row names the list, as the web UI's
              // Participants (n).
              itemCount: participants.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Participants (${participants.length})',
                      style: text.titleSmall,
                    ),
                  );
                }
                final participant = participants[index - 1];
                final isMe = currentIdentity?.mId == participant.mId;
                return ListTile(
                  leading: IdentityAvatar(identity: participant),
                  title: Text(participant.name ?? participant.mId),
                  subtitle: Text(
                    isMe
                        ? 'You'
                        : participant.isContact
                            ? 'Contact'
                            : 'Identity',
                  ),
                  trailing: isMe
                      ? null
                      : IconButton(
                          tooltip: 'Start private chat',
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () => _startPrivateChat(participant),
                        ),
                  onTap: isMe ? null : () => _showActions(participant),
                );
              },
            );
          },
        );
      },
    );
  }
}
