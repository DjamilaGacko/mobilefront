import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/test_selection.dart';
import '../services/device_info_service.dart';
import '../services/location_service.dart';
import '../services/network_info_service.dart';
import '../services/speed_test_api_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';
import 'score_screen.dart';

/// Écran de test (complet / débit / navigation / streaming).
/// La jauge mesure le débit ; pendant le streaming la vidéo s'affiche, et
/// pendant la navigation les pages web s'affichent réellement (WebView).
class FullTestScreen extends StatefulWidget {
  final TestSelection selection;
  final String title;
  final String route;
  final String launchLabel; // texte au centre de la jauge
  const FullTestScreen({
    super.key,
    this.selection = const TestSelection.all(),
    this.title = 'Test complet',
    this.route = '/full',
    this.launchLabel = 'LANCER LE\nTEST COMPLET',
  });

  @override
  State<FullTestScreen> createState() => _FullTestScreenState();
}

enum _Stage { idle, running }

class _FullTestScreenState extends State<FullTestScreen>
    with SingleTickerProviderStateMixin {
  final _api = SpeedTestApiService();
  final _location = LocationService();
  final _device = DeviceInfoService();
  final _net = NetworkInfoService();

  late final AnimationController _arcCtrl;

  _Stage _stage = _Stage.idle;
  String _phaseLabel = '';
  String _metricUnit = 'Mb/s';
  double _coreValue = 0;
  double _arcTarget = 0;
  double _arcFrom = 0;

  double get _displayFrac =>
      _arcFrom + (_arcTarget - _arcFrom) * _arcCtrl.value;

  double _download = 0, _upload = 0, _ping = 0;

  String _techno = '—';
  String _operator = '—';
  String _network = '—';

  VideoPlayerController? _video; // test de streaming (vidéo visible)
  WebViewController? _web; // test de navigation (pages visibles)

  @override
  void initState() {
    super.initState();
    _arcCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() => setState(() {}));
    _loadContext();
  }

  @override
  void dispose() {
    _arcCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final techno = await _net.getNetworkType();
    final ssid = await _net.getWiFiSSID();
    final loc = await _location.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _techno = techno ?? '—';
      _operator = loc?.operator.isNotEmpty == true ? loc!.operator : '—';
      _network = (ssid != null && ssid.isNotEmpty)
          ? ssid
          : (loc?.city.isNotEmpty == true ? loc!.city : '—');
    });
  }

  void _animateArcTo(double fraction) {
    _arcFrom = _displayFrac;
    _arcTarget = fraction.clamp(0.0, 1.0);
    _arcCtrl.forward(from: 0);
  }

  double _fracFor(double value, double scaleMax) {
    if (value <= 0) return 0;
    if (value <= scaleMax) return value / scaleMax;
    return 1.0;
  }

  Future<void> _start() async {
    if (_stage == _Stage.running) return;
    setState(() {
      _stage = _Stage.running;
      _phaseLabel = 'Initialisation…';
      _download = _upload = _ping = 0;
      _coreValue = 0;
      _arcTarget = 0;
    });

    try {
      final gps = await _location.requestGpsPosition();
      final ipLoc = await _location.getCurrentLocation();
      final techno = await _net.getNetworkType();
      final ssid = await _net.getWiFiSSID();
      final deviceModel = await _device.getDeviceModel();
      final osVersion = await _device.getOSVersion();
      final battery = await _device.getBatteryLevel();

      if (mounted) {
        setState(() {
          _techno = techno ?? _techno;
          _operator =
              ipLoc?.operator.isNotEmpty == true ? ipLoc!.operator : _operator;
          _network = (ssid != null && ssid.isNotEmpty)
              ? ssid
              : (ipLoc?.city.isNotEmpty == true ? ipLoc!.city : _network);
        });
      }

      final result = await _api.runSpeedTest(
        latitude: gps?.latitude ?? ipLoc?.latitude,
        longitude: gps?.longitude ?? ipLoc?.longitude,
        location: ipLoc != null ? '${ipLoc.city}, ${ipLoc.countryName}' : null,
        networkType: techno,
        operator: ipLoc?.operator,
        deviceModel: deviceModel,
        osVersion: osVersion,
        batteryLevel: battery,
        selection: widget.selection,
        onProgress: _onProgress,
        onStreamingController: (c) {
          if (mounted) setState(() => _video = c);
        },
        onBrowsingController: (c) {
          if (mounted) setState(() => _web = c);
        },
        // On affiche le bilan AVANT le QoE : pas d'envoi automatique ici.
        autoUpload: false,
      );

      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _phaseLabel = '';
        _coreValue = _download;
        _metricUnit = 'Mb/s';
      });
      _animateArcTo(_fracFor(_download, 100));

      // Bilan d'abord ; le QoE et l'enregistrement se font depuis l'écran Score.
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScoreScreen(result: result)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _phaseLabel = 'Échec du test. Vérifiez la connexion.';
      });
    }
  }

  void _onProgress(SpeedTestProgress p) {
    if (!mounted) return;
    setState(() {
      _phaseLabel = p.message;
      if (p.downloadSpeed != null) _download = p.downloadSpeed!;
      if (p.uploadSpeed != null) _upload = p.uploadSpeed!;
      if (p.ping != null) _ping = p.ping!;

      switch (p.phase) {
        case SpeedTestPhase.download:
          _metricUnit = 'Mb/s';
          _coreValue = _download;
          _animateArcTo(_fracFor(_download, 100));
          break;
        case SpeedTestPhase.ping:
          _metricUnit = 'ms';
          _coreValue = _ping;
          _animateArcTo(_fracFor(_ping, 500));
          break;
        case SpeedTestPhase.upload:
          _metricUnit = 'Mb/s';
          _coreValue = _upload;
          _animateArcTo(_fracFor(_upload, 100));
          break;
        default:
          break;
      }
    });
  }

  bool get _showVideo => _video != null && _video!.value.isInitialized;
  bool get _showWeb => _web != null;

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: widget.title,
      route: widget.route,
      body: Container(
        decoration: const BoxDecoration(gradient: YeleColors.testGradient),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_stage == _Stage.running && _phaseLabel.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
                      child: Text(_phaseLabel.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              fontSize: 14)),
                    ),
                  ),
                _centerArea(),
                _serverBar(),
                _metrics(),
                _bottomInfo(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerArea() {
    if (_showVideo) return _videoCard();
    if (_showWeb) return _webCard();
    // Tests streaming / navigation : bouton START simple (façon nPerf),
    // pas de compteur de vitesse (qui n'a de sens que pour le débit).
    if (!widget.selection.speed) return _startButton();
    return _gauge();
  }

  Widget _startButton() {
    final running = _stage == _Stage.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: GestureDetector(
          onTap: running ? null : _start,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(0, -0.3),
                colors: [Color(0xFF3A4636), Color(0xFF1C2419)],
              ),
              border: Border.all(color: YeleColors.testBot, width: 6),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            alignment: Alignment.center,
            child: running
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(widget.launchLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.15)),
          ),
        ),
      ),
    );
  }

  Widget _videoCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 210,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
              if (_video!.value.isBuffering)
                const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
              _badge('● TEST STREAMING ${_video!.value.size.height.round()}p'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _webCard() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 360,
          width: double.infinity,
          child: Stack(
            children: [
              WebViewWidget(controller: _web!),
              _badge('● TEST NAVIGATION WEB'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _gauge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: SizedBox(
        width: 320,
        height: 320,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(320, 320),
              painter: _GaugePainter(_displayFrac),
            ),
            GestureDetector(
              onTap: _stage == _Stage.idle ? _start : null,
              child: Container(
                width: 165,
                height: 165,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(0, -0.3),
                    colors: [Color(0xFF3A4636), Color(0xFF1C2419)],
                  ),
                  border: Border.all(color: const Color(0xFF5B6B4D), width: 6),
                ),
                alignment: Alignment.center,
                child: _coreContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coreContent() {
    if (_stage == _Stage.idle) {
      return Text(widget.launchLabel,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.15));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_coreValue.toStringAsFixed(_metricUnit == 'ms' ? 0 : 2),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 34)),
        Text(_metricUnit,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _serverBar() {
    return Container(
      color: const Color(0xFFEEF1EE),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(width: 26, height: 20, color: const Color(0xFF5A6B3A)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('[BF] yele_serveur — Ouagadougou',
                style: TextStyle(color: Color(0xFF33402A), fontSize: 13)),
          ),
          const Text('🇧🇫', style: TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _metrics() {
    Widget cell(String label, double value, String unit, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Color(0xFFD7DDCF))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF33402A),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(height: 30, child: _miniBar(value, color)),
              const SizedBox(height: 4),
              Text(
                  value > 0
                      ? '${value.toStringAsFixed(unit == 'ms' ? 0 : 1)} $unit'
                      : '—',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.ink)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFEEF1EE),
      child: Row(
        children: [
          cell('▼ Download', _download, 'Mb/s', YeleColors.accent),
          cell('▲ Upload', _upload, 'Mb/s', YeleColors.good),
          cell('↔ Latence', _ping, 'ms', YeleColors.muted),
        ],
      ),
    );
  }

  Widget _miniBar(double value, Color color) {
    final frac = _fracFor(value, value > 100 ? value : 100);
    return Align(
      alignment: Alignment.bottomLeft,
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: value > 0 ? (0.25 + 0.75 * frac) : 0.06,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _bottomInfo() {
    Widget c(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: YeleColors.line)),
          ),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: YeleColors.field,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF2C3650), fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: YeleColors.panel,
        border: Border(top: BorderSide(color: YeleColors.primary, width: 2)),
      ),
      child: Row(
        children: [
          c('Technologie', _techno),
          c('Opérateur', _operator),
          c('Réseau', _network),
        ],
      ),
    );
  }
}

/// Peint l'arc de la jauge (270°, dégradé cyan→lime) et les graduations.
class _GaugePainter extends CustomPainter {
  final double fraction;
  _GaugePainter(this.fraction);

  static const double _startDeg = 135;
  static const double _sweepDeg = 270;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30;
    const stroke = 40.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startRad = _startDeg * math.pi / 180;
    final sweepRad = _sweepDeg * math.pi / 180;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0xFF2B3520).withValues(alpha: 0.55);
    canvas.drawArc(rect, startRad, sweepRad, false, track);

    final tick = Paint()
      ..color = const Color(0xFFC9D97F)
      ..strokeWidth = 2;
    for (int i = 0; i <= 60; i++) {
      final a = (_startDeg + i * (_sweepDeg / 60)) * math.pi / 180;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (radius - 22);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (radius - 12);
      canvas.drawLine(p1, p2, tick);
    }

    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [YeleColors.accent, YeleColors.testBot],
          transform: GradientRotation(_startDeg * math.pi / 180),
        ).createShader(rect);
      canvas.drawArc(rect, startRad, sweepRad * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}
