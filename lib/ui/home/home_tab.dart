import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/ui/home/add_friend_dialog.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:share_plus/share_plus.dart';

/// Home, as in the web UI: the page to add friends. It shows my RetroShare ID
/// to send to a friend, and adds a friend from the ID they sent me.
class HomeTab extends StatefulWidget {
  const HomeTab({required this.open, super.key});

  /// Opens a named route (in the detail pane on a desktop layout).
  final void Function(String route, {Object? arguments}) open;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String _ownId = '';

  @override
  void initState() {
    super.initState();
    _loadOwnId();
  }

  Future<void> _loadOwnId() async {
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (authToken == null) return;
    try {
      final id = await RsPeers.getShortInvite(authToken);
      if (mounted) setState(() => _ownId = id);
    } catch (e) {
      debugPrint('Cannot get my RetroShare ID: $e');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ownId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'RetroShare ID copied. Send it to your friend however you like.',
        ),
      ),
    );
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(text: _ownId, title: 'My RetroShare ID'),
    );
  }

  void _showQr() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('My RetroShare ID'),
        content: SizedBox(
          width: 260,
          height: 260,
          child: QrImageView(
            data: _ownId,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final text = Theme.of(context).textTheme;
    final ready = _ownId.isNotEmpty;

    Widget question(String label) => Padding(
          padding: const EdgeInsets.only(bottom: RsScale.s2),
          child: Text(label, style: text.titleSmall),
        );

    return ListView(
      padding: const EdgeInsets.all(RsScale.s4),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/rs-logo.png', width: 56, height: 56),
            const SizedBox(width: RsScale.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'RETRO',
                        style: TextStyle(color: rs.brand),
                      ),
                      TextSpan(
                        text: 'SHARE',
                        style: TextStyle(color: rs.ink),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: RsScale.tTitle,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'secure communication for everyone',
                  style: text.labelMedium,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: RsScale.s5),
        Text('Welcome to RetroShare!', style: text.titleLarge),
        const SizedBox(height: RsScale.s1),
        Text(
          'RetroShare is an Open Source Cross-platform, Private and Secure '
          'Decentralized Communication Platform.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: RsScale.s5),
        question('This is your RetroShare ID. Copy and share with your friends!'),
        Container(
          padding: const EdgeInsets.all(RsScale.s3),
          decoration: BoxDecoration(
            color: rs.sunken,
            border: Border.all(color: rs.line),
            borderRadius: BorderRadius.circular(RsScale.rMd),
          ),
          child: ready
              ? SelectableText(
                  _ownId,
                  style: TextStyle(
                    fontFamily: RsScale.fontMono,
                    fontSize: RsScale.tMeta,
                    color: rs.inkBody,
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: RsScale.s2),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: RsScale.s2,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
              onPressed: ready ? _copy : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
              onPressed: ready ? _share : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code, size: 18),
              label: const Text('QR code'),
              onPressed: ready ? _showQr : null,
            ),
          ],
        ),
        const SizedBox(height: RsScale.s5),
        question('Did you receive a RetroShare ID from your friend?'),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add Friend'),
            onPressed: () => showAddFriendDialog(context),
          ),
        ),
        const SizedBox(height: RsScale.s5),
        question('Do you need help with RetroShare?'),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.public),
            label: const Text('Open Web Help'),
            onPressed: () => widget.open('/about'),
          ),
        ),
      ],
    );
  }
}
