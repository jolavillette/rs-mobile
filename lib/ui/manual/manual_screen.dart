import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:retroshare/ui/manual/manual_pages.dart';

/// Opens the page [page] of the manual (a key of [manualPages]).
Future<void> openManual(BuildContext context, [String page = 'index']) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ManualScreen(page: page)),
    );

/// The **?** button of a page: opens the part of the manual that explains it.
class ManualButton extends StatelessWidget {
  const ManualButton(this.page, {super.key});

  final String page;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => openManual(context, page),
        tooltip: 'Manual',
        icon: const Icon(Icons.help_outline_rounded),
      );
}

/// One page of the manual. Its links open other pages.
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key, this.page = 'index'});

  final String page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdown = manualPages[page] ?? manualPages['index']!;
    final heading = RegExp(r'^# (.+)$', multiLine: true).firstMatch(markdown);
    return Scaffold(
      appBar: AppBar(
        title: Text(heading?.group(1) ?? 'Manual'),
        actions: [
          if (page != 'index')
            IconButton(
              onPressed: () => openManual(context),
              tooltip: 'Contents',
              icon: const Icon(Icons.menu_book_outlined),
            ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          // Down to above the system navigation bar.
          padding: EdgeInsets.fromLTRB(
            8,
            0,
            8,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            Html(
              data: manualHtml(markdown, withTitle: false),
              style: {
                'body': Style(
                    fontSize: FontSize(15), lineHeight: LineHeight.number(1.4)),
                'a': Style(
                  color: theme.colorScheme.primary,
                  textDecoration: TextDecoration.none,
                ),
                'code': Style(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  fontFamily: 'monospace',
                ),
              },
              onLinkTap: (url, attributes, element) {
                if (url == null || !url.endsWith('.md')) return;
                final target = url.substring(0, url.length - 3);
                if (manualPages.containsKey(target)) {
                  openManual(context, target);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The HTML of a page written in the manual's Markdown: headings, paragraphs,
/// lists, **bold**, `code` and [links](page.md). [withTitle] keeps the first
/// heading, which the app bar otherwise shows.
String manualHtml(String markdown, {bool withTitle = true}) {
  final out = StringBuffer();
  final paragraph = <String>[];
  String? list; // 'ul' or 'ol' while a list is open
  final item = <String>[];
  var titleSkipped = withTitle;

  void flushItem() {
    if (item.isEmpty) return;
    out.write('<li>${_inline(item.join(' '))}</li>');
    item.clear();
  }

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    out.write('<p>${_inline(paragraph.join(' '))}</p>');
    paragraph.clear();
  }

  void closeList() {
    flushItem();
    if (list != null) out.write('</$list>');
    list = null;
  }

  final bullet = RegExp(r'^- (.*)$');
  final numbered = RegExp(r'^\d+\. (.*)$');
  final heading = RegExp(r'^(#{1,3}) (.*)$');

  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) {
      flushParagraph();
      closeList();
      continue;
    }
    final h = heading.firstMatch(line);
    if (h != null) {
      flushParagraph();
      closeList();
      final level = h.group(1)!.length;
      if (level == 1 && !titleSkipped) {
        titleSkipped = true;
        continue;
      }
      out.write('<h${level + 1}>${_inline(h.group(2)!)}</h${level + 1}>');
      continue;
    }
    final b = bullet.firstMatch(line);
    final n = numbered.firstMatch(line);
    if (b != null || n != null) {
      flushParagraph();
      final kind = b != null ? 'ul' : 'ol';
      if (list != kind) {
        closeList();
        out.write('<$kind>');
        list = kind;
      }
      flushItem();
      item.add((b ?? n)!.group(1)!);
      continue;
    }
    if (list != null && line.startsWith(' ')) {
      item.add(trimmed);
      continue;
    }
    closeList();
    paragraph.add(trimmed);
  }
  flushParagraph();
  closeList();
  return out.toString();
}

String _inline(String text) {
  var html = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  html = html.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => '<code>${m[1]}</code>',
  );
  html = html.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => '<b>${m[1]}</b>',
  );
  html = html.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'),
    (m) => '<a href="${m[2]}">${m[1]}</a>',
  );
  return html;
}
