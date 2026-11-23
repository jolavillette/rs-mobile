import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare/provider/identity.dart';

/// Home, as in the web UI: who I am, how my node is doing, and how to add a
/// friend.
class HomeTab extends StatelessWidget {
  const HomeTab({required this.open, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final identity = context.watch<Identities>().currentIdentity;
    final account = context.watch<AccountCredentials>().loggedinAccount;
    final friends = context.watch<FriendLocations>().friendlist;
    final online = friends.where((f) => f.isOnline).length;

    return ListView(
      padding: const EdgeInsets.all(RsScale.s4),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(RsScale.s4),
            child: Row(
              children: [
                if (identity != null) IdentityAvatar(identity: identity, size: 56),
                const SizedBox(width: RsScale.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        identity?.name ?? account?.pgpName ?? 'RetroShare',
                        style: text.titleMedium,
                      ),
                      if (account != null)
                        Text(
                          '${account.pgpName} · ${account.locationName}',
                          style: text.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (identity != null)
                  IconButton(
                    tooltip: 'Edit identity',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        open('/updateIdentity', arguments: {'id': identity}),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RsScale.s3),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.circle,
              size: 12,
              color: online > 0 ? rs.up : rs.inkFaint,
            ),
            title: Text(online > 0 ? 'Online' : 'No friend connected'),
            subtitle: Text('$online of ${friends.length} friends connected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open('/friends_locations'),
          ),
        ),
        const SizedBox(height: RsScale.s4),
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add a friend'),
          onPressed: () => open('/add_friend'),
        ),
        const SizedBox(height: RsScale.s2),
        Text(
          'Share your invite or scan a friend\'s QR code.',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
      ],
    );
  }
}
