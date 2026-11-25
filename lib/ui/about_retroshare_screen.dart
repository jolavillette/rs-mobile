import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// Preferences > About, as on the desktop: the versions in use and the
/// libraries libretroshare is built with, with a button to copy them all.
class AboutRetroShareScreen extends StatefulWidget {
  const AboutRetroShareScreen({super.key});

  @override
  State<AboutRetroShareScreen> createState() => _AboutRetroShareScreenState();
}

class _AboutRetroShareScreenState extends State<AboutRetroShareScreen> {
  // The commits built in, passed by the build script (--dart-define); empty
  // for a build made elsewhere.
  static const _mobileGit = String.fromEnvironment('RS_MOBILE_GIT');
  static const _wrapperGit = String.fromEnvironment('RS_WRAPPER_GIT');
  static const _libGit = String.fromEnvironment('RS_LIB_GIT');

  // The build's own name, as in the file name of the package:
  // <date>-<app commits>-g<app commit>-lib-<lib commits>-g<lib commit>.
  static const _build = String.fromEnvironment('RS_VERSION');

  /// (name, version) rows, in display order.
  List<(String, String)> _versions = [];
  List<(String, String)>? _libraries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final package = await PackageInfo.fromPlatform();
    var core = 'unavailable';
    try {
      final response = await rsApiCall('/rsJsonApi/version')
          .timeout(const Duration(seconds: 5));
      final human = response['human'];
      if (human is String && human.trim().isNotEmpty) core = human.trim();
    } catch (e) {
      debugPrint('About: cannot read the libretroshare version: $e');
    }
    List<(String, String)>? libraries;
    if (!mounted) return;
    final authToken =
        Provider.of<AccountCredentials>(context, listen: false).authtoken;
    if (authToken != null) {
      try {
        final response =
            await rsApiCall('/rsControl/getLibraries', authToken: authToken);
        final list = response['libraries'];
        if (list is List) {
          libraries = [
            for (final l in list.whereType<Map>())
              ('${l['mName'] ?? ''}', '${l['mVersion'] ?? ''}'),
          ];
        }
      } catch (e) {
        debugPrint('About: cannot read the libraries: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _versions = [
        if (_build.isNotEmpty) ('Build', _build),
        (
          'RetroShare Mobile',
          '${package.version} (build ${package.buildNumber})'
              '${_mobileGit.isEmpty ? '' : ', git $_mobileGit'}',
        ),
        (
          'libretroshare',
          '$core${_libGit.isEmpty ? '' : ' (git $_libGit)'}',
        ),
        if (_wrapperGit.isNotEmpty) ('Retroshare-Wrapper', 'git $_wrapperGit'),
        ('Android', Platform.operatingSystemVersion),
        ('Dart', Platform.version.split(' ').first),
      ];
      _libraries = libraries;
    });
  }

  String get _asText => [
        for (final (name, version) in _versions) '$name: $version',
        if (_libraries != null) ...[
          '',
          'libretroshare libraries:',
          for (final (name, version) in _libraries!) '  $name: $version',
        ],
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row((String, String) entry) => ListTile(
          dense: true,
          title: Text(entry.$1),
          subtitle: SelectableText(entry.$2),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: _versions.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: _asText));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Versions copied.')),
                    );
                  },
          ),
        ],
      ),
      body: _versions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Versions', style: text.titleSmall),
                ),
                for (final entry in _versions) row(entry),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Libraries', style: text.titleSmall),
                ),
                if (_libraries == null)
                  const ListTile(
                    dense: true,
                    title: Text('Not given by this libretroshare'),
                  )
                else
                  for (final entry in _libraries!) row(entry),
              ],
            ),
    );
  }
}
