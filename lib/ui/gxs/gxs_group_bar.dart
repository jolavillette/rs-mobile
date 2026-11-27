import 'package:flutter/material.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';

/// What a forum or channel page shows above its posts: the description and
/// the button to follow or leave it.
class GxsGroupBar extends StatelessWidget {
  const GxsGroupBar({
    required this.kind,
    required this.subscribed,
    required this.description,
    required this.busy,
    required this.onSubscribe,
    super.key,
  });

  final GxsContentKind kind;
  final bool subscribed;
  final String description;
  final bool busy;
  final void Function(bool subscribe) onSubscribe;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Padding(
      padding: const EdgeInsets.all(RsScale.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: RsScale.s3),
              child: Text(
                description.trim(),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: RsScale.tRow, color: rs.inkBody),
              ),
            ),
          if (!subscribed)
            Padding(
              padding: const EdgeInsets.only(bottom: RsScale.s3),
              child: Text(
                'This phone does not follow this ${kind.noun}: it has none '
                'of its posts. Followed, it gets those of the last 15 days '
                'from the friends that serve it.',
                style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
              ),
            ),
          if (subscribed)
            OutlinedButton(
              onPressed: busy ? null : () => onSubscribe(false),
              child: const Text('Stop following'),
            )
          else
            FilledButton(
              onPressed: busy ? null : () => onSubscribe(true),
              child: const Text('Follow'),
            ),
        ],
      ),
    );
  }
}
