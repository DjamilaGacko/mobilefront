import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/speed_test_result.dart';
import '../services/account_service.dart';
import '../services/data_usage_service.dart';
import '../services/local_storage_service.dart';
import '../services/speed_test_api_service.dart';
import '../services/settings_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/barometer_card.dart';
import '../widgets/qoe_dialog.dart';
import '../widgets/streaming_table.dart';
import '../widgets/yele_scaffold.dart';

/// Écran "Score" — bilan d'un test, affiché AVANT le questionnaire QoE.
/// L'utilisateur consulte ses résultats, puis évalue la qualité ressentie ;
/// l'enregistrement local + envoi au serveur ont lieu à ce moment-là.
/// Choix « ne montrer que le mesurable » : note de qualité dérivée du débit,
/// pas de score en points arbitraire.
class ScoreScreen extends StatefulWidget {
  final SpeedTestResult result;
  const ScoreScreen({super.key, required this.result});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  final _api = SpeedTestApiService();
  final _storage = LocalStorageService();
  bool _saved = false;
  bool _qoeDone = false;

  SpeedTestResult get r => widget.result;

  bool get _speedDone => r.downloadSpeed > 0 || r.uploadSpeed > 0;

  Future<void> _finalize() async {
    if (_saved) return;
    _saved = true;
    try {
      // IMP-03 : la mesure appartient au compte connecté, s'il y en a un.
      r.accountId = AccountService.instance.accountId;
      await _storage.saveResult(r);
      r.isUploaded = await _api.uploadTestResult(r);
      // L'envoi a remplacé l'identifiant provisoire par celui du serveur :
      // sans réenregistrement, il serait perdu, et la mesure reviendrait en
      // double lors d'une synchronisation du compte.
      await r.save();
      // IMP-09 : la mesure a consommé des données, le seuil mensuel est
      // peut-être franchi.
      DataUsageService().checkLimit();
    } catch (_) {
      // Échec d'enregistrement non bloquant pour l'affichage.
    }
  }

  Future<void> _openQoe() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => QoeDialog(
        onCompleted: (rating, usage, satisfaction) {
          r.qoeRating = rating;
          r.qoeUsage = usage;
          r.qoeSatisfaction = satisfaction;
        },
      ),
    );
    await _finalize();
    if (!mounted) return;
    setState(() => _qoeDone = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Résultat enregistré ✓')),
    );
  }

  // ── Partage du résultat en image (IMP-10) ──

  final _shotKey = GlobalKey();
  bool _sharing = false;

  /// Capture le bilan en PNG puis ouvre le menu de partage du système
  /// (WhatsApp, e-mail, galerie…).
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      // Résolution de l'écran, plafonnée : au-delà de 3, l'image pèse
      // inutilement lourd pour une messagerie.
      final ratio = MediaQuery.of(context).devicePixelRatio.clamp(2.0, 3.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/yele_${DateFormat('yyyyMMdd_HHmmss').format(r.timestamp)}.png');
      await file.writeAsBytes(png.buffer.asUint8List());

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _shareText,
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de générer l'image.")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Texte joint à l'image, pour les applications qui n'affichent pas
  /// l'aperçu.
  String get _shareText {
    final parts = <String>[
      if (_speedDone)
        '▼ ${Settings.speedUnit.format(r.downloadSpeed)} · '
            '▲ ${Settings.speedUnit.format(r.uploadSpeed)} · '
            '${r.ping.toStringAsFixed(0)} ms',
      if (r.operator != null) r.operator!,
    ];
    return 'Mon test Yélé — ${parts.join(' — ')}';
  }

  /// En-tête de l'image : sans lui, une capture partagée ne dirait ni quand ni
  /// où la mesure a été faite.
  Widget _shareHeader() {
    final place = r.placeLabel;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Image.asset('assets/yele-logo.png', height: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(DateFormat('dd/MM/yyyy · HH:mm').format(r.timestamp),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: YeleColors.ink)),
                if ((place ?? '').isNotEmpty)
                  Text(place!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: YeleColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Qualité dérivée du débit descendant (seuils documentés) ──
  ({String label, Color color}) get _quality {
    final d = r.downloadSpeed;
    if (d >= 50) return (label: 'Excellent', color: YeleColors.good);
    if (d >= 20) return (label: 'Très bon', color: YeleColors.testBot);
    if (d >= 10) return (label: 'Bon', color: YeleColors.warn);
    if (d >= 4) return (label: 'Moyen', color: YeleColors.g4);
    return (label: 'Faible', color: YeleColors.danger);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _finalize(),
      child: YeleScaffold(
        title: 'Résultat du test',
        route: '/full',
        body: Container(
          decoration: BoxDecoration(gradient: Settings.testStyle.gradient),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // IMP-10 : tout le bilan, en-tête compris, est capturé tel
                  // qu'affiché pour l'image partagée ; les boutons restent
                  // hors de la capture.
                  RepaintBoundary(
                    key: _shotKey,
                    child: Container(
                      decoration:
                          BoxDecoration(gradient: Settings.testStyle.gradient),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          _shareHeader(),
                          // N'affiche que les sections du/des test(s) réellement faits.
                          if (_speedDone) ...[
                            _metrics(),
                            _qualityBand(),
                            // IMP-11 : position parmi les autres mesures.
                            BarometerCard(result: r),
                          ],
                          // Mesures radio (ISS-01) : indépendantes du speedtest, elles
                          // valent aussi pour un test de streaming ou de navigation.
                          _radioBand(r),
                          // Affiché aussi en cas d'échec, pour en montrer la raison.
                          if (r.hasStreamingTest || r.streamingError != null)
                            _streamingCard(),
                          if (r.hasBrowsingTest) _browsingCard(),
                          const SizedBox(height: 12),
                          _bottomInfo(),
                        ],
                      ),
                    ),
                  ),
                  _actions(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metrics() {
    Widget m(String label, String val, String unit, String sub) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2C3650),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(val,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: YeleColors.field,
                      height: 1.1)),
              Text(unit,
                  style: const TextStyle(fontSize: 13, color: YeleColors.field)),
              const SizedBox(height: 3),
              Text(sub,
                  style: const TextStyle(fontSize: 11, color: YeleColors.muted)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: YeleColors.panel,
      child: Row(
        children: [
          m('▼ Download', Settings.speedUnit.value(r.downloadSpeed),
              Settings.speedUnit.label, ''),
          m('▲ Upload', Settings.speedUnit.value(r.uploadSpeed),
              Settings.speedUnit.label, ''),
          m('↔ Latence', r.ping.toStringAsFixed(0), 'ms',
              'Gigue : ${r.jitter.toStringAsFixed(0)} ms'),
        ],
      ),
    );
  }

  /// Bandeau des mesures radio (ISS-01).
  ///
  /// Deux conditions, et la seconde est essentielle. La radio du téléphone
  /// reste accrochée à sa cellule 4G/5G même pendant un test passé en Wi-Fi :
  /// RSRP et RSRQ sont alors bien renseignés, mais ils décrivent le réseau
  /// mobile, PAS ce que le test a mesuré. Les afficher reviendrait à présenter
  /// des informations mobiles comme celles du test — ce qu'interdit ISS-03.
  Widget _radioBand(SpeedTestResult r) {
    if (!r.hasRadioMetrics || !r.cellularCarriedTest) {
      return const SizedBox.shrink();
    }

    Widget cell(String label, String value, String hint) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: YeleColors.muted)),
              const SizedBox(height: 3),
              Text(value,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: YeleColors.ink)),
              Text(hint,
                  style: const TextStyle(fontSize: 10.5, color: YeleColors.muted)),
            ],
          ),
        );

    return Container(
      color: YeleColors.panel2,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (r.rsrp != null)
            cell('RSRP', '${r.rsrp} dBm', 'Puissance du signal'),
          if (r.rsrq != null)
            cell('RSRQ', '${r.rsrq} dB', 'Qualité du signal'),
        ],
      ),
    );
  }

  Widget _qualityBand() {
    final q = _quality;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2419), Color(0xFF10160D)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(0, -0.2),
              colors: [Color(0xFF1C2419), Color(0xFF0C1108)],
            ),
            border: Border.all(color: q.color, width: 7),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('QUALITÉ',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(q.label,
                  style: TextStyle(
                      color: q.color, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(Settings.speedUnit.format(r.downloadSpeed),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // Carte de résultat d'un test, avec en-tête coloré et lignes clé/valeur.
  Widget _resultCard(String icon, String title, Color color, double score,
      List<({String k, String v})> lines) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${score.toStringAsFixed(0)}/100',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.k,
                            style: const TextStyle(
                                color: YeleColors.muted, fontSize: 13)),
                        Text(l.v,
                            style: const TextStyle(
                                color: YeleColors.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Streaming : tableau par qualité (720p/1080p/2160p), façon nPerf.
  /// Repli sur l'ancienne carte pour les résultats enregistrés avant ce test.
  Widget _streamingCard() {
    final rows = r.streamingQualities;
    final error = r.streamingError;
    if (rows.isEmpty && error != null) return _streamingError(error);
    if (rows.isEmpty) {
      return _resultCard('🎬', 'Streaming vidéo', YeleColors.g5,
          r.streamingScore ?? 0, [
        (k: 'Résolution max soutenue', v: r.streamingMaxResolution ?? '—'),
        (k: 'Démarrage', v: '${r.streamingStartupMs ?? 0} ms'),
        (k: 'Interruptions', v: '${r.streamingRebufferCount ?? 0}'),
      ]);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(
            children: [
              const Text('🎬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('Streaming vidéo',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(r.streamingScore ?? 0).toStringAsFixed(0)}/100',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        StreamingTable(qualities: rows),
        if (error != null) _streamingError(error),
      ],
    );
  }

  /// Explique un test de streaming sans mesure : sans ce message, un échec
  /// technique ressemblerait à un réseau simplement trop faible.
  Widget _streamingError(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: YeleColors.warn, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: YeleColors.warn, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 13, color: YeleColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _browsingCard() {
    return _resultCard('🌐', 'Navigation web', YeleColors.primary,
        r.browsingScore ?? 0, [
      (
        k: 'Temps de chargement moyen',
        v: '${((r.browsingAvgLoadMs ?? 0) / 1000).toStringAsFixed(1)} s'
      ),
      (
        k: 'Taux de réussite',
        v: '${((r.browsingSuccessRate ?? 0) * 100).toStringAsFixed(0)} %'
      ),
      (k: 'Pages testées', v: '${r.browsingPagesTested ?? 0}'),
    ]);
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
          c('Connexion', r.networkType ?? '—'),
          c('FAI', r.operator ?? '—'),
          c('Réseau mobile', _mobileLabel),
          // IMP-01 : volume total échangé par la mesure.
          c('Données', r.dataUsedLabel ?? '—'),
        ],
      ),
    );
  }

  /// « 4G · Orange », « 4G », ou « — » selon les mesures disponibles.
  String get _mobileLabel {
    final tech = r.cellularTech;
    final sim = r.simOperator;
    if ((tech == null || tech.isEmpty) && (sim == null || sim.isEmpty)) {
      return '—';
    }
    if (sim != null && sim.isNotEmpty && tech != null && tech.isNotEmpty) {
      return '$tech · $sim';
    }
    return (tech != null && tech.isNotEmpty) ? tech : sim!;
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _qoeDone ? null : _openQoe,
              icon: Icon(_qoeDone ? Icons.check_circle : Icons.rate_review),
              label: Text(_qoeDone
                  ? 'Évaluation enregistrée'
                  : 'Évaluer la qualité (QoE)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YeleColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YeleColors.good,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.share),
              label: const Text('Partager le résultat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: YeleColors.ink,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _finalize();
                    if (mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recommencer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YeleColors.ink,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _finalize();
                    if (mounted) {
                      Navigator.of(context).pushReplacementNamed('/history');
                    }
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YeleColors.ink,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
