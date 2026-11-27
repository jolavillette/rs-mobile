import 'package:flutter/material.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';

enum _GroupAction { allRead, allUnread, syncPeriod, storagePeriod }

/// The menu of an open forum or channel: mark every post read or unread,
/// and, for a subscribed group, how far back posts are asked for and how
/// long they are kept. The periods are those the desktop offers.
class GxsGroupMenu extends StatelessWidget {
  const GxsGroupMenu({
    required this.content,
    required this.groupId,
    required this.subscribed,
    required this.posts,
    required this.onChanged,
    super.key,
  });

  /// Null until the page has read the group.
  final GxsContent? content;
  final String groupId;
  final bool subscribed;

  /// Every post of the group the page knows.
  final List<GxsPostMeta> Function() posts;

  /// Called once the read marks have changed.
  final VoidCallback onChanged;

  /// Days, as the desktop's menus; 0 is no limit.
  static const Map<int, String> _periods = {
    5: '5 days',
    15: '2 weeks',
    30: '1 month',
    90: '3 months',
    180: '6 months',
    365: '1 year',
    1095: '3 years',
    1825: '5 years',
    0: 'Indefinitely',
  };

  Future<void> _run(BuildContext context, _GroupAction action) async {
    final content = this.content;
    if (content == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _GroupAction.allRead:
        case _GroupAction.allUnread:
          await content.setAllRead(
            groupId,
            posts(),
            read: action == _GroupAction.allRead,
          );
          onChanged();
        case _GroupAction.syncPeriod:
          final current = await content.syncDays(groupId);
          if (!context.mounted) return;
          final days = await _choose(
            context,
            'Synchronise posts of last...',
            current,
          );
          if (days != null) await content.setSyncDays(groupId, days);
        case _GroupAction.storagePeriod:
          final current = await content.storageDays(groupId);
          if (!context.mounted) return;
          final days = await _choose(
            context,
            'Store posts for at most...',
            current,
          );
          if (days != null) await content.setStorageDays(groupId, days);
      }
    } catch (error) {
      debugPrint('Group $groupId: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('The core did not take the change.')),
      );
    }
  }

  /// The period picked among the desktop's, or null when the dialog is
  /// dismissed or the current one is picked again.
  Future<int?> _choose(BuildContext context, String title, int current) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title, style: const TextStyle(fontSize: RsScale.tH3)),
        children: [
          for (final period in _periods.entries)
            ListTile(
              dense: true,
              leading: Icon(
                period.key == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(period.value),
              onTap: () => Navigator.pop(
                dialogContext,
                period.key == current ? null : period.key,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_GroupAction>(
      onSelected: (action) => _run(context, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _GroupAction.allRead,
          child: Text('Mark all as read'),
        ),
        const PopupMenuItem(
          value: _GroupAction.allUnread,
          child: Text('Mark all as unread'),
        ),
        if (subscribed) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _GroupAction.syncPeriod,
            child: Text('Synchronise posts of last...'),
          ),
          const PopupMenuItem(
            value: _GroupAction.storagePeriod,
            child: Text('Store posts for at most...'),
          ),
        ],
      ],
    );
  }
}
