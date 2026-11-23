import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/bottom_bar.dart';
import 'package:retroshare/common/drawer.dart';
import 'package:retroshare/common/person_delegate.dart';
import 'package:retroshare/common/show_dialog.dart';
import 'package:retroshare/common/shimmer.dart';
import 'package:retroshare/common/styles.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/common/rs_tokens.dart';

class ChangeIdentityScreen extends StatefulWidget {
  const ChangeIdentityScreen({super.key});

  @override
  ChangeIdentityScreenState createState() => ChangeIdentityScreenState();
}

class ChangeIdentityScreenState extends State<ChangeIdentityScreen> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<Identities>(context, listen: false).fetchOwnidenities();
    });
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FutureBuilder(
            future: Provider.of<Identities>(context, listen: false)
                .fetchOwnidenities(),
            builder: (context, snapshot) {
              return snapshot.connectionState == ConnectionState.done
                  ? ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: Provider.of<Identities>(context, listen: false)
                          .ownIdentity
                          .length,
                      itemBuilder: (BuildContext context, int index) {
                        return PersonDelegate(
                          data: PersonDelegateData.identityData(
                            Provider.of<Identities>(context, listen: false)
                                .ownIdentity[index],
                            context,
                          ),
                          isSelectable: true,
                          onPressed: () {
                            final id =
                                Provider.of<Identities>(context, listen: false)
                                    .ownIdentity[index];
                            Provider.of<Identities>(context, listen: false)
                                .updateSelectedIdentity(id);
                          },
                          // Identities are deleted from this list, and never
                          // the active one: the user switches first.
                          onLongPress: (Offset tapPosition) {
                            final ids =
                                Provider.of<Identities>(context, listen: false);
                            final id = ids.ownIdentity[index];
                            if (id.mId == ids.currentIdentity?.mId) return;
                            showCustomMenu(
                              'Delete identity',
                              const Icon(Icons.delete, color: Colors.black),
                              () => showdeleteDialog(
                                context,
                                id,
                                onDeleted: () => setState(() {}),
                              ),
                              tapPosition,
                              context,
                            );
                          },
                        );
                      },
                    )
                  : changeIdentityShimmer();
            },
          ),
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: Center(
          child: SizedBox(
            height: 2 * appBarHeight / 3,
            child: ElevatedButton(
              onPressed: () {
                Provider.of<Identities>(context, listen: false)
                    .updateCurrentIdentity();
                Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0 + personDelegateHeight * 0.04,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(RsScale.rSm),
                      gradient: context.rs.actionGradient,
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'Change Identity',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
