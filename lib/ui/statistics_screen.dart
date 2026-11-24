import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare_api_wrapper/retroshare.dart';

/// The node's traffic, received and sent kept apart: the speeds now with the
/// totals since the core started under them, then the same for each service.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

/// The columns of the table by service, which can sort it.
enum _Column { receivedRate, sentRate, received, sent }

class _StatisticsScreenState extends State<StatisticsScreen> {
  static const _friendlyServiceNames = <int, String>{
    0x0011: 'Discovery',
    0x0012: 'Chat',
    0x0013: 'Messages',
    0x0014: 'Turtle Router',
    0x0016: 'Heartbeat',
    0x0017: 'File Transfer',
    0x0018: 'Global Router',
    0x0019: 'File Database',
    0x0020: 'Service Info',
    0x0021: 'Bandwidth',
    0x0028: 'GXS Tunnels',
    0x0101: 'Banlist',
    0x0102: 'Status',
    0x0211: 'GXS Identity',
    0x0213: 'GXS Wiki',
    0x0214: 'GXS Wire',
    0x0215: 'GXS Forums',
    0x0216: 'GXS Boards',
    0x0217: 'GXS Channels',
    0x0218: 'GXS Circles',
    0x0219: 'GXS Reputation',
    0x0230: 'GXS Mails',
    0x1011: 'RTT',
    0x2003: 'FeedReader',
  };

  static const _refreshPeriod = Duration(seconds: 5);

  Timer? _refreshTimer;
  double _downloadRate = 0;
  double _uploadRate = 0;
  double _downloadedBytes = 0;
  double _uploadedBytes = 0;
  List<_ServiceTraffic> _serviceTraffic = const [];
  // The totals by service of the previous refresh, and when it was: each
  // service's speed is what it received and sent since.
  Map<int, (double, double)> _previousTotals = const {};
  DateTime? _previousTime;
  _Column _sortBy = _Column.received;
  bool _loading = true;
  bool _requestInProgress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(_refreshPeriod, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    try {
      final authToken =
          Provider.of<AccountCredentials>(context, listen: false).authtoken;
      if (authToken == null) throw Exception('Not authenticated');

      final responses = await Future.wait([
        rsApiCall(
          '/rsConfig/getTotalBandwidthRates',
          authToken: authToken,
        ),
        rsApiCall(
          '/rsConfig/getCumulativeTrafficByService',
          authToken: authToken,
        ),
        rsApiCall(
          '/rsServiceControl/getOwnServices',
          authToken: authToken,
        ),
      ]);
      final now = DateTime.now();
      final rawRates = responses[0]['rates'];
      if (rawRates is! Map) throw Exception('Traffic data is unavailable');
      final serviceTraffic = _parseServiceTraffic(
        responses[1]['stats'],
        _parseServiceNames(responses[2]),
        _previousTotals,
        _previousTime == null
            ? null
            : now.difference(_previousTime!).inMilliseconds / 1000,
      );

      if (!mounted) return;
      setState(() {
        _downloadRate = _number(rawRates['mRateIn'] ?? rawRates['rateIn']);
        _uploadRate = _number(rawRates['mRateOut'] ?? rawRates['rateOut']);
        _downloadedBytes = _number(rawRates['mTotalIn'] ?? rawRates['totalIn']);
        _uploadedBytes = _number(rawRates['mTotalOut'] ?? rawRates['totalOut']);
        _serviceTraffic = serviceTraffic;
        _previousTotals = {
          for (final service in serviceTraffic)
            service.id: (service.receivedBytes, service.sentBytes),
        };
        _previousTime = now;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      _requestInProgress = false;
    }
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    if (value is Map) {
      return _number(value['xuint64'] ?? value['xint64'] ?? value['xstr64']);
    }
    return 0;
  }

  static List<MapEntry<Object?, Object?>> _mapEntries(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((entry) {
        return MapEntry(entry['key'], entry['value']);
      }).toList();
    }
    if (value is Map) return value.entries.toList();
    return const [];
  }

  static Map<int, String> _parseServiceNames(Map<String, dynamic> response) {
    final info = response['info'];
    if (info is! Map) return const {};
    final result = <int, String>{};
    for (final entry in _mapEntries(info['mServiceList'])) {
      if (entry.value is! Map) continue;
      final service = entry.value! as Map;
      final fullType = _number(service['mServiceType']).toInt();
      final serviceId = (fullType >> 8) & 0xffff;
      final name = service['mServiceName']?.toString().trim();
      if (name != null && name.isNotEmpty) result[serviceId] = name;
    }
    return result;
  }

  /// The traffic of each service: its totals, and its speeds in kB/s since
  /// [previous], taken [seconds] ago (no speed without a previous refresh).
  static List<_ServiceTraffic> _parseServiceTraffic(
    Object? rawStats,
    Map<int, String> serviceNames,
    Map<int, (double, double)> previous,
    double? seconds,
  ) {
    final result = <_ServiceTraffic>[];
    for (final entry in _mapEntries(rawStats)) {
      if (entry.value is! Map) continue;
      final stats = entry.value! as Map;
      final serviceId = _number(entry.key).toInt();
      final received = _number(stats['bytesIn']);
      final sent = _number(stats['bytesOut']);
      if (received <= 0 && sent <= 0) continue;
      double? rate(double now, double? before) =>
          seconds == null || seconds <= 0 || before == null
              ? null
              : ((now - before) / 1024 / seconds).clamp(0, double.infinity);
      final last = previous[serviceId];
      result.add(
        _ServiceTraffic(
          id: serviceId,
          name: _friendlyServiceNames[serviceId] ??
              serviceNames[serviceId] ??
              'Service 0x${serviceId.toRadixString(16).padLeft(4, '0')}',
          receivedBytes: received,
          sentBytes: sent,
          receivedRate:
              rate(received, last?.$1 ?? (seconds == null ? null : 0)),
          sentRate: rate(sent, last?.$2 ?? (seconds == null ? null : 0)),
        ),
      );
    }
    return result;
  }

  List<_ServiceTraffic> get _sortedServices {
    double key(_ServiceTraffic t) => switch (_sortBy) {
          _Column.receivedRate => t.receivedRate ?? -1,
          _Column.sentRate => t.sentRate ?? -1,
          _Column.received => t.receivedBytes,
          _Column.sent => t.sentBytes,
        };
    return [..._serviceTraffic]..sort((a, b) => key(b).compareTo(key(a)));
  }

  // Speeds and amounts are measures: always two decimals, zero included.

  static String _formatRate(double kiloBytesPerSecond) {
    if (kiloBytesPerSecond >= 1024) {
      return '${(kiloBytesPerSecond / 1024).toStringAsFixed(2)} MB/s';
    }
    return '${kiloBytesPerSecond.toStringAsFixed(2)} kB/s';
  }

  static String _formatBytes(double bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var value = bytes;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 ? 0 : 2;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  /// A speed in the table: kB/s without the unit, '–' when not known yet.
  static String _formatTableRate(double? kiloBytesPerSecond) =>
      kiloBytesPerSecond?.toStringAsFixed(2) ?? '–';

  /// An amount in the table: MB without the unit, so that a column keeps
  /// one unit.
  static String _formatTableMegabytes(double bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        shadowColor: Colors.transparent,
        title: Text(
          'Statistics',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 14.5,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _requestInProgress ? null : _refresh,
            tooltip: 'Refresh statistics',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Down to above the system navigation bar.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.error_outline_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  title: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    context,
                    icon: Icons.arrow_downward_rounded,
                    color: Colors.green,
                    label: 'Received',
                    rate: _formatRate(_downloadRate),
                    total: _formatBytes(_downloadedBytes),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    context,
                    icon: Icons.arrow_upward_rounded,
                    color: Colors.blue,
                    label: 'Sent',
                    rate: _formatRate(_uploadRate),
                    total: _formatBytes(_uploadedBytes),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('By service', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _serviceTable(context),
            const SizedBox(height: 12),
            Text(
              'Speeds over the last ${_refreshPeriod.inSeconds} seconds, in '
              'kB/s; totals in MB since RetroShare started on this phone. '
              'Tap a column to sort by it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceTable(BuildContext context) {
    final theme = Theme.of(context);
    if (_serviceTraffic.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No per-service traffic has been recorded yet.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final small = theme.textTheme.bodySmall;
    final dim = theme.colorScheme.onSurfaceVariant;

    // A figure column: right-aligned, on one line, made smaller rather than
    // wrapped when the text is large, and apart from its left neighbour.
    Widget figure(Widget child) => Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: child,
            ),
          ),
        );

    Widget header(String text, _Column column, Color color) {
      final selected = _sortBy == column;
      return figure(
        InkWell(
          onTap: () => setState(() => _sortBy = column),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              selected ? '$text ▾' : text,
              maxLines: 1,
              style: small?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    Widget cell(String text) => figure(
          Text(
            text,
            maxLines: 1,
            style: small?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Text('Service', style: small?.copyWith(color: dim)),
                ),
                header('↓ kB/s', _Column.receivedRate, Colors.green),
                header('↑ kB/s', _Column.sentRate, Colors.blue),
                header('↓ MB', _Column.received, Colors.green),
                header('↑ MB', _Column.sent, Colors.blue),
              ],
            ),
            const Divider(height: 1),
            for (final traffic in _sortedServices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Text(
                        traffic.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    cell(_formatTableRate(traffic.receivedRate)),
                    cell(_formatTableRate(traffic.sentRate)),
                    cell(_formatTableMegabytes(traffic.receivedBytes)),
                    cell(_formatTableMegabytes(traffic.sentBytes)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String rate,
    required String total,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withAlpha(35),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(height: 10),
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                rate,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$total in all',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTraffic {
  const _ServiceTraffic({
    required this.id,
    required this.name,
    required this.receivedBytes,
    required this.sentBytes,
    required this.receivedRate,
    required this.sentRate,
  });

  final int id;
  final String name;
  final double receivedBytes;
  final double sentBytes;

  /// kB/s since the previous refresh; null on the first one.
  final double? receivedRate;
  final double? sentRate;
}
