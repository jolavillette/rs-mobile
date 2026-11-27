import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/node_avatars.dart';

/// The avatar of a node, of a friend (the first of their nodes that has
/// one) or of my own node, in a circle; the first letter of [name] while
/// there is none. [statusColor] adds the presence dot of the web UI.
class NodeAvatar extends StatelessWidget {
  const NodeAvatar({
    required this.name,
    this.nodeIds = const [],
    this.own = false,
    this.radius = 18,
    this.statusColor,
    super.key,
  });

  final String name;

  /// The nodes whose avatar is looked for, in order.
  final List<String> nodeIds;

  /// My own node instead of [nodeIds].
  final bool own;

  final double radius;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    final side = radius * 2 + 4;
    final dot = radius * 2 / 3;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: NodeAvatars.instance,
            builder: (context, _) {
              final image = authToken == null
                  ? null
                  : own
                      ? NodeAvatars.instance.own(authToken)
                      : NodeAvatars.instance.ofAny(nodeIds, authToken);
              return CircleAvatar(
                radius: radius,
                backgroundColor: rs.brandPale,
                foregroundColor: rs.brandDeep,
                backgroundImage: image == null ? null : MemoryImage(image),
                child: image == null
                    ? Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: TextStyle(fontSize: radius),
                      )
                    : null,
              );
            },
          ),
          if (statusColor != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: rs.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
