import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../constants/app_colors.dart';
import '../models/speed_test_result.dart';
import '../models/test_selection.dart';
import 'browsing_test_service.dart';
import 'streaming_test_service.dart';

enum SpeedTestPhase {
  initializing,
  download,
  ping,
  upload,
  streaming,
  browsing,
  telemetry,
  completed,
  failed,
}

class SpeedTestProgress {
  final SpeedTestPhase phase;
  final String message;
  final double? downloadSpeed;
  final double? uploadSpeed;
  final double? ping;
  final double? jitter;

  const SpeedTestProgress({
    required this.phase,
    required this.message,
    this.downloadSpeed,
    this.uploadSpeed,
    this.ping,
    this.jitter,
  });

  /// Index de la phase parmi les phases réellement exécutées, selon la
  /// sélection de tests (les phases non sélectionnées sont sautées).
  int phaseIndexFor(TestSelection selection) {
    int index;
    switch (phase) {
      case SpeedTestPhase.initializing:
      case SpeedTestPhase.failed:
        return 0;
      case SpeedTestPhase.download:
        return 1;
      case SpeedTestPhase.ping:
        return 2;
      case SpeedTestPhase.upload:
        return 3;
      case SpeedTestPhase.streaming:
        return 4;
      case SpeedTestPhase.browsing:
        index = 4 + (selection.streaming ? 1 : 0);
        return index;
      case SpeedTestPhase.telemetry:
        index = 4 +
            (selection.streaming ? 1 : 0) +
            (selection.browsing ? 1 : 0);
        return index;
      case SpeedTestPhase.completed:
        index = 5 +
            (selection.streaming ? 1 : 0) +
            (selection.browsing ? 1 : 0);
        return index;
    }
  }

  /// Compatibilité : index sans tests optionnels.
  int get phaseIndex => phaseIndexFor(const TestSelection());
}

class SpeedTransferMeasurement {
  final double mbps;
  final int bytes;
  final Duration duration;

  const SpeedTransferMeasurement({
    required this.mbps,
    required this.bytes,
    required this.duration,
  });
}

class LatencyMeasurement {
  final double ping;
  final double jitter;

  const LatencyMeasurement({
    required this.ping,
    required this.jitter,
  });
}

typedef SpeedTestProgressCallback = void Function(SpeedTestProgress progress);

class SpeedTestApiService {
  final logger = Logger();
  late final Dio _dio;
  final String baseUrl = API_BASE_URL;

  SpeedTestApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 300),
        sendTimeout: const Duration(seconds: 300),
        contentType: 'application/json',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          logger.i('Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onError: (error, handler) {
          logger.e('DIO Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  Future<SpeedTestResult> runSpeedTest({
    double? latitude,
    double? longitude,
    String? location,
    String? networkType,
    String? operator,
    String? deviceModel,
    String? osVersion,
    int? batteryLevel,
    TestSelection selection = const TestSelection(),
    SpeedTestProgressCallback? onProgress,
    StreamingControllerCallback? onStreamingController,
    BrowsingControllerCallback? onBrowsingController,
    // Permet à l'UI de recueillir la note QoE et de l'attacher au résultat
    // AVANT l'envoi au serveur, pour qu'elle soit incluse dans la télémétrie.
    Future<void> Function(SpeedTestResult result)? onCollectQoe,
    // Si faux, le résultat est retourné sans QoE ni envoi : l'UI peut alors
    // afficher le bilan d'abord, puis déclencher QoE + envoi (uploadTestResult).
    bool autoUpload = true,
  }) async {
    String? ipInfo;

    try {
      onProgress?.call(
        const SpeedTestProgress(
          phase: SpeedTestPhase.initializing,
          message: 'Initialisation du test',
        ),
      );

      ipInfo = await getPublicIP();

      // Débit : exécuté uniquement si demandé (tests indépendants).
      double dlMbps = 0, ulMbps = 0, pingMs = 0, jitterMs = 0;
      if (selection.speed) {
        onProgress?.call(const SpeedTestProgress(
          phase: SpeedTestPhase.download,
          message: 'Mesure du téléchargement',
        ));
        final download = await measureDownloadSpeed(chunkSize: 2, parallel: 2);
        dlMbps = download.mbps;
        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.download,
          message: 'Téléchargement mesuré',
          downloadSpeed: dlMbps,
        ));

        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.ping,
          message: 'Mesure de la latence',
          downloadSpeed: dlMbps,
        ));
        final latency = await measureLatency();
        pingMs = latency.ping;
        jitterMs = latency.jitter;
        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.ping,
          message: 'Latence mesurée',
          downloadSpeed: dlMbps,
          ping: pingMs,
          jitter: jitterMs,
        ));

        onProgress?.call(SpeedTestProgress(
          phase: SpeedTestPhase.upload,
          message: 'Mesure du chargement',
          downloadSpeed: dlMbps,
          ping: pingMs,
          jitter: jitterMs,
        ));
        final upload = await measureUploadSpeed(uploadSize: 1, parallel: 2);
        ulMbps = upload.mbps;
      }

      // ── Tests optionnels : streaming vidéo et navigation web ──────────────
      StreamingTestResult? streaming;
      if (selection.streaming) {
        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.streaming,
            message: 'Test de streaming vidéo',
            downloadSpeed: dlMbps,
            uploadSpeed: ulMbps,
            ping: pingMs,
            jitter: jitterMs,
          ),
        );
        try {
          streaming = await StreamingTestService().runTest(
            onController: onStreamingController,
            onProgress: (progress, message) => onProgress?.call(
              SpeedTestProgress(
                phase: SpeedTestPhase.streaming,
                message: message,
                downloadSpeed: dlMbps,
                uploadSpeed: ulMbps,
                ping: pingMs,
                jitter: jitterMs,
              ),
            ),
          );
        } catch (e) {
          logger.e('Test streaming échoué: $e');
        }
      }

      BrowsingTestResult? browsing;
      if (selection.browsing) {
        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.browsing,
            message: 'Test de navigation web',
            downloadSpeed: dlMbps,
            uploadSpeed: ulMbps,
            ping: pingMs,
            jitter: jitterMs,
          ),
        );
        try {
          browsing = await BrowsingTestService().runTest(
            onController: onBrowsingController,
            onProgress: (progress, message) => onProgress?.call(
              SpeedTestProgress(
                phase: SpeedTestPhase.browsing,
                message: message,
                downloadSpeed: dlMbps,
                uploadSpeed: ulMbps,
                ping: pingMs,
                jitter: jitterMs,
              ),
            ),
          );
        } catch (e) {
          logger.e('Test navigation échoué: $e');
        }
      }

      final result = SpeedTestResult(
        downloadSpeed: dlMbps,
        uploadSpeed: ulMbps,
        ping: pingMs,
        jitter: jitterMs,
        server: 'Render.com',
        clientIp: _extractIp(ipInfo),
        networkType: networkType,
        operator: operator ?? _extractOperator(ipInfo),
        latitude: latitude,
        longitude: longitude,
        location: location ?? _extractLocation(ipInfo),
        deviceModel: deviceModel,
        osVersion: osVersion,
        batteryLevel: batteryLevel,
        testLog: ipInfo,
        streamingStartupMs: streaming?.startupMs,
        streamingRebufferCount: streaming?.rebufferCount,
        streamingRebufferRatio: streaming?.rebufferRatio,
        streamingMaxResolution: streaming?.maxResolution,
        streamingScore: streaming?.score,
        browsingAvgLoadMs: browsing?.avgLoadMs,
        browsingSuccessRate: browsing?.successRate,
        browsingPagesTested: browsing?.pagesTested,
        browsingScore: browsing?.score,
      );

      // Par défaut : QoE puis envoi immédiat. Si autoUpload=false, l'UI gère
      // l'affichage du bilan, le QoE et l'envoi après coup.
      if (autoUpload) {
        if (onCollectQoe != null) {
          await onCollectQoe(result);
        }

        onProgress?.call(
          SpeedTestProgress(
            phase: SpeedTestPhase.telemetry,
            message: 'Envoi des résultats au serveur',
            downloadSpeed: result.downloadSpeed,
            uploadSpeed: result.uploadSpeed,
            ping: result.ping,
            jitter: result.jitter,
          ),
        );

        result.isUploaded = await uploadTestResult(result);
      }

      onProgress?.call(
        SpeedTestProgress(
          phase: SpeedTestPhase.completed,
          message: 'Test terminé',
          downloadSpeed: result.downloadSpeed,
          uploadSpeed: result.uploadSpeed,
          ping: result.ping,
          jitter: result.jitter,
        ),
      );

      return result;
    } catch (e) {
      onProgress?.call(
        SpeedTestProgress(
          phase: SpeedTestPhase.failed,
          message: 'Erreur pendant le test: $e',
        ),
      );
      rethrow;
    }
  }

  // Démarrer un test de vitesse
  // speedtest-go ne démarre pas de job serveur: le client mesure /garbage et /empty.
  Future<Map<String, dynamic>?> startSpeedTest({
    required double latitude,
    required double longitude,
    required String? networkType,
    required String? deviceModel,
    required String? osVersion,
    required int? batteryLevel,
  }) async {
    try {
      final ipResponse = await getPublicIP();
      if (ipResponse != null) {
        logger.i('Test ready, IP: $ipResponse');
        return {
          'testId': DateTime.now().millisecondsSinceEpoch.toString(),
          'status': 'ready',
          'ip': ipResponse,
        };
      }
      return null;
    } on DioException catch (e) {
      logger.e('Erreur init test: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // Récupérer les résultats d'un test en JSON.
  Future<Map<String, dynamic>?> getTestResults(String testId) async {
    try {
      final response = await _dio.get(
        '/results/json',
        queryParameters: {'id': testId},
      );

      if (response.statusCode == 200) {
        logger.i('Résultats reçus pour test: $testId');
        return response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{'raw': response.data};
      }
    } on DioException catch (e) {
      logger.e('Erreur récupération résultats: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // Récupérer l'adresse IP publique et infos ISP.
  Future<String?> getPublicIP() async {
    try {
      final response = await _dio.get(
        '/getIP',
        queryParameters: {'isp': 'true'},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        String? ip;
        if (data is Map) {
          final rawIspInfo = data['rawIspInfo'];
          ip = (data['processedString'] ??
                  data['ip'] ??
                  (rawIspInfo is Map ? rawIspInfo['ip'] : null))
              ?.toString();
        } else {
          ip = data?.toString();
        }
        logger.i('IP publique récupérée: $ip');
        return ip;
      }
    } on DioException catch (e) {
      logger.e('Erreur récupération IP: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  Future<SpeedTransferMeasurement> measureDownloadSpeed({
    int chunkSize = 4,
    int parallel = 4,
  }) async {
    final stopwatch = Stopwatch()..start();
    final chunks = await Future.wait(
      List.generate(parallel, (_) => _downloadChunk(chunkSize)),
    );
    stopwatch.stop();

    final bytes = chunks.fold<int>(0, (sum, value) => sum + value);
    final mbps = _calculateMbps(bytes, stopwatch.elapsed);
    logger.i('Download: ${mbps.toStringAsFixed(2)} Mbps, bytes: $bytes');

    return SpeedTransferMeasurement(
      mbps: mbps,
      bytes: bytes,
      duration: stopwatch.elapsed,
    );
  }

  Future<SpeedTransferMeasurement> measureUploadSpeed({
    int uploadSize = 1,
    int parallel = 4,
  }) async {
    final bytesPerUpload = uploadSize * 1024 * 1024;
    final uploadData = Uint8List.fromList(
      List<int>.generate(bytesPerUpload, (index) => index % 256),
    );

    final stopwatch = Stopwatch()..start();
    final uploads = await Future.wait(
      List.generate(parallel, (_) => _uploadChunk(uploadData)),
    );
    stopwatch.stop();

    final bytes = uploads.fold<int>(0, (sum, value) => sum + value);
    final mbps = _calculateMbps(bytes, stopwatch.elapsed);
    logger.i('Upload: ${mbps.toStringAsFixed(2)} Mbps, bytes: $bytes');

    return SpeedTransferMeasurement(
      mbps: mbps,
      bytes: bytes,
      duration: stopwatch.elapsed,
    );
  }

  Future<LatencyMeasurement> measureLatency({int samples = 5}) async {
    final measurements = <double>[];

    for (int i = 0; i < samples; i++) {
      final stopwatch = Stopwatch()..start();
      await _dio.get(
        '/getIP',
        queryParameters: {
          'isp': 'false',
          'r': DateTime.now().microsecondsSinceEpoch,
        },
        options: Options(responseType: ResponseType.plain),
      );
      stopwatch.stop();
      measurements.add(stopwatch.elapsedMicroseconds / 1000);
    }

    final ping = measurements.reduce((a, b) => a + b) / measurements.length;
    final jitter = measurements.length < 2
        ? 0.0
        : List.generate(
              measurements.length - 1,
              (index) => (measurements[index + 1] - measurements[index]).abs(),
            ).reduce((a, b) => a + b) /
            (measurements.length - 1);

    logger.i(
        'Ping: ${ping.toStringAsFixed(2)} ms, jitter: ${jitter.toStringAsFixed(2)} ms');
    return LatencyMeasurement(ping: ping, jitter: jitter);
  }

  // Obtenir la liste des serveurs disponibles.
  Future<List<Map<String, dynamic>>?> getServers() async {
    logger.i('Serveur unique: Render.com');
    return [
      {
        'name': 'Render.com Default',
        'url': baseUrl,
        'location': 'Render',
        'sponsor': 'Render Platform',
      }
    ];
  }

  // Envoyer les résultats sauvegardés au serveur via telemetry.
  Future<bool> uploadTestResult(SpeedTestResult result) async {
    try {
      final response = await _dio.post(
        '/results/telemetry',
        data: {
          'ispinfo': result.testLog ?? result.location ?? 'Unknown',
          'dl': result.downloadSpeed.toStringAsFixed(2),
          'ul': result.uploadSpeed.toStringAsFixed(2),
          'ping': result.ping.toStringAsFixed(2),
          'jitter': result.jitter.toStringAsFixed(2),
          'log': 'Yélé Mobile Test',
          'extra': jsonEncode({
            'operator': result.operator ?? '',
            'networkType': result.networkType ?? '',
            'deviceModel': result.deviceModel ?? '',
            'location': result.location ?? '',
            'latitude': result.latitude ?? 0.0,
            'longitude': result.longitude ?? 0.0,
            'qoeRating': result.qoeRating ?? 0,
            'qoeSatisfaction': result.qoeSatisfaction ?? '',
            // Streaming / navigation web : 0 = test non effectué
            'streamingStartupMs': result.streamingStartupMs ?? 0,
            'streamingRebufferCount': result.streamingRebufferCount ?? 0,
            'streamingRebufferRatio': result.streamingRebufferRatio ?? 0.0,
            'streamingMaxResolution': result.streamingMaxResolution ?? '',
            'streamingScore': result.streamingScore ?? 0.0,
            'browsingAvgLoadMs': result.browsingAvgLoadMs ?? 0.0,
            'browsingSuccessRate': result.browsingSuccessRate ?? 0.0,
            'browsingPagesTested': result.browsingPagesTested ?? 0,
            'browsingScore': result.browsingScore ?? 0.0,
          }),
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final serverId = _extractTelemetryId(response.data?.toString());
        if (serverId != null) {
          result.id = serverId;
        }
        logger.i('Résultat uploadé: ${result.id}');
        return true;
      }
    } on DioException catch (e) {
      logger.e('Erreur upload résultat: ${e.message}');
      _handleDioError(e);
    }
    return false;
  }

  // speedtest-go ne liste pas l'historique complet côté mobile.
  Future<List<SpeedTestResult>?> getHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    logger.i('Historique géré localement par Hive');
    return null;
  }

  // API de compatibilité: mesure un download et retourne le chronomètre.
  Future<Stopwatch?> downloadTest({
    int chunkSize = 2,
    int parallel = 2,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();
      await Future.wait(
          List.generate(parallel, (_) => _downloadChunk(chunkSize)));
      stopwatch.stop();
      return stopwatch;
    } on DioException catch (e) {
      logger.e('Erreur test download: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  // API de compatibilité: mesure un upload et retourne le chronomètre.
  Future<Stopwatch?> uploadTest({
    int uploadSize = 1,
    int parallel = 4,
  }) async {
    try {
      final bytesPerUpload = uploadSize * 1024 * 1024;
      final uploadData = Uint8List.fromList(
        List<int>.generate(bytesPerUpload, (index) => index % 256),
      );
      final stopwatch = Stopwatch()..start();
      await Future.wait(
          List.generate(parallel, (_) => _uploadChunk(uploadData)));
      stopwatch.stop();
      return stopwatch;
    } on DioException catch (e) {
      logger.e('Erreur test upload: ${e.message}');
      _handleDioError(e);
    }
    return null;
  }

  Future<SpeedTestResult?> pollTestResults(String testId) async {
    try {
      int maxAttempts = 60;
      int attempts = 0;

      while (attempts < maxAttempts) {
        final results = await getTestResults(testId);

        if (results != null) {
          if (results['status'] == 'failed') {
            logger.e('Test échoué: $testId');
            return null;
          }

          if (results['status'] == 'completed' ||
              results.containsKey('download') ||
              results.containsKey('downloadSpeed')) {
            return SpeedTestResult.fromJson({
              ...results,
              'id': testId,
              'server': results['server'] ?? 'Render.com',
            });
          }
        }

        await Future.delayed(const Duration(seconds: 5));
        attempts++;
      }

      logger.e('Timeout: polling dépassé pour test $testId');
    } catch (e) {
      logger.e('Erreur polling: $e');
    }
    return null;
  }

  Future<int> _downloadChunk(int chunkSize) async {
    final response = await _dio.get(
      '/garbage',
      queryParameters: {
        'ckSize': chunkSize,
        'r': DateTime.now().microsecondsSinceEpoch,
      },
      options: Options(
        responseType: kIsWeb ? ResponseType.bytes : ResponseType.stream,
      ),
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final data = response.data;
    if (data is ResponseBody) {
      int bytes = 0;
      await for (final chunk in data.stream) {
        bytes += chunk.length;
      }
      return bytes;
    }

    if (data is List<int>) {
      return data.length;
    }

    return data?.toString().length ?? 0;
  }

  Future<int> _uploadChunk(Uint8List uploadData) async {
    final response = await _dio.post(
      '/empty',
      data: uploadData,
      queryParameters: {'r': DateTime.now().microsecondsSinceEpoch},
      options: Options(
        contentType: 'application/octet-stream',
        responseType: ResponseType.plain,
      ),
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    return uploadData.length;
  }

  double _calculateMbps(int bytes, Duration duration) {
    final seconds =
        max(duration.inMicroseconds / Duration.microsecondsPerSecond, 0.001);
    return (bytes * 8) / seconds / 1000000;
  }

  String? _extractIp(String? value) {
    if (value == null) return null;
    return RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').firstMatch(value)?.group(0);
  }

  String? _extractOperator(String? value) {
    if (value == null || !value.contains(' - ')) return null;
    return value.split(' - ').last.split(',').first.trim();
  }

  String? _extractLocation(String? value) {
    if (value == null || !value.contains(',')) return null;
    final parts = value.split(',');
    return parts.length >= 2
        ? parts.sublist(1).join(',').replaceAll(RegExp(r'\([^)]*\)'), '').trim()
        : null;
  }

  String? _extractTelemetryId(String? value) {
    if (value == null) return null;
    final match = RegExp(r'id\s+([A-Za-z0-9_-]+)').firstMatch(value);
    return match?.group(1);
  }

  void _handleDioError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) {
      logger.e('Timeout de connexion');
    } else if (error.type == DioExceptionType.receiveTimeout) {
      logger.e('Timeout de réception');
    } else if (error.type == DioExceptionType.badResponse) {
      logger.e('Erreur serveur: ${error.response?.statusCode}');
    } else if (error.type == DioExceptionType.connectionError) {
      logger.e('Erreur de connexion');
    }
  }
}
