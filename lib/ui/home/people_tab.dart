import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/identity_avatar.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/identity.dart';

/// People, as in the web UI: my identities first, the active one marked.
class PeopleTab extends StatefulWidget {
  const PeopleTab({required this.open, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  @override
  void initState() {
    super.initState();
    final ids = Provider.of<Identities>(context, listen: false);
    if (ids.ownIdentity.isEmpty) ids.fetchOwnidenities();
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final ids = context.watch<Identities>();
    final current = ids.currentIdentity?.mId;

    return RefreshIndicator(
      onRefresh: ids.fetchOwnidenities,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: RsScale.s2),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RsScale.s4,
              RsScale.s2,
              RsScale.s4,
              RsScale.s1,
            ),
            child: Text('My identities', style: text.labelMedium),
          ),
          for (final identity in ids.ownIdentity)
            ListTile(
              leading: IdentityAvatar(identity: identity),
              title: Text(identity.name ?? identity.mId),
              subtitle: Text(
                identity.signed ? 'Signed identity' : 'Pseudonymous identity',
              ),
              selected: identity.mId == current,
              trailing: identity.mId == current
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 18, color: rs.brand),
                        const SizedBox(width: RsScale.s1),
                        Text('Active', style: text.labelMedium),
                      ],
                    )
                  : null,
              onTap: () => widget.open('/profile', arguments: {'id': identity}),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Change the active identity'),
            onTap: () => widget.open('/change_identity'),
          ),
        ],
      ),
    );
  }
}
