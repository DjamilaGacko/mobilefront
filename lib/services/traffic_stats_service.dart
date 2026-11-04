import 'package:flutter/services.dart';

/// Compteurs d'octets reçus et envoyés par l'application, lus via
/// `TrafficStats` (Android).
///
/// Sert à mesurer la consommation de données : on relève le compteur avant et
/// après une mesure, la différence est le volume réellement échangé. Le trafic
/// du WebView est inclus : sur Android, la pile réseau de Chromium tourne dans
/// le processus de l'application, donc sous le même UID.
///
/// iOS n'expose aucun équivalent propre : les compteurs y retournent null et
/// la consommation affiche « — ».
class TrafficStatsService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// Octets reçus par l'application depuis le démarrage de l'appareil.
  /// null si la plateforme ne sait pas le fournir.
  Future<int?> rxBytes() => _read('getRxBytes');

  /// Octets envoyés par l'application depuis le démarrage de l'appareil.
  Future<int?> txBytes() => _read('getTxBytes');

  /// Octets reçus + envoyés : ce que le forfait décompte réellement (IMP-01).
  /// null si l'un des deux compteurs manque — un total partiel sous-estimerait
  /// la consommation sans le dire.
  Future<int?> totalBytes() async {
    final rx = await rxBytes();
    final tx = await txBytes();
    if (rx == null || tx == null) return null;
    return rx + tx;
  }

  Future<int?> _read(String method) async {
    try {
      final value = await _channel.invokeMethod<int>(method);
      if (value == null || value < 0) return null;
      return value;
    } catch (_) {
      // Canal absent (iOS, tests) ou compteur indisponible.
      return null;
    }
  }

  /// Volume reçu entre deux relevés, en kibioctets. -1 si non mesurable.
  static int kibBetween(int? before, int? after) {
    if (before == null || after == null || after < before) return -1;
    return ((after - before) / 1024).round();
  }

  /// Volume lisible : « 850 Ko », « 245 Mo », « 1,2 Go ». Unités décimales,
  /// celles qu'emploient les opérateurs pour décompter les forfaits.
  static String formatBytes(int bytes) {
    if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} Ko';
    if (bytes < 1000 * 1000 * 1000) {
      final mo = bytes / (1000 * 1000);
      return '${mo < 10 ? mo.toStringAsFixed(1).replaceAll('.', ',') : mo.round()} Mo';
    }
    final go = bytes / (1000 * 1000 * 1000);
    return '${go.toStringAsFixed(2).replaceAll('.', ',')} Go';
  }
}
