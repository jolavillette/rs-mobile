import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/drawer.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/ui/identities/own_identities_list.dart';

/// The Identities screen (Settings): my identities, the same list as People,
/// My Identities. Routes open above this screen, so going back from an
/// identity returns here.
class ChangeIdentityScreen extends StatefulWidget {
  const ChangeIdentityScreen({super.key});

  @override
  ChangeIdentityScreenState createState() => ChangeIdentityScreenState();
}

class ChangeIdentityScreenState extends State<ChangeIdentityScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<Identities>(context, listen: false).fetchOwnidenities();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: appBar('Identities', context),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New identity'),
        onPressed: () => Navigator.pushNamed(context, '/create_identity'),
      ),
      body: SafeArea(
        child: OwnIdentitiesList(
          open: (route, {arguments}) =>
              Navigator.pushNamed(context, route, arguments: arguments),
        ),
      ),
    );
  }
}
