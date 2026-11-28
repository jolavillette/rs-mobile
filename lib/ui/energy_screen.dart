import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One line of counters written by the service process (EnergyLog.kt).
class _Sample {
  _Sample(List<String> f)
      : wallMs = int.parse(f[0]),
        elapsedMs = int.parse(f[1]),
        uptimeMs = int.parse(f[2]),
        pid = int.parse(f[3]),
        cpuMs = int.parse(f[4]),
        // f[5] to f[9], not shown: the traffic on every interface, the
        // loopback between the screens and the core included, and the
        // network in use; the counters at the end of the line are what went
        // over the air.
        level = int.parse(f[10]),
        chargeUah = int.parse(f[11]),
        plugged = f[12] == '1',
        quiet = f[13] == '1',
        heldAwakeMs = int.parse(f[14]),
        keepAlives = int.parse(f[15]),
        incomingWakes = int.parse(f[16]),
        appMah = double.parse(f[17]),
        wifiBytes = _optional(f, 18),
        wifiPackets = _optional(f, 19),
        mobileBytes = _optional(f, 20),
        mobilePackets = _optional(f, 21);

  static int _optional(List<String> f, int i) =>
      f.length > i ? int.parse(f[i]) : -1;

  final int wallMs;
  final int elapsedMs;
  final int uptimeMs;
  final int pid;
  final int cpuMs;
  final int level;
  final int chargeUah;
  final bool plugged;

  /// The phone sleeps between keep-alives from this line on.
  final bool quiet;
  final int heldAwakeMs;
  final int keepAlives;
  final int incomingWakes;

  /// What Android charges to the application since its statistics were
  /// reset, or negative when this line does not carry it.
  final double appMah;

  /// Over Wi-Fi and over the mobile network, both ways, since the phone
  /// started, as Android's network statistics count them; negative when the
  /// line does not carry them (older lines, or Android could not tell).
  final int wifiBytes;
  final int wifiPackets;
  final int mobileBytes;
  final int mobilePackets;

  static List<_Sample> parse(String log) {
    final samples = <_Sample>[];
    for (final line in log.split('\n')) {
      final fields = line.trim().split(';');
      if (fields.length < 18) continue;
      try {
        samples.add(_Sample(fields));
      } on FormatException {
        // A line cut short by a stop of the process.
      }
    }
    return samples;
  }
}

/// The sums over the lines of one period.
class _Period {
  _Period(this.title, List<_Sample> samples) {
    if (samples.isEmpty) return;
    start = samples.first.wallMs;
    end = samples.last.wallMs;
    _Sample? power;
    for (var i = 0; i < samples.length; i++) {
      final b = samples[i];
      if (b.appMah >= 0) {
        // Android resets its statistics at a full charge: a lower figure
        // starts a new count.
        if (power != null && b.appMah >= power.appMah) {
          appMah += b.appMah - power.appMah;
          powerMs += b.wallMs - power.wallMs;
        }
        power = b;
      }
      if (i == 0) continue;
      final a = samples[i - 1];
      final ms = b.elapsedMs - a.elapsedMs;
      // The clocks and the system's counters restart with the phone.
      if (ms <= 0) continue;
      coveredMs += ms;
      phoneAwakeMs += b.uptimeMs - a.uptimeMs;
      if (a.quiet) quietMs += ms;
      // The process counters restart with the service.
      if (a.pid == b.pid && b.cpuMs >= a.cpuMs) {
        processMs += ms;
        cpuMs += b.cpuMs - a.cpuMs;
        heldAwakeMs += b.heldAwakeMs - a.heldAwakeMs;
        keepAlives += b.keepAlives - a.keepAlives;
        incomingWakes += b.incomingWakes - a.incomingWakes;
      }
      // The network counters restart with the phone, like the clocks.
      if (a.wifiBytes >= 0 &&
          b.wifiBytes >= a.wifiBytes &&
          b.wifiPackets >= a.wifiPackets) {
        wifiMs += ms;
        wifiBytes += b.wifiBytes - a.wifiBytes;
        wifiPackets += b.wifiPackets - a.wifiPackets;
      }
      if (a.mobileBytes >= 0 &&
          b.mobileBytes >= a.mobileBytes &&
          b.mobilePackets >= a.mobilePackets) {
        mobileMs += ms;
        mobileBytes += b.mobileBytes - a.mobileBytes;
        mobilePackets += b.mobilePackets - a.mobilePackets;
      }
      if (!a.plugged && !b.plugged && a.chargeUah > 0 && b.chargeUah > 0) {
        batteryMs += ms;
        usedUah += a.chargeUah - b.chargeUah;
        levelLost += a.level - b.level;
      }
    }
  }

  final String title;
  int start = 0;
  int end = 0;
  int coveredMs = 0;
  int quietMs = 0;
  int phoneAwakeMs = 0;
  int processMs = 0;
  int cpuMs = 0;
  int heldAwakeMs = 0;
  int keepAlives = 0;
  int incomingWakes = 0;
  int wifiMs = 0;
  int wifiPackets = 0;
  int wifiBytes = 0;
  int mobileMs = 0;
  int mobilePackets = 0;
  int mobileBytes = 0;
  int batteryMs = 0;
  int usedUah = 0;
  int levelLost = 0;
  int powerMs = 0;
  double appMah = 0;

  double get hours => coveredMs / 3600000;
  double get processHours => processMs / 3600000;
  double get batteryHours => batteryMs / 3600000;
  double get powerHours => powerMs / 3600000;
  double get wifiHours => wifiMs / 3600000;
  double get mobileHours => mobileMs / 3600000;
}

/// The Battery tab of Statistics. What RetroShare does to the battery: its
/// own activity, the battery of the whole phone and, when Android lets the
/// application read it, what Android charges to it; over the last time
/// in background, 24 hours and 7 days. Pulled down, it measures again.
class EnergyView extends StatefulWidget {
  const EnergyView({super.key});

  @override
  State<EnergyView> createState() => _EnergyViewState();
}

class _EnergyViewState extends State<EnergyView> {
  static const _channel = MethodChannel('cc.retroshare.retroshare/energy');

  bool _loading = true;
  bool _available = true;
  bool _powerPermissions = false;
  List<_Period> _periods = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _powerPermissions =
          await _channel.invokeMethod<bool>('powerPermissions') ?? false;
      // The service writes a fresh line; reading the system's battery
      // statistics for it takes a few seconds when permitted.
      final asked = await _channel.invokeMethod<bool>('sample') ?? false;
      if (asked) {
        await Future<void>.delayed(
          Duration(seconds: _powerPermissions ? 5 : 1),
        );
      }
      final log = await _channel.invokeMethod<String>('log') ?? '';
      _periods = _split(_Sample.parse(log));
    } on MissingPluginException {
      _available = false;
    } on PlatformException catch (error) {
      debugPrint('Energy: $error');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<_Period> _split(List<_Sample> samples) {
    if (samples.length < 2) return const [];
    final now = samples.last.wallMs;
    List<_Sample> since(int ms) =>
        samples.where((s) => s.wallMs >= now - ms).toList();

    // The last stretch in background: from the last line that begins one to
    // the line that ends it.
    var quietStart = -1;
    for (var i = samples.length - 1; i >= 0; i--) {
      if (samples[i].quiet && (i == 0 || !samples[i - 1].quiet)) {
        quietStart = i;
        break;
      }
    }
    var background = const <_Sample>[];
    if (quietStart >= 0) {
      var quietEnd = samples.length - 1;
      for (var i = quietStart + 1; i < samples.length; i++) {
        if (!samples[i].quiet) {
          quietEnd = i;
          break;
        }
      }
      background = samples.sublist(quietStart, quietEnd + 1);
    }
    return [
      _Period('Last time in background', background),
      _Period('Last 24 hours', since(24 * 3600 * 1000)),
      _Period('Last 7 days', since(7 * 24 * 3600 * 1000)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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
          if (!_available)
            const Text('Not measured on this platform.')
          else if (!_loading && _periods.isEmpty)
            const Text(
              'Nothing measured yet. The figures build up while RetroShare '
              'runs: come back after it spent some time in the background.',
            )
          else
            for (final period in _periods) _periodCard(period),
        ],
      ),
    );
  }

  Widget _periodCard(_Period p) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    void header(String text) => rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(text, style: theme.textTheme.labelLarge),
          ),
        );
    void row(String label, String value) => rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                Text(value, textAlign: TextAlign.right),
              ],
            ),
          ),
        );

    if (p.coveredMs <= 0) {
      rows.add(const Text('Nothing measured.'));
    } else {
      row('Measured', '${_clock(p.start)} to ${_clock(p.end)}');
      row('Duration', _duration(p.coveredMs));
      row('Of which in background', _percent(p.quietMs, p.coveredMs));

      header('RetroShare');
      if (p.processMs > 0) {
        row('Processor, average', _percent(p.cpuMs, p.processMs));
        row(
          'Keeps the phone awake',
          '${_decimal(p.heldAwakeMs / 1000 / p.processHours)} s/h',
        );
        row(
          'Wake-ups for a keep-alive',
          '${_decimal(p.keepAlives / p.processHours)} /h',
        );
        row(
          'Wake-ups for an arrival',
          '${_decimal(p.incomingWakes / p.processHours)} /h',
        );
      }
      row('Wi-Fi', _traffic(p.wifiPackets, p.wifiBytes, p.wifiHours));
      row(
        'Mobile network',
        _traffic(p.mobilePackets, p.mobileBytes, p.mobileHours),
      );

      header('Battery of the phone, every application');
      row('Phone awake', _percent(p.phoneAwakeMs, p.coveredMs));
      if (p.batteryMs <= 0) {
        row('On battery', 'no, on charge');
      } else {
        final mah = p.usedUah / 1000;
        row('On battery', _duration(p.batteryMs));
        row('Used', '${_decimal(mah)} mAh, ${p.levelLost} %');
        row('Average current', '${_decimal(mah / p.batteryHours)} mA');
        row(
          'At this rate',
          '${_decimal(p.levelLost / p.batteryHours * 24)} % per day',
        );
      }

      // Android shows what it charges to each application only to an
      // application allowed to read it; without that, the section is left out.
      if (_powerPermissions) {
        header('RetroShare, as Android counts it');
        if (p.powerMs <= 0) {
          row('Used', 'not measured yet');
        } else {
          row('Counted over', _duration(p.powerMs));
          row('Used', '${_decimal(p.appMah)} mAh');
          row('Average', '${_decimal(p.appMah / p.powerHours)} mAh/h');
        }
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(128),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// Per hour of the time the counters cover, which is the whole period
  /// once the lines carry them.
  static String _traffic(int packets, int bytes, double hours) => hours > 0
      ? '${_decimal(packets / hours)} packets/h, '
          '${_decimal(bytes / 1000 / hours)} kB/h'
      : '-';

  static String _decimal(double value) =>
      value.isFinite ? value.toStringAsFixed(2) : '-';

  static String _percent(int part, int whole) =>
      whole > 0 ? '${_decimal(part * 100 / whole)} %' : '-';

  static String _duration(int ms) {
    final minutes = ms ~/ 60000;
    final days = minutes ~/ 1440;
    final hours = minutes % 1440 ~/ 60;
    final rest = minutes % 60;
    if (days > 0) return '$days d $hours h';
    if (hours > 0) return '$hours h ${rest.toString().padLeft(2, '0')}';
    return '$rest min';
  }

  static String _clock(int wallMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(wallMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
