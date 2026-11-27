import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/apiUtils/gxs_content.dart';
import 'package:retroshare/common/rs_tokens.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

enum _FileState { unknown, absent, downloading, complete }

/// A file of a channel post: its name and size, and the download. The file
/// is asked from the core on a tap, never by itself; its progress is read
/// once a second while it downloads and this row is on screen.
class GxsFileTile extends StatefulWidget {
  const GxsFileTile(this.file, {super.key});

  final GxsFile file;

  @override
  State<GxsFileTile> createState() => _GxsFileTileState();
}

class _GxsFileTileState extends State<GxsFileTile> {
  // Where the core looks the hash up: its downloads, its shared and extra
  // files (RS_FILE_HINTS_EXTRA | LOCAL | REMOTE | DOWNLOAD | UPLOAD).
  static const int _everywhere = 62;
  // RS_FILE_REQ_ANONYMOUS_ROUTING: the sources are found through tunnels.
  static const int _anonymousRouting = 0x40;
  // FT_STATE_* of the core.
  static const Set<int> _complete = {1, 4};
  static const Set<int> _active = {2, 3, 5, 7};

  _FileState _state = _FileState.unknown;
  double _progress = 0;
  double _rate = 0;
  String? _path;
  Timer? _timer;

  AuthToken? get _token =>
      Provider.of<AccountCredentials>(context, listen: false).authtoken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static bool _ok(Object? retval) => retval == true || retval == 1;

  static int _int(Object? value, int otherwise) {
    if (value is int) return value;
    if (value is Map) {
      return int.tryParse('${value['xstr64']}') ??
          (value['xint64'] is int ? value['xint64'] as int : otherwise);
    }
    return otherwise;
  }

  /// Reads from the core where the file stands.
  Future<void> _read() async {
    final token = _token;
    if (token == null || !mounted) return;
    try {
      final response = await rsApiCall(
        '/rsFiles/FileDetails',
        authToken: token,
        params: {'hash': widget.file.hash, 'hintflags': _everywhere},
      );
      if (!mounted) return;
      final info = response['info'];
      if (!_ok(response['retval']) || info is! Map) {
        _show(_FileState.absent);
        return;
      }
      final status = _int(info['downloadStatus'], 0);
      final path = _fullPath(info);
      if (_complete.contains(status) ||
          (status == 0 && path.isNotEmpty && File(path).existsSync())) {
        _path = path;
        _show(_FileState.complete);
      } else if (_active.contains(status)) {
        final size = _int(info['size'], widget.file.size);
        _progress = size > 0 ? _int(info['transfered'], 0) / size : 0;
        final rate = info['tfRate'];
        _rate = rate is num ? rate.toDouble() : 0;
        _show(_FileState.downloading);
      } else {
        _show(_FileState.absent);
      }
    } catch (error) {
      debugPrint('File ${widget.file.hash}: $error');
    }
  }

  /// The file's place on the phone: the core gives its directory, or its
  /// full path.
  String _fullPath(Map<dynamic, dynamic> info) {
    final path = info['path'] is String ? info['path'] as String : '';
    final name =
        info['fname'] is String ? info['fname'] as String : widget.file.name;
    if (path.isEmpty || path.endsWith(name)) return path;
    return path.endsWith('/') ? '$path$name' : '$path/$name';
  }

  void _show(_FileState state) {
    if (state == _FileState.downloading) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _read());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    setState(() => _state = state);
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _download() async {
    final token = _token;
    if (token == null) return;
    try {
      final response = await rsApiCall(
        '/rsFiles/FileRequest',
        authToken: token,
        params: {
          'fileName': widget.file.name,
          'hash': widget.file.hash,
          'size': {
            'xstr64': '${widget.file.size}',
            'xint64': widget.file.size,
          },
          'destPath': '',
          'flags': _anonymousRouting,
          'srcIds': <String>[],
        },
      );
      if (!_ok(response['retval'])) {
        _say('The core refused this download.');
        return;
      }
      if (!mounted) return;
      _progress = 0;
      _rate = 0;
      _show(_FileState.downloading);
    } catch (error) {
      debugPrint('File ${widget.file.hash}: $error');
      _say('Could not start this download.');
    }
  }

  Future<void> _cancel() async {
    final token = _token;
    if (token == null) return;
    try {
      await rsApiCall(
        '/rsFiles/FileCancel',
        authToken: token,
        params: {'hash': widget.file.hash},
      );
    } catch (error) {
      debugPrint('File ${widget.file.hash}: $error');
    }
    await _read();
  }

  Future<void> _openFile() async {
    final path = _path;
    if (path == null || !File(path).existsSync()) {
      _say('The file is no longer on this phone.');
      await _read();
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _say('No app on this phone opens this file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final size = gxsSize(widget.file.size);
    final downloading = _state == _FileState.downloading;
    return ListTile(
      leading: Icon(
        _state == _FileState.complete
            ? Icons.check_circle_outline
            : Icons.insert_drive_file_outlined,
        color: _state == _FileState.complete ? rs.upInk : rs.inkDim,
      ),
      title: Text(
        widget.file.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: RsScale.tRow),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (_state) {
              _FileState.downloading =>
                '${(_progress * 100).toStringAsFixed(2)} % of $size · '
                    '${_rate.toStringAsFixed(2)} kB/s',
              _FileState.complete => '$size · on this phone',
              _ => size,
            },
            style: TextStyle(fontSize: RsScale.tMeta, color: rs.inkDim),
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.only(top: RsScale.s1),
              child: LinearProgressIndicator(value: _progress.clamp(0, 1)),
            ),
        ],
      ),
      trailing: switch (_state) {
        _FileState.unknown => null,
        _FileState.absent => IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: _download,
          ),
        _FileState.downloading => IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: _cancel,
          ),
        _FileState.complete => IconButton(
            tooltip: 'Open',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openFile,
          ),
      },
    );
  }
}
