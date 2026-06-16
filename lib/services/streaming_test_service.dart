import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'package:video_player/video_player.dart';

import '../constants/config.dart';

/// Résultat du test de streaming vidéo.
class StreamingTestResult {
  final int startupMs; // délai avant le premier frame affiché
  final int rebufferCount; // nombre de gels de l'image
  final double rebufferRatio; // part du temps passée en mise en tampon (0-1)
  final String maxResolution; // plus haut palier soutenu (ex: 720p)
  final double score; // score synthétique 0-100

  const StreamingTestResult({
    required this.startupMs,
    required this.rebufferCount,
    required this.rebufferRatio,
    required this.maxResolution,
    required this.score,
  });

  @override
  String toString() =>
      'Streaming: $maxResolution, démarrage ${startupMs}ms, '
      '$rebufferCount interruptions (${(rebufferRatio * 100).toStringAsFixed(1)}%), '
      'score ${score.toStringAsFixed(1)}';
}

typedef StreamingProgressCallback = void Function(
    double progress, String message);

typedef StreamingControllerCallback = void Function(
    VideoPlayerController? controller);

class _Variant {
  final int height;
  final String url;
  const _Variant(this.height, this.url);
}

class _LevelResult {
  final bool ok; // palier soutenu sans coupure excessive
  final bool started; // la lecture a démarré
  final int startupMs;
  final int rebufferCount;
  final double stallSec;
  final double playedSec;
  const _LevelResult({
    required this.ok,
    required this.started,
    required this.startupMs,
    required this.rebufferCount,
    required this.stallSec,
    required this.playedSec,
  });
}

/// Test de streaming **par paliers progressifs**, à la manière de nPerf.
///
/// On lit le manifeste HLS maître pour connaître les renditions réelles du
/// flux (240p, 360p, 480p, 720p, 1080p…), puis on lit **chaque palier du plus
/// bas au plus haut** en forçant sa qualité (lecture de la sous-playlist du
/// palier, sans adaptation automatique). À chaque palier on mesure le temps de
/// démarrage et les coupures ; dès qu'un palier ne tient pas (timeout ou trop
/// de mise en tampon), on s'arrête : la résolution max = le plus haut palier
/// réellement soutenu par le réseau.
class StreamingTestService {
  final logger = Logger();
  final Dio _dio = Dio();

  // Un palier est "soutenu" si la part de mise en tampon reste sous ce seuil.
  static const double _maxStallRatio = 0.35;
  // Durée de lecture mesurée par palier.
  static const int _perLevelSec = 6;

  Future<StreamingTestResult> runTest({
    int playDurationSec = STREAMING_VIDEO_DURATION_SEC,
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
  }) async {
    // Web : pas de HLS natif → mesure simple sur le MP4 de repli.
    if (kIsWeb) {
      return _runSingle(STREAMING_VIDEO_URL_WEB, onController, onProgress);
    }

    onProgress?.call(0.02, 'Analyse des qualités disponibles…');
    final variants = await _fetchVariants(STREAMING_VIDEO_URL);

    // Repli : si on n'a pas pu lister les renditions, mesure simple adaptative.
    if (variants.isEmpty) {
      return _runSingle(STREAMING_VIDEO_URL, onController, onProgress);
    }

    int bestHeight = 0;
    int firstStartupMs = -1;
    int totalRebuffers = 0;
    double totalStall = 0;
    double totalPlayed = 0;

    for (int i = 0; i < variants.length; i++) {
      final v = variants[i];
      onProgress?.call(
        (i + 0.1) / variants.length,
        'Test en ${v.height}p…',
      );

      final r = await _playLevel(v, onController, onProgress, i, variants.length);

      if (firstStartupMs < 0 && r.started) firstStartupMs = r.startupMs;
      totalRebuffers += r.rebufferCount;
      totalStall += r.stallSec;
      totalPlayed += r.playedSec;

      if (r.ok) {
        bestHeight = v.height;
      } else {
        // Ce palier ne tient pas : inutile de tester plus haut.
        logger.w('Streaming: palier ${v.height}p non soutenu, arrêt.');
        break;
      }
    }

    onController?.call(null);

    final measured = totalPlayed + totalStall;
    final rebufferRatio =
        measured > 0 ? (totalStall / measured).clamp(0.0, 1.0) : 0.0;
    final startupMs = firstStartupMs < 0 ? 0 : firstStartupMs;
    final score = _computeScore(
        bestHeight.toDouble(), startupMs, rebufferRatio, totalRebuffers);

    final result = StreamingTestResult(
      startupMs: startupMs,
      rebufferCount: totalRebuffers,
      rebufferRatio: double.parse(rebufferRatio.toStringAsFixed(3)),
      maxResolution: _resolutionLabel(bestHeight.toDouble()),
      score: double.parse(score.toStringAsFixed(1)),
    );
    logger.i('$result');
    return result;
  }

  /// Lit et parse le manifeste maître pour en extraire les renditions
  /// (hauteur + URL de sous-playlist), triées du plus bas au plus haut.
  Future<List<_Variant>> _fetchVariants(String masterUrl) async {
    try {
      final res = await _dio.get<String>(
        masterUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final body = res.data ?? '';
      final lines = body.split('\n');
      final base = masterUrl.substring(0, masterUrl.lastIndexOf('/') + 1);
      final byHeight = <int, String>{};

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          final m = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
          final height = m != null ? int.parse(m.group(1)!) : 0;
          // La ligne d'URI suit (première ligne non vide non commentée).
          for (int j = i + 1; j < lines.length; j++) {
            final uri = lines[j].trim();
            if (uri.isEmpty || uri.startsWith('#')) continue;
            final url = uri.startsWith('http') ? uri : '$base$uri';
            if (height > 0 && !byHeight.containsKey(height)) {
              byHeight[height] = url;
            }
            break;
          }
        }
      }

      final variants = byHeight.entries
          .map((e) => _Variant(e.key, e.value))
          .toList()
        ..sort((a, b) => a.height.compareTo(b.height));
      logger.i('Streaming: ${variants.length} paliers '
          '(${variants.map((v) => '${v.height}p').join(', ')})');
      return variants;
    } catch (e) {
      logger.w('Streaming: impossible de lister les renditions ($e)');
      return [];
    }
  }

  /// Joue un palier donné pendant [_perLevelSec] et mesure démarrage + coupures.
  Future<_LevelResult> _playLevel(
    _Variant v,
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
    int index,
    int total,
  ) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(v.url));
    int rebufferCount = 0;
    double stallSec = 0;
    bool started = false;
    final stallWatch = Stopwatch();

    void listener() {
      final val = controller.value;
      if (!started) return;
      if (val.isBuffering && !stallWatch.isRunning) {
        stallWatch.start();
        rebufferCount++;
      } else if (!val.isBuffering && stallWatch.isRunning) {
        stallWatch.stop();
        stallSec += stallWatch.elapsedMilliseconds / 1000;
        stallWatch.reset();
      }
    }

    final wall = Stopwatch()..start();
    try {
      controller.addListener(listener);
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.setVolume(0);
      onController?.call(controller);
      await controller.play();

      // Démarrage : la position commence à avancer.
      int startupMs = -1;
      while (wall.elapsed.inSeconds < 15) {
        if (controller.value.position > Duration.zero) {
          startupMs = wall.elapsedMilliseconds;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (startupMs < 0) {
        return const _LevelResult(
            ok: false,
            started: false,
            startupMs: 0,
            rebufferCount: 0,
            stallSec: 0,
            playedSec: 0);
      }
      started = true;

      final playStart = wall.elapsedMilliseconds;
      while ((wall.elapsedMilliseconds - playStart) / 1000 < _perLevelSec) {
        onProgress?.call(
          (index + 0.1 + 0.8 * ((wall.elapsedMilliseconds - playStart) / 1000) / _perLevelSec) /
              total,
          'Lecture en ${v.height}p'
          '${rebufferCount > 0 ? ' · $rebufferCount interruption${rebufferCount > 1 ? 's' : ''}' : ''}',
        );
        final val = controller.value;
        if (val.duration > Duration.zero && val.position >= val.duration) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (stallWatch.isRunning) {
        stallWatch.stop();
        stallSec += stallWatch.elapsedMilliseconds / 1000;
      }
      await controller.pause();

      final measuredSec = (wall.elapsedMilliseconds - playStart) / 1000;
      final stallRatio = measuredSec > 0 ? stallSec / measuredSec : 1.0;
      final ok = stallRatio < _maxStallRatio;

      return _LevelResult(
        ok: ok,
        started: true,
        startupMs: startupMs,
        rebufferCount: rebufferCount,
        stallSec: stallSec,
        playedSec: (measuredSec - stallSec).clamp(0, measuredSec).toDouble(),
      );
    } catch (e) {
      logger.w('Streaming: palier ${v.height}p échoué ($e)');
      return const _LevelResult(
          ok: false,
          started: false,
          startupMs: 0,
          rebufferCount: 0,
          stallSec: 0,
          playedSec: 0);
    } finally {
      // Libère la référence côté UI AVANT de disposer le lecteur, sinon le
      // widget VideoPlayer pointe un instant sur un contrôleur libéré
      // (écran rouge furtif au changement de palier).
      onController?.call(null);
      controller.removeListener(listener);
      await Future.delayed(const Duration(milliseconds: 180));
      await controller.dispose();
    }
  }

  /// Mesure simple sur une source unique (web, ou repli sans renditions).
  Future<StreamingTestResult> _runSingle(
    String url,
    StreamingControllerCallback? onController,
    StreamingProgressCallback? onProgress,
  ) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    int rebufferCount = 0;
    double stallSec = 0;
    double maxHeight = 0;
    bool started = false;
    final stallWatch = Stopwatch();

    void listener() {
      final v = controller.value;
      if (v.size.height > maxHeight) maxHeight = v.size.height;
      if (!started) return;
      if (v.isBuffering && !stallWatch.isRunning) {
        stallWatch.start();
        rebufferCount++;
      } else if (!v.isBuffering && stallWatch.isRunning) {
        stallWatch.stop();
        stallSec += stallWatch.elapsedMilliseconds / 1000;
        stallWatch.reset();
      }
    }

    final wall = Stopwatch()..start();
    try {
      controller.addListener(listener);
      await controller.initialize().timeout(const Duration(seconds: 30));
      await controller.setVolume(0);
      onController?.call(controller);
      await controller.play();

      int startupMs = -1;
      while (wall.elapsed.inSeconds < 30) {
        if (controller.value.position > Duration.zero) {
          startupMs = wall.elapsedMilliseconds;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (startupMs < 0) throw TimeoutException('Lecture non démarrée');
      started = true;

      final playStart = wall.elapsedMilliseconds;
      while ((wall.elapsedMilliseconds - playStart) / 1000 <
          STREAMING_VIDEO_DURATION_SEC) {
        onProgress?.call(
          ((wall.elapsedMilliseconds - playStart) / 1000) /
              STREAMING_VIDEO_DURATION_SEC,
          'Lecture en ${_resolutionLabel(maxHeight)}',
        );
        final v = controller.value;
        if (v.duration > Duration.zero && v.position >= v.duration) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (stallWatch.isRunning) {
        stallWatch.stop();
        stallSec += stallWatch.elapsedMilliseconds / 1000;
      }
      await controller.pause();

      final measuredSec = (wall.elapsedMilliseconds - playStart) / 1000;
      final rebufferRatio =
          measuredSec > 0 ? (stallSec / measuredSec).clamp(0.0, 1.0) : 1.0;
      final score =
          _computeScore(maxHeight, startupMs, rebufferRatio, rebufferCount);

      return StreamingTestResult(
        startupMs: startupMs,
        rebufferCount: rebufferCount,
        rebufferRatio: double.parse(rebufferRatio.toStringAsFixed(3)),
        maxResolution: _resolutionLabel(maxHeight),
        score: double.parse(score.toStringAsFixed(1)),
      );
    } finally {
      onController?.call(null);
      controller.removeListener(listener);
      await Future.delayed(const Duration(milliseconds: 150));
      await controller.dispose();
    }
  }

  String _resolutionLabel(double height) {
    if (height >= 2160) return '2160p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    if (height > 0) return '${height.round()}p';
    return 'inconnue';
  }

  double _computeScore(
      double maxHeight, int startupMs, double rebufferRatio, int rebufferCount) {
    final double base = maxHeight >= 2160
        ? 100
        : maxHeight >= 1080
            ? 90
            : maxHeight >= 720
                ? 75
                : maxHeight >= 480
                    ? 55
                    : maxHeight > 0
                        ? 35
                        : 0;
    double score = base;
    if (startupMs > 2000) score -= (startupMs - 2000) / 500;
    score -= 40 * rebufferRatio + 2 * rebufferCount;
    return score.clamp(0, 100);
  }
}
