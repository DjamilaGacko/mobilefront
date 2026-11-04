import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'local_storage_service.dart';
import 'test_reminder_service.dart';

/// État de la consommation du mois (IMP-09).
class DataUsageSnapshot {
  /// Données mobiles du téléphone depuis le 1er du mois, toutes applications
  /// confondues ; null sans l'accès aux données d'utilisation.
  final int? deviceBytes;

  /// Données consommées par les tests Yélé depuis le 1er du mois.
  final int yeleBytes;

  /// Seuil mensuel, 0 = aucun.
  final int limitBytes;

  final bool usageAccess;
  final DateTime monthStart;

  const DataUsageSnapshot({
    required this.deviceBytes,
    required this.yeleBytes,
    required this.limitBytes,
    required this.usageAccess,
    required this.monthStart,
  });

  /// Volume affiché : celui du téléphone si on peut le lire, sinon celui
  /// des tests — mieux qu'aucun suivi.
  int get usedBytes => deviceBytes ?? yeleBytes;

  bool get coversWholePhone => deviceBytes != null;

  /// Part du seuil consommée (0 à 1+), null sans seuil.
  double? get ratio => limitBytes > 0 ? usedBytes / limitBytes : null;
}

/// Suivi de la consommation de données (IMP-09) : compteur cumulé du mois,
/// seuil mensuel avec alerte, débit en direct dans la barre d'état.
///
/// Le travail est fait côté Android (DataUsage.kt, LiveSpeedService.kt), pour
/// que l'alerte de seuil et le moniteur fonctionnent sans que l'application
/// soit ouverte. Sur iOS, aucune de ces API n'existe : seul le cumul des
/// tests Yélé est disponible.
class DataUsageService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  bool get isAndroid => Platform.isAndroid;

  Future<DataUsageSnapshot> snapshot() async {
    Map? native;
    if (isAndroid) {
      try {
        native = await _channel.invokeMethod<Map>('getDataUsage');
      } catch (_) {}
    }
    final start = native?['monthStart'] is int
        ? DateTime.fromMillisecondsSinceEpoch(native!['monthStart'] as int)
        : DateTime(DateTime.now().year, DateTime.now().month);
    return DataUsageSnapshot(
      deviceBytes: (native?['deviceBytes'] as num?)?.toInt(),
      yeleBytes: _yeleBytesSince(start),
      limitBytes: (native?['limitBytes'] as num?)?.toInt() ?? 0,
      usageAccess: native?['usageAccess'] == true,
      monthStart: start,
    );
  }

  /// Somme des consommations mesurées par chaque test (IMP-01) depuis
  /// [since], tous comptes confondus : le forfait est celui du téléphone.
  int _yeleBytesSince(DateTime since) {
    try {
      return LocalStorageService()
          .getAllResults()
          .where((r) => !r.timestamp.isBefore(since))
          .fold<int>(0, (sum, r) => sum + (r.dataUsedBytes ?? 0));
    } catch (_) {
      return 0;
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod('openUsageAccessSettings');
    } catch (_) {}
  }

  /// Fixe le seuil mensuel (0 = aucun). Demande l'autorisation d'afficher
  /// des notifications : sans elle, l'alerte de dépassement serait muette.
  Future<void> setLimit(int bytes) async {
    if (!isAndroid) return;
    if (bytes > 0) await TestReminderService().requestPermission();
    try {
      await _channel.invokeMethod('setDataLimit', {'bytes': bytes});
    } catch (_) {}
    await checkLimit();
  }

  /// Compare la consommation au seuil, et prévient si besoin. Appelé après
  /// chaque test et à l'ouverture de l'écran ; le moniteur en direct, s'il
  /// est actif, le fait aussi chaque minute de son côté.
  Future<void> checkLimit() async {
    if (!isAndroid) return;
    final s = await snapshot();
    try {
      await _channel.invokeMethod('checkDataLimit', {
        // Sans accès au compteur du téléphone, on se rabat sur les tests.
        'fallbackBytes': s.coversWholePhone ? null : s.yeleBytes,
      });
    } catch (_) {}
  }

  Future<bool> isLiveMonitorOn() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isLiveMonitorOn') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Active ou coupe le débit en direct. Retourne l'état obtenu.
  Future<bool> setLiveMonitor(bool on) async {
    if (!isAndroid) return false;
    // Android 13+ : sans cette autorisation, le service tourne mais sa
    // notification — donc le débit — reste invisible.
    if (on && !await TestReminderService().requestPermission()) return false;
    try {
      await _channel.invokeMethod('setLiveMonitor', {'on': on});
    } catch (_) {
      return false;
    }
    return on;
  }
}
