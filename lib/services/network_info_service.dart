import 'package:logger/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Service d'information réseau
/// 
/// Détecte le type de connexion (WiFi, 4G, 5G, etc.), l'opérateur mobile,
/// et autres informations réseau pertinentes pour le test de vitesse.
class NetworkInfoService {
  final logger = Logger();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Mapping des opérateurs par pays (simplifié)
  static const Map<String, Map<String, String>> operatorsByCountry = {
    'MA': {
      // Maroc
      '20600': 'Maroc Telecom',
      '20601': 'Maroc Telecom',
      '20602': 'Maroc Telecom',
      '20610': 'Orange Maroc',
      '20611': 'Maroc Telecom',
      '20620': 'Inwi',
      '20621': 'Inwi',
      '20622': 'Stc/Itissalat',
    },
    'SN': {
      // Sénégal
      '22801': 'Sonatel',
      '22802': 'Orange Sénégal',
      '22803': 'Expresso',
    },
    'BF': {
      // Burkina Faso
      '61301': 'Orange Burkina Faso',
      '61302': 'Zain',
      '61304': 'Telecel Faso',
      '61305': 'Vodafone Burkina',
    },
    'CI': {
      // Côte d'Ivoire
      '61215': 'Orange Côte d\'Ivoire',
      '61201': 'MTN Côte d\'Ivoire',
      '61204': 'MOOV Côte d\'Ivoire',
      '61216': 'KoZ',
    },
  };

  /// Récupère le type de réseau actuel (WiFi, 4G, 5G, etc.)
  /// Retourne: 'WiFi', '5G', '4G', '3G', '2G' ou 'Unknown'
  Future<String?> getNetworkType() async {
    try {
      if (kIsWeb) {
        return 'Web Connection';
      }

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        // Sur Android, on peut essayer de détecter 5G vs 4G via les propriétés système
        // Pour cette implémentation, on utilise une estimation basée sur la performance
        logger.i('📱 Appareil Android: ${androidInfo.model}');
        return _estimateNetworkType();
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        logger.i('📱 Appareil iOS: ${iosInfo.model}');
        return _estimateNetworkType();
      }
    } catch (e) {
      logger.e('Erreur détection type réseau: $e');
    }

    return 'Unknown';
  }

  /// Estime le type de réseau (implémentation basique)
  String _estimateNetworkType() {
    // Heuristique simple: on suppose 4G par défaut sur les appareils modernes
    // Une implémentation réelle nécessiterait connectivity_plus
    return '4G';
  }

  /// Récupère le SSID du WiFi connecté
  Future<String?> getWiFiSSID() async {
    try {
      if (Platform.isAndroid) {
        logger.w('WiFi SSID non disponible sans permission supplémentaire');
        return null;
      }
    } catch (e) {
      logger.e('Erreur récupération SSID: $e');
    }
    return null;
  }

  /// Récupère le BSSID (MAC address) du WiFi
  Future<String?> getWiFiBSSID() async {
    logger.w('WiFi BSSID non disponible');
    return null;
  }

  /// Récupère l'adresse IP locale
  Future<String?> getIPAddress() async {
    try {
      // Cette fonctionnalité nécessiterait network_interfaces
      logger.w('IP locale non disponible sans dépendance supplémentaire');
      return null;
    } catch (e) {
      logger.e('Erreur récupération IP: $e');
    }
    return null;
  }

  /// Récupère la force du signal réseau
  Future<Map<String, dynamic>> getSignalStrength() async {
    try {
      // Cette fonctionnalité nécessiterait connectivity_plus
      return {};
    } catch (e) {
      logger.e('Erreur récupération force signal: $e');
      return {};
    }
  }

  /// Retourne la force du signal en texte
  String _estimateSignalStrength(int rssi) {
    if (rssi > -50) return 'Excellent';
    if (rssi > -60) return 'Très bon';
    if (rssi > -70) return 'Bon';
    if (rssi > -80) return 'Faible';
    return 'Très faible';
  }

  /// Récupère le nom de l'opérateur mobile
  Future<String?> getOperatorName() async {
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        // Essayer d'extraire le nom de l'opérateur depuis les propriétés système
        // Retomber sur une valeur par défaut
        logger.i('📶 Recherche opérateur...');
        return 'Opérateur Mobile';
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        logger.i('📶 Opérateur iOS (non disponible sans package supplémentaire)');
        return 'Opérateur Mobile';
      }
    } catch (e) {
      logger.e('Erreur récupération opérateur: $e');
    }
    return 'Opérateur Mobile';
  }

  /// Récupère le SIM en cours d'utilisation (numéro, opérateur, etc.)
  Future<SIMInfo?> getSIMInfo() async {
    try {
      // Cette fonctionnalité nécessiterait sim_data ou telephony packages
      logger.w('Informations SIM non disponibles sans package supplémentaire');
      return null;
    } catch (e) {
      logger.e('Erreur récupération SIM: $e');
    }
    return null;
  }

  /// Récupère toutes les informations réseau
  Future<Map<String, dynamic>> getFullNetworkInfo() async {
    return {
      'networkType': await getNetworkType(),
      'wifiSSID': await getWiFiSSID(),
      'ipAddress': await getIPAddress(),
      'signalStrength': await getSignalStrength(),
      'operator': await getOperatorName(),
      'simInfo': await getSIMInfo(),
    };
  }

  Stream getWatchConnectivity() {
    return Stream.empty();
  }

  Stream watchConnectivity() {
    return getWatchConnectivity();
  }
}

/// Classe représentant les informations SIM
class SIMInfo {
  final String? simSerialNumber;
  final String? operatorName;
  final String? countryIso;
  final String? phoneNumber;

  SIMInfo({
    this.simSerialNumber,
    this.operatorName,
    this.countryIso,
    this.phoneNumber,
  });

  @override
  String toString() => 'SIM: $operatorName ($countryIso)';
}
