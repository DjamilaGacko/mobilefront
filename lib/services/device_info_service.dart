import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'settings_service.dart';

class DeviceInfoService {
  final logger = Logger();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// Espace de noms propre à Yélé pour dériver l'identifiant d'appareil.
  /// Ne jamais le changer : tous les appareils changeraient d'identifiant, et
  /// le suivi dans le temps repartirait de zéro.
  static const String _deviceIdNamespace =
      'f367eff8-8f26-476c-86ff-a7c21b8b2ff6';

  static String? _cachedDeviceId;

  /// Identifiant d'appareil stable et anonyme (IMP-15).
  ///
  /// C'est une empreinte (UUID v5, SHA-1) de l'identifiant système, jamais
  /// l'identifiant lui-même : on ne peut pas remonter de l'une à l'autre, et
  /// l'empreinte ne se rapproche d'aucune donnée tenue par un autre service.
  /// Elle ne contient rien de personnel — ni numéro de téléphone, ni IMEI, ni
  /// compte — et sert uniquement à relier entre elles les mesures d'un même
  /// appareil, sans compte utilisateur.
  ///
  /// Sous Android, elle survit à une réinstallation. Sous iOS, l'identifiant
  /// fournisseur est conservé tant qu'une application de l'éditeur reste
  /// installée.
  Future<String> getAnonymousDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    String? source;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        source = await _channel.invokeMethod<String>('getAndroidId');
      } else if (!kIsWeb && Platform.isIOS) {
        source = (await _deviceInfo.iosInfo).identifierForVendor;
      }
    } catch (e) {
      logger.w('Identifiant système illisible: $e');
    }

    final id = (source != null && source.isNotEmpty)
        ? const Uuid().v5(_deviceIdNamespace, source)
        : await Settings.fallbackDeviceId();
    return _cachedDeviceId = id;
  }

  Future<String?> getDeviceModel() async {
    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await _deviceInfo.webBrowserInfo;
        return webInfo.browserName.toString().split('.').last.toUpperCase();
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.model;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.model;
      }
    } catch (e) {
      logger.e('Erreur récupération modèle: $e');
    }
    return null;
  }

  Future<String?> getOSVersion() async {
    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await _deviceInfo.webBrowserInfo;
        return webInfo.platform;
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return 'iOS ${iosInfo.systemVersion}';
      }
    } catch (e) {
      logger.e('Erreur récupération OS version: $e');
    }
    return null;
  }

  Future<String?> getProcessorName() async {
    try {
      if (kIsWeb) {
        return 'Web CPU';
      }
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.hardware; // CPU
      }
    } catch (e) {
      logger.e('Erreur récupération processeur: $e');
    }
    return null;
  }

  Future<int?> getTotalMemory() async {
    // totalMemory not available in device_info_plus
    logger.w('Total memory not available');
    return null;
  }

  Future<Map<String, dynamic>> getFullDeviceInfo() async {
    return {
      'model': await getDeviceModel(),
      'osVersion': await getOSVersion(),
      'processor': await getProcessorName(),
      'totalMemory': await getTotalMemory(),
    };
  }
}
