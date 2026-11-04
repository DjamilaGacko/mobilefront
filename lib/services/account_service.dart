import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show StringCharacters, ValueNotifier;
import 'package:logger/logger.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';
import 'local_storage_service.dart';
import 'settings_service.dart';

/// Compte utilisateur connecté.
class Account {
  final String id;
  final String email;
  final String name;
  final int tests; // mesures rattachées au compte côté serveur

  const Account({
    required this.id,
    required this.email,
    required this.name,
    this.tests = 0,
  });

  /// Nom affiché : le nom saisi, ou à défaut la partie locale de l'adresse.
  String get displayName => name.isNotEmpty ? name : email.split('@').first;

  String get initial =>
      displayName.isEmpty ? '?' : displayName.characters.first.toUpperCase();

  factory Account.fromJson(Map<String, dynamic> json) {
    final user = Map<String, dynamic>.from(json['user'] as Map);
    return Account(
      id: user['id'].toString(),
      email: (user['email'] ?? '').toString(),
      name: (user['name'] ?? '').toString(),
      tests: (json['tests'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toStore() =>
      {'id': id, 'email': email, 'name': name, 'tests': tests};

  factory Account.fromStore(Map stored) => Account(
        id: stored['id'].toString(),
        email: (stored['email'] ?? '').toString(),
        name: (stored['name'] ?? '').toString(),
        tests: (stored['tests'] as num?)?.toInt() ?? 0,
      );
}

/// Erreur présentable telle quelle à l'utilisateur.
class AccountException implements Exception {
  final String message;
  const AccountException(this.message);
  @override
  String toString() => message;
}

/// Comptes utilisateurs (IMP-03).
///
/// Le compte est facultatif : sans lui, l'application fonctionne comme avant
/// et les mesures restent anonymes. Connecté, chaque mesure est rattachée au
/// compte, ce qui permet de retrouver son historique sur un autre téléphone
/// et de séparer les historiques de plusieurs personnes sur le même appareil.
///
/// Le jeton de session est conservé dans la boîte de réglages, dans le
/// stockage privé de l'application. Le mot de passe, lui, n'est jamais gardé.
class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _kToken = 'accountToken';
  static const _kAccount = 'account';

  final _logger = Logger();
  final Dio _dio = Dio(BaseOptions(
    baseUrl: API_BASE_URL,
    // Le serveur gratuit peut mettre près d'une minute à sortir de veille.
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    contentType: Headers.jsonContentType,
  ));

  /// Compte connecté, ou null. Les écrans s'y abonnent pour se mettre à jour
  /// à la connexion et à la déconnexion.
  final ValueNotifier<Account?> current = ValueNotifier(null);

  String? get _token => Settings.readValue(_kToken) as String?;

  /// Identifiant du compte connecté, ou null en mode anonyme.
  String? get accountId => current.value?.id;

  /// En-tête à joindre aux requêtes pour qu'elles soient attribuées au compte.
  Map<String, String> get authHeaders {
    final t = _token;
    return t == null ? const {} : {'Authorization': 'Bearer $t'};
  }

  /// Restaure le compte mémorisé, sans appel réseau : l'application doit
  /// démarrer hors connexion. La validité du jeton est vérifiée plus tard,
  /// par [refresh].
  void restore() {
    final stored = Settings.readValue(_kAccount);
    if (_token != null && stored is Map) {
      current.value = Account.fromStore(stored);
    }
  }

  Future<Account> register(String email, String password, String name) =>
      _open('/api/auth/register',
          {'email': email.trim(), 'password': password, 'name': name.trim()});

  Future<Account> login(String email, String password) =>
      _open('/api/auth/login', {'email': email.trim(), 'password': password});

  Future<Account> _open(String path, Map<String, dynamic> body) async {
    final data = await _call(() => _dio.post(path, data: body));
    await Settings.writeValue(_kToken, data['token']);
    final account = await _store(data);
    // Les mesures déjà rattachées au compte (autre téléphone, réinstallation)
    // reviennent dans l'historique.
    syncResults();
    return account;
  }

  /// Revérifie la session auprès du serveur et met à jour le profil. Une
  /// session expirée ou révoquée déconnecte ; une simple absence de réseau,
  /// non.
  Future<void> refresh() async {
    if (_token == null) return;
    try {
      final res = await _dio.get('/api/auth/me',
          options: Options(headers: authHeaders));
      await _store(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await _forget();
    } catch (_) {}
  }

  Future<Account> updateProfile({
    required String name,
    String? currentPassword,
    String? newPassword,
  }) async {
    final data = await _call(() => _dio.put('/api/auth/me',
        data: {
          'name': name.trim(),
          if (newPassword != null && newPassword.isNotEmpty) ...{
            'currentPassword': currentPassword ?? '',
            'newPassword': newPassword,
          },
        },
        options: Options(headers: authHeaders)));
    return _store(data);
  }

  /// Ferme la session. Les mesures du compte restent sur le téléphone mais ne
  /// sont plus affichées : l'historique redevient celui du mode anonyme.
  Future<void> logout() async {
    final headers = authHeaders;
    await _forget();
    try {
      await _dio.post('/api/auth/logout', options: Options(headers: headers));
    } catch (_) {
      // Hors connexion : le jeton expirera de lui-même côté serveur.
    }
  }

  /// Supprime le compte. Ses mesures restent sur la carte, mais anonymes.
  Future<void> deleteAccount(String password) async {
    await _call(() => _dio.delete('/api/auth/me',
        data: {'password': password}, options: Options(headers: authHeaders)));
    final id = accountId;
    await _forget();
    if (id != null) await LocalStorageService().deleteAccountResults(id);
  }

  /// Rapatrie les mesures du compte enregistrées sur le serveur. Celles déjà
  /// présentes sur le téléphone ne sont pas dupliquées.
  /// Retourne le nombre de mesures ajoutées.
  Future<int> syncResults() async {
    final id = accountId;
    if (id == null) return 0;
    try {
      final res = await _dio.get('/api/auth/results',
          options: Options(headers: authHeaders));
      final remote = (res.data as List)
          .whereType<Map>()
          .map((e) => SpeedTestResult.fromJson(Map<String, dynamic>.from(e))
            ..accountId = id
            ..isUploaded = true)
          .toList();
      return await LocalStorageService().mergeResults(remote);
    } catch (e) {
      _logger.w('Synchronisation du compte impossible: $e');
      return 0;
    }
  }

  Future<Account> _store(Map<String, dynamic> data) async {
    final account = Account.fromJson(data);
    await Settings.writeValue(_kAccount, account.toStore());
    current.value = account;
    return account;
  }

  Future<void> _forget() async {
    await Settings.writeValue(_kToken, null);
    await Settings.writeValue(_kAccount, null);
    current.value = null;
  }

  /// Exécute un appel et traduit les erreurs en message lisible.
  Future<Map<String, dynamic>> _call(
      Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        throw AccountException(data['error'] as String);
      }
      if (e.response == null) {
        throw const AccountException(
            'Serveur injoignable. Vérifiez votre connexion internet.');
      }
      throw const AccountException('Une erreur est survenue, réessayez.');
    }
  }
}
