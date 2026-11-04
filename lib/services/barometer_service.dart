import 'package:dio/dio.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';

/// Débit médian d'un opérateur.
class BarometerOperator {
  final String name;
  final int count;
  final double medianDownload;

  const BarometerOperator(this.name, this.count, this.medianDownload);
}

/// Position d'un résultat parmi les autres mesures (IMP-11).
class Barometer {
  /// « mobile » ou « wifi » : on ne compare qu'à type de connexion égal.
  final String network;
  final int count;
  final int days;

  /// Part des mesures que le résultat dépasse, en %.
  final int downloadPct;
  final int uploadPct;
  final int pingPct;

  /// Position parmi les clients du même opérateur, si assez de mesures.
  final String? operatorName;
  final int? operatorPct;

  /// Opérateurs classés par débit médian décroissant.
  final List<BarometerOperator> operators;

  const Barometer({
    required this.network,
    required this.count,
    required this.days,
    required this.downloadPct,
    required this.uploadPct,
    required this.pingPct,
    required this.operators,
    this.operatorName,
    this.operatorPct,
  });

  factory Barometer.fromJson(Map<String, dynamic> j) {
    final you = j['you'] as Map? ?? const {};
    final op = j['operator'] as Map?;
    int pct(Object? v) => (v as num?)?.toInt() ?? 0;
    return Barometer(
      network: (j['network'] ?? 'mobile').toString(),
      count: pct(j['count']),
      days: pct(j['days']),
      downloadPct: pct(you['downloadPct']),
      uploadPct: pct(you['uploadPct']),
      pingPct: pct(you['pingPct']),
      operatorName: op?['name']?.toString(),
      operatorPct: op == null ? null : pct(op['downloadPct']),
      operators: [
        for (final o in (j['operators'] as List? ?? const []).whereType<Map>())
          BarometerOperator(
            (o['name'] ?? '').toString(),
            pct(o['count']),
            (o['medianDownload'] as num?)?.toDouble() ?? 0,
          ),
      ],
    );
  }
}

class BarometerService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: API_BASE_URL,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Situe [r] parmi les mesures des 90 derniers jours. null si le serveur
  /// est injoignable ou s'il n'a pas assez de mesures pour comparer.
  Future<Barometer?> compare(SpeedTestResult r) async {
    try {
      final res = await _dio.get('/api/barometer', queryParameters: {
        'network': r.networkType ?? '',
        'operator': r.operator ?? '',
        'download': r.downloadSpeed.toStringAsFixed(2),
        'upload': r.uploadSpeed.toStringAsFixed(2),
        'ping': r.ping.toStringAsFixed(1),
      });
      final b = Barometer.fromJson(Map<String, dynamic>.from(res.data as Map));
      // Sous une vingtaine de mesures, un pourcentage ne veut rien dire.
      return b.count >= 20 ? b : null;
    } catch (_) {
      return null;
    }
  }
}
