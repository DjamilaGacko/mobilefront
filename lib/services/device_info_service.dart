import 'package:device_info_plus/device_info_plus.dart';
import 'package:logger/logger.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class DeviceInfoService {
  final logger = Logger();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

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
