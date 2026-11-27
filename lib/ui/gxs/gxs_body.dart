import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// The rich text of a forum or channel post. Pictures embedded in the text
/// are shown; links are not followed.
class GxsBody extends StatelessWidget {
  const GxsBody(this.html, {super.key});

  final String html;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Html(
        data: html,
        shrinkWrap: true,
        extensions: [
          TagExtension(
            tagsToExtend: {'img'},
            builder: (extensionContext) {
              final src = extensionContext.attributes['src'];
              if (src == null || !src.contains('base64,')) {
                return const SizedBox.shrink();
              }
              try {
                return Image.memory(
                  base64Decode(src.split('base64,').last.trim()),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image),
                );
              } on FormatException {
                return const Icon(Icons.broken_image);
              }
            },
          ),
        ],
      ),
    );
  }
}
