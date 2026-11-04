import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import '../models/speed_test_result.dart';

class LocalStorageService {
  final logger = Logger();
  static Box<SpeedTestResult>? _resultsBox;

  static const String boxName = 'speedTestResults';

  Future<void> initialize() async {
    try {
      if (_resultsBox?.isOpen ?? false) {
        return;
      }

      await Hive.initFlutter();

      // Enregistrer l'adaptateur
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SpeedTestResultAdapter());
      }

      _resultsBox = await Hive.openBox<SpeedTestResult>(boxName);
      logger.i('Hive initialisée avec ${_box.length} résultats');
    } catch (e) {
      logger.e('Erreur initialisation Hive: $e');
      rethrow;
    }
  }

  Box<SpeedTestResult> get _box {
    final box = _resultsBox;
    if (box == null || !box.isOpen) {
      throw StateError(
          'LocalStorageService doit être initialisé avant utilisation');
    }
    return box;
  }

  // Sauvegarder un résultat
  Future<void> saveResult(SpeedTestResult result) async {
    try {
      await _box.put(result.id, result);
      logger.i('Résultat sauvegardé: ${result.id}');
    } catch (e) {
      logger.e('Erreur sauvegarde résultat: $e');
      rethrow;
    }
  }

  // Récupérer un résultat
  SpeedTestResult? getResult(String id) {
    try {
      return _box.get(id);
    } catch (e) {
      logger.e('Erreur récupération résultat: $e');
      return null;
    }
  }

  // Récupérer tous les résultats
  List<SpeedTestResult> getAllResults() {
    try {
      return _box.values.toList();
    } catch (e) {
      logger.e('Erreur récupération résultats: $e');
      return [];
    }
  }

  // Récupérer les résultats triés par date (récent d'abord)
  List<SpeedTestResult> getResultsSorted() {
    try {
      List<SpeedTestResult> results = _box.values.toList();
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      logger.e('Erreur tri résultats: $e');
      return [];
    }
  }

  /// Historique d'un compte (IMP-03), le plus récent d'abord. [accountId]
  /// null = mesures faites sans être connecté.
  List<SpeedTestResult> getHistory(String? accountId) {
    try {
      final results =
          _box.values.where((r) => r.accountId == accountId).toList();
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      logger.e('Erreur lecture historique: $e');
      return [];
    }
  }

  /// Ajoute les mesures rapatriées du serveur qui ne sont pas déjà sur le
  /// téléphone. La comparaison porte sur l'identifiant de la mesure — celui
  /// attribué par le serveur à l'envoi — et non sur la clé de stockage, qui
  /// reste l'identifiant provisoire d'avant l'envoi.
  /// Retourne le nombre de mesures ajoutées.
  Future<int> mergeResults(List<SpeedTestResult> remote) async {
    final known = _box.values.map((r) => r.id).toSet();
    final fresh = {
      for (final r in remote)
        if (!known.contains(r.id)) r.id: r,
    };
    await _box.putAll(fresh);
    return fresh.length;
  }

  /// Efface du téléphone les mesures d'un compte supprimé.
  Future<void> deleteAccountResults(String accountId) async {
    final keys = _box.keys
        .where((k) => _box.get(k)?.accountId == accountId)
        .toList();
    await _box.deleteAll(keys);
  }

  // Récupérer les résultats du dernier mois
  List<SpeedTestResult> getResultsLastMonth() {
    try {
      DateTime oneMonthAgo = DateTime.now().subtract(const Duration(days: 30));
      List<SpeedTestResult> results =
          _box.values.where((r) => r.timestamp.isAfter(oneMonthAgo)).toList();
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      logger.e('Erreur récupération dernier mois: $e');
      return [];
    }
  }

  // Chercher dans les résultats
  List<SpeedTestResult> searchResults(String query) {
    try {
      List<SpeedTestResult> results = _box.values.toList();
      return results
          .where((r) =>
              (r.location?.contains(query) ?? false) ||
              r.server.contains(query) ||
              (r.networkType?.contains(query) ?? false))
          .toList();
    } catch (e) {
      logger.e('Erreur recherche: $e');
      return [];
    }
  }

  // Supprimer un résultat
  Future<void> deleteResult(String id) async {
    try {
      await _box.delete(id);
      logger.i('Résultat supprimé: $id');
    } catch (e) {
      logger.e('Erreur suppression résultat: $e');
      rethrow;
    }
  }

  // Supprimer tous les résultats
  Future<void> clearAll() async {
    try {
      await _box.clear();
      logger.i('Tous les résultats ont été supprimés');
    } catch (e) {
      logger.e('Erreur suppression tout: $e');
      rethrow;
    }
  }

  // Statistiques
  Map<String, dynamic> getStatistics() {
    try {
      List<SpeedTestResult> results = getResultsSorted();
      if (results.isEmpty) {
        return {
          'totalTests': 0,
          'averageSpeed': 0,
          'bestSpeed': 0,
          'worstSpeed': 0,
        };
      }

      double avgSpeed =
          results.fold<double>(0.0, (sum, r) => sum + r.downloadSpeed) /
              results.length;
      double bestSpeed =
          results.map((r) => r.downloadSpeed).reduce((a, b) => a > b ? a : b);
      double worstSpeed =
          results.map((r) => r.downloadSpeed).reduce((a, b) => a < b ? a : b);

      return {
        'totalTests': results.length,
        'averageSpeed': avgSpeed,
        'bestSpeed': bestSpeed,
        'worstSpeed': worstSpeed,
        'lastTest': results.isNotEmpty ? results.first.timestamp : null,
      };
    } catch (e) {
      logger.e('Erreur calcul stats: $e');
      return {};
    }
  }

  // Exporter en JSON
  Future<String?> exportToJSON() async {
    try {
      List<SpeedTestResult> results = getAllResults();
      final jsonData = results.map((r) => r.toJson()).toList();
      logger.i('Export JSON: ${jsonData.length} résultats');
      return jsonData.toString();
    } catch (e) {
      logger.e('Erreur export JSON: $e');
      return null;
    }
  }

  int getTotalResults() => _box.length;
}
