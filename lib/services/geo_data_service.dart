import 'dart:math';

import 'package:logger/logger.dart';
import '../models/speed_test_result.dart';
import 'local_storage_service.dart';

/// Service de gestion des données géolocalisées
/// 
/// Permet de :
/// - Filtrer les résultats de test par localisation
/// - Grouper les résultats par opérateur et zone géographique
/// - Générer des statistiques géographiques
/// - Récupérer les données pour affichage sur la carte
class GeoDataService {
  final logger = Logger();
  final LocalStorageService _storageService;

  GeoDataService(this._storageService);

  /// Récupère tous les résultats avec coordonnées valides (pour la carte)
  List<SpeedTestResult> getGeoResults() {
    try {
      final allResults = _storageService.getAllResults();
      final geoResults = allResults
          .where((result) =>
              result.latitude != null &&
              result.longitude != null &&
              result.latitude != 0.0 &&
              result.longitude != 0.0)
          .toList();

      logger.i(
          '🗺️ ${geoResults.length} résultats avec coordonnées GPS trouvés');
      return geoResults;
    } catch (e) {
      logger.e('Erreur récupération résultats géo: $e');
      return [];
    }
  }

  /// Récupère les résultats d'une zone spécifique (boîte délimitée)
  List<SpeedTestResult> getResultsByBoundingBox(
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
  ) {
    try {
      final geoResults = getGeoResults();
      final boxResults = geoResults
          .where((result) =>
              result.latitude! >= minLat &&
              result.latitude! <= maxLat &&
              result.longitude! >= minLng &&
              result.longitude! <= maxLng)
          .toList();

      logger.i('🗺️ ${boxResults.length} résultats dans la zone spécifiée');
      return boxResults;
    } catch (e) {
      logger.e('Erreur filtrage zone: $e');
      return [];
    }
  }

  /// Récupère les résultats filtrés par opérateur
  List<SpeedTestResult> getResultsByOperator(String operator) {
    try {
      final allResults = _storageService.getAllResults();
      final filtered = allResults
          .where((result) =>
              result.operator != null &&
              result.operator!.toLowerCase().contains(operator.toLowerCase()))
          .toList();

      logger.i('📶 ${filtered.length} résultats pour opérateur: $operator');
      return filtered;
    } catch (e) {
      logger.e('Erreur filtrage opérateur: $e');
      return [];
    }
  }

  /// Récupère les résultats filtrés par type de réseau
  List<SpeedTestResult> getResultsByNetworkType(String networkType) {
    try {
      final allResults = _storageService.getAllResults();
      final filtered = allResults
          .where((result) =>
              result.networkType != null &&
              result.networkType!.toLowerCase().contains(networkType.toLowerCase()))
          .toList();

      logger.i('📡 ${filtered.length} résultats pour type: $networkType');
      return filtered;
    } catch (e) {
      logger.e('Erreur filtrage type réseau: $e');
      return [];
    }
  }

  /// Récupère les résultats filtrés par localisation (pays/ville)
  List<SpeedTestResult> getResultsByLocation(String location) {
    try {
      final allResults = _storageService.getAllResults();
      final filtered = allResults
          .where((result) =>
              result.location != null &&
              result.location!.toLowerCase().contains(location.toLowerCase()))
          .toList();

      logger.i('🌍 ${filtered.length} résultats pour localisation: $location');
      return filtered;
    } catch (e) {
      logger.e('Erreur filtrage localisation: $e');
      return [];
    }
  }

  /// Génère des statistiques géographiques
  Map<String, dynamic> getGeoStatistics() {
    try {
      final allResults = _storageService.getAllResults();

      if (allResults.isEmpty) {
        return {
          'totalResults': 0,
          'uniqueLocations': 0,
          'operatorStats': {},
          'networkTypeStats': {},
          'bestPerformer': null,
          'averageDownload': 0.0,
          'averageUpload': 0.0,
        };
      }

      // Localités uniques
      final uniqueLocations = allResults
          .where((r) => r.location != null)
          .map((r) => r.location!)
          .toSet();

      // Statistiques par opérateur
      final operatorStats = <String, Map<String, dynamic>>{};
      for (final result in allResults) {
        final op = result.operator ?? 'Unknown';
        if (!operatorStats.containsKey(op)) {
          operatorStats[op] = {
            'count': 0,
            'avgDownload': 0.0,
            'avgUpload': 0.0,
            'totalDownload': 0.0,
            'totalUpload': 0.0,
          };
        }
        operatorStats[op]!['count'] += 1;
        operatorStats[op]!['totalDownload'] += result.downloadSpeed;
        operatorStats[op]!['totalUpload'] += result.uploadSpeed;
      }

      // Calculer les moyennes
      for (final stats in operatorStats.values) {
        stats['avgDownload'] = stats['totalDownload'] / stats['count'];
        stats['avgUpload'] = stats['totalUpload'] / stats['count'];
      }

      // Statistiques par type de réseau
      final networkTypeStats = <String, Map<String, dynamic>>{};
      for (final result in allResults) {
        final netType = result.networkType ?? 'Unknown';
        if (!networkTypeStats.containsKey(netType)) {
          networkTypeStats[netType] = {
            'count': 0,
            'avgDownload': 0.0,
            'avgUpload': 0.0,
            'totalDownload': 0.0,
            'totalUpload': 0.0,
          };
        }
        networkTypeStats[netType]!['count'] += 1;
        networkTypeStats[netType]!['totalDownload'] += result.downloadSpeed;
        networkTypeStats[netType]!['totalUpload'] += result.uploadSpeed;
      }

      // Calculer les moyennes
      for (final stats in networkTypeStats.values) {
        stats['avgDownload'] = stats['totalDownload'] / stats['count'];
        stats['avgUpload'] = stats['totalUpload'] / stats['count'];
      }

      // Meilleur résultat
      final bestResult = allResults.reduce((a, b) =>
          a.downloadSpeed > b.downloadSpeed ? a : b);

      final avgDownload = allResults.fold<double>(
              0.0, (sum, r) => sum + r.downloadSpeed) /
          allResults.length;
      final avgUpload =
          allResults.fold<double>(0.0, (sum, r) => sum + r.uploadSpeed) /
              allResults.length;

      return {
        'totalResults': allResults.length,
        'uniqueLocations': uniqueLocations.length,
        'operatorStats': operatorStats,
        'networkTypeStats': networkTypeStats,
        'bestPerformer': bestResult,
        'averageDownload': avgDownload,
        'averageUpload': avgUpload,
      };
    } catch (e) {
      logger.e('Erreur calcul statistiques géo: $e');
      return {};
    }
  }

  /// Récupère les points chauds (hotspots) - zones avec le plus de tests
  List<Map<String, dynamic>> getHotspots({int radius = 10}) {
    try {
      final geoResults = getGeoResults();
      final hotspots = <Map<String, dynamic>>[];

      final processed = <String>{};

      for (final result in geoResults) {
        final key =
            '${result.latitude!.toStringAsFixed(1)}_${result.longitude!.toStringAsFixed(1)}';
        if (processed.contains(key)) continue;
        processed.add(key);

        final nearbyResults = geoResults
            .where((r) =>
                (_calculateDistance(result.latitude!, r.latitude!,
                        result.longitude!, r.longitude!) <
                    radius))
            .toList();

        if (nearbyResults.length > 1) {
          final avgDownload = nearbyResults.fold<double>(
                  0.0, (sum, r) => sum + r.downloadSpeed) /
              nearbyResults.length;
          final avgUpload =
              nearbyResults.fold<double>(0.0, (sum, r) => sum + r.uploadSpeed) /
                  nearbyResults.length;

          hotspots.add({
            'latitude': result.latitude,
            'longitude': result.longitude,
            'location': result.location,
            'testCount': nearbyResults.length,
            'avgDownload': avgDownload,
            'avgUpload': avgUpload,
            'operators': nearbyResults
                .map((r) => r.operator)
                .toSet()
                .toList(),
          });
        }
      }

      hotspots.sort((a, b) => (b['testCount'] as int).compareTo(a['testCount'] as int));
      logger.i('🔥 ${hotspots.length} hotspots trouvés');
      return hotspots;
    } catch (e) {
      logger.e('Erreur calcul hotspots: $e');
      return [];
    }
  }

  /// Calcule la distance entre deux points GPS (Haversine formula)
  double _calculateDistance(double lat1, double lat2, double lng1, double lng2) {
    const R = 6371; // Rayon de la Terre en km
    final dLat = (lat2 - lat1) * 3.14159 / 180;
    final dLng = (lng2 - lng1) * 3.14159 / 180;
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.14159 / 180) *
            cos(lat2 * 3.14159 / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
}
