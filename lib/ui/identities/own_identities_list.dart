import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/common/show_dialog.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Identity;

/// My identities, as People (My Identities) and the Identities screen show
/// them: the active one marked; a tap opens the identity, its menu makes it
/// active, edits it or deletes it, never the active one; the list ends with a
/// row to create an identity. It follows the Identities provider, so a
/// created or deleted identity shows at once.
class OwnIdentitiesList extends StatelessWidget {
  const OwnIdentitiesList({required this.open, this.search = '', super.key});

  /// Opens a named route above the screen that shows the list.
  final void Function(String route, {Object? arguments}) open;

  /// Only the identities whose name contains it (case ignored).
  final String search;

  void _useIdentity(BuildContext context, Identity identity) {
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
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final ids = context.watch<Identities>();
    final current = ids.currentIdentity?.mId;
    final query = search.toLowerCase();
    final own = ids.ownIdentity
        .where((i) => (i.name ?? '').toLowerCase().contains(query))
        .toList()
      ..sort(
        (a, b) =>
            (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()),
      );
    return RefreshIndicator(
      onRefresh: ids.fetchOwnidenities,
      child: ListView.builder(
        itemCount: own.length + 1,
        itemBuilder: (context, i) {
          if (i == own.length) {
            return ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create a new identity'),
              onTap: () => open('/create_identity'),
            );
          }
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
            onTap: () => open('/profile', arguments: {'id': identity}),
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) {
                switch (action) {
                  case 'use':
                    _useIdentity(context, identity);
                  case 'edit':
                    open('/updateIdentity', arguments: {'id': identity});
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
              child: Padding(
                padding: const EdgeInsets.all(RsScale.s2),
                child: active
                    ? Icon(Icons.check_circle, color: rs.brand)
                    : Icon(Icons.more_vert, color: rs.inkDim),
              ),
            ),
            titleTextStyle:
                active ? text.titleSmall?.copyWith(color: rs.brand) : null,
          );
        },
      ),
    );
  }
}
