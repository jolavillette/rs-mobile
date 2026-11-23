import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:retroshare/common/identicon.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare_api_wrapper/retroshare.dart' show Identity;

/// The avatar of an identity, or its identicon when it has none.
class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({required this.identity, this.size = 40, super.key});

  final Identity identity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = identity.avatar;
    final shape = BoxDecoration(
      borderRadius: BorderRadius.circular(RsScale.rMd),
      border: Border.all(color: context.rs.line),
      image: avatar != null && avatar.isNotEmpty
          ? DecorationImage(
              fit: BoxFit.cover,
              image: MemoryImage(base64.decode(avatar)),
            )
          : null,
    );
    return Container(
      width: size,
      height: size,
      decoration: shape,
      child: avatar == null || avatar.isEmpty
          ? Identicon(id: identity.mId, size: size, borderRadius: RsScale.rMd)
          : null,
    );
  }
}
