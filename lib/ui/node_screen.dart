import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';
import 'package:share_plus/share_plus.dart';

/// Preferences > Node, as the desktop's: the profile (the PGP key, the same
/// on every device of its owner) and this node (the device). Identities are
/// another thing and are not shown here.
class NodeScreen extends StatefulWidget {
  const NodeScreen({super.key});

  @override
  State<NodeScreen> createState() => _NodeScreenState();
}

class _NodeScreenState extends State<NodeScreen> {
  String _retroshareId = '';
  bool _loadingId = true;

  /// Short: small, enough for a recent RetroShare, easy to scan. Long: the
  /// whole certificate, with the profile's PGP key.
  bool _longFormat = false;

  @override
  void initState() {
    super.initState();
    _loadRetroshareId();
  }

  Future<void> _loadRetroshareId() async {
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    var id = '';
    if (authToken != null) {
      try {
        id = _longFormat
            ? (await RsPeers.getOwnCert(authToken)).replaceAll('\n', '')
            : await RsPeers.getShortInvite(authToken);
      } catch (e) {
        debugPrint('Error fetching the RetroShare ID: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _retroshareId = id;
      _loadingId = false;
    });
  }

  void _setFormat(bool long) {
    if (long == _longFormat) return;
    setState(() {
      _longFormat = long;
      _loadingId = true;
    });
    _loadRetroshareId();
  }

  void _showQr() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_longFormat ? 'Long RetroShare ID' : 'RetroShare ID'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: _retroshareId),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = Provider.of<AccountCredentials>(context).loggedinAccount;
    String shown(String? v) => (v == null || v.isEmpty) ? '—' : v;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Node'),
        backgroundColor: theme.colorScheme.surface,
        shadowColor: Colors.transparent,
        leading: BackButton(
          color: theme.colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            _sectionTitle(
              context,
              'Profile',
              'You. The same on all your devices.',
            ),
            _infoTile(
              context,
              'Profile name',
              shown(account?.pgpName),
              Icons.person,
            ),
            _infoTile(
              context,
              'PGP ID',
              shown(account?.pgpId),
              Icons.security,
            ),
            const SizedBox(height: 16),
            _sectionTitle(
              context,
              'This node',
              'This device. Your friends connect to it.',
            ),
            _infoTile(
              context,
              'Node name',
              shown(account?.locationName),
              Icons.smartphone,
            ),
            _infoTile(
              context,
              'Node ID',
              shown(account?.locationId),
              Icons.vpn_key,
            ),
            const SizedBox(height: 16),
            _sectionTitle(
              context,
              'RetroShare ID',
              'Give it to a friend to be added. Short is enough between '
                  'recent versions; long carries your whole certificate.',
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Short')),
                ButtonSegment(value: true, label: Text('Long')),
              ],
              selected: {_longFormat},
              onSelectionChanged: (s) => _setFormat(s.first),
            ),
            const SizedBox(height: 10),
            _infoTile(
              context,
              _longFormat ? 'Long RetroShare ID' : 'Short RetroShare ID',
              _loadingId ? 'Loading...' : shown(_retroshareId),
              Icons.badge_outlined,
              maxLines: 6,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retroshareId.isEmpty
                        ? null
                        : () => SharePlus.instance
                            .share(ShareParams(text: _retroshareId)),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retroshareId.isEmpty ? null : _showQr,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('QR code'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String hint) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    int maxLines = 2,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(128),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: maxLines,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy to clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
