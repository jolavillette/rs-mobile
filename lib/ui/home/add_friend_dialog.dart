import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/friend_location.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// Add a Friend, as in the web UI: paste (or scan) the friend's RetroShare
/// ID, check who it is, then add.
Future<void> showAddFriendDialog(BuildContext context) async {
  final invite = await showDialog<String>(
    context: context,
    builder: (_) => const _PasteIdDialog(),
  );
  if (invite == null || invite.trim().isEmpty || !context.mounted) return;
  await _confirmAndAdd(context, invite.trim());
}

class _PasteIdDialog extends StatefulWidget {
  const _PasteIdDialog();

  @override
  State<_PasteIdDialog> createState() => _PasteIdDialogState();
}

class _PasteIdDialogState extends State<_PasteIdDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (!(await Permission.camera.request()).isGranted || !mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.75,
        child: MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes.isNotEmpty
                ? capture.barcodes.first.rawValue
                : null;
            if (value != null) Navigator.of(sheetContext).pop(value);
          },
        ),
      ),
    );
    if (code != null) setState(() => _controller.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Add a Friend'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Paste your friend's RetroShare ID to connect.",
              style: text.bodyMedium,
            ),
            const SizedBox(height: RsScale.s3),
            Text("Friend's RetroShare ID", style: text.labelMedium),
            const SizedBox(height: RsScale.s1),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 6,
              style: const TextStyle(fontFamily: RsScale.fontMono),
              decoration: const InputDecoration(
                hintText: 'Paste the RetroShare ID here',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: RsScale.s2),
            Center(child: Text('or', style: text.bodySmall)),
            const SizedBox(height: RsScale.s2),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan a QR code'),
              onPressed: _scan,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add friend'),
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}

/// The details of an invite, from the core: a short invite or a full
/// certificate.
Future<Map<String, dynamic>?> _inviteDetails(
  AuthToken authToken,
  String invite,
) async {
  try {
    final details = await RsPeers.parseShortInvite(authToken, invite);
    if (details.isNotEmpty) return details;
  } catch (_) {
    // Not a short invite: try a full certificate.
  }
  try {
    final response = await rsApiCall(
      '/rsPeers/loadDetailsFromStringCert',
      authToken: authToken,
      params: {'cert': invite},
    );
    if (response['retval'] == true && response['certDetails'] is Map) {
      return Map<String, dynamic>.from(response['certDetails'] as Map);
    }
  } catch (_) {
    // Neither: the ID is not valid.
  }
  return null;
}

/// The ID itself, as the web UI cleans it: what follows "rsInvite=" in a
/// link, URL-decoded.
String _cleanId(String value) {
  final input = value.trim();
  const marker = 'rsInvite=';
  final at = input.indexOf(marker);
  final id = at >= 0 ? input.substring(at + marker.length) : input;
  try {
    return Uri.decodeComponent(id).trim();
  } catch (_) {
    return id.trim();
  }
}

Future<void> _confirmAndAdd(BuildContext context, String pasted) async {
  final invite = _cleanId(pasted);
  final messenger = ScaffoldMessenger.of(context);
  final authToken =
      Provider.of<AccountCredentials>(context, listen: false).authtoken;
  if (authToken == null) return;
  final details = await _inviteDetails(authToken, invite);
  if (!context.mounted) return;
  if (details == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Check the ID and try again.')),
    );
    return;
  }

  final hidden = details['isHiddenNode'] == true;
  String field(String key) {
    final value = details[key];
    return value == null || '$value'.isEmpty ? 'Unknown' : '$value';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final text = Theme.of(dialogContext).textTheme;
      Widget row(String label, String value, {bool mono = false}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: RsScale.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label, style: text.labelMedium),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: mono
                        ? const TextStyle(fontFamily: RsScale.fontMono)
                        : text.bodyMedium,
                  ),
                ),
              ],
            ),
          );
      return AlertDialog(
        title: const Text('Make Friend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirm this is the person you want to add.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: RsScale.s3),
            row('Name', field('name')),
            row('Location', field('location')),
            row('Peer ID', field('id'), mono: true),
            row(
              hidden ? 'Hidden address' : 'Address',
              hidden ? field('hiddenNodeAddress') : field('extAddr'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Finish'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;

  final friends = Provider.of<FriendLocations>(context, listen: false);
  try {
    await friends.addFriendLocation(invite);
    await friends.fetchfriendLocation();
    messenger.showSnackBar(
      const SnackBar(content: Text('Successfully added friend.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('An error occurred during adding. Friend not added.'),
      ),
    );
  }
}
