import 'package:logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/config.dart';

/// Pourquoi la géolocalisation n'est pas exploitable.
///
/// Renvoyer simplement « pas de position » ne suffisait pas : les trois causes
/// appellent des actions différentes de la part de l'utilisateur — activer le
/// service, accorder l'autorisation, ou passer par les réglages du système
/// quand il l'a refusée définitivement.
enum GpsReadiness {
  ok,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever;

  bool get isReady => this == GpsReadiness.ok;

  String get message {
    switch (this) {
      case GpsReadiness.ok:
        return '';
      case GpsReadiness.serviceDisabled:
        return 'La localisation de votre téléphone est désactivée. '
            'Activez-la pour lancer un test : sans position, la mesure ne peut '
            'pas être placée sur la carte de couverture.';
      case GpsReadiness.permissionDenied:
        return 'Yélé a besoin d\'accéder à votre position pour situer la '
            'mesure sur la carte de couverture.';
      case GpsReadiness.permissionDeniedForever:
        return 'L\'accès à la position a été refusé définitivement. '
            'Autorisez-le depuis les réglages du système pour pouvoir lancer '
            'un test.';
    }
  }
}

/// Service de localisation — GPS réel avec fallback IP
class LocationService {
  final logger = Logger();
  late final Dio _dio;
  late final Dio _nominatim;

  LocationService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: API_BASE_URL,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    // Délais courts : l'adresse est demandée pendant la préparation du test,
    // qu'un serveur lent ne doit pas faire traîner.
    _nominatim = Dio(
      BaseOptions(
        baseUrl: NOMINATIM_BASE_URL,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        headers: {'User-Agent': NOMINATIM_USER_AGENT},
      ),
    );
  }

  /// Vérifie que la géolocalisation est exploitable, et demande l'autorisation
  /// si elle n'a pas encore été accordée.
  ///
  /// Sert de garde avant un test : le cahier des charges impose qu'une mesure
  /// ne puisse pas être lancée sans position, une mesure non géolocalisée
  /// n'ayant aucune valeur pour une carte de couverture.
  Future<GpsReadiness> checkReadiness() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return GpsReadiness.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return GpsReadiness.permissionDeniedForever;
      }
      if (permission == LocationPermission.denied) {
        return GpsReadiness.permissionDenied;
      }
      return GpsReadiness.ok;
    } catch (e) {
      logger.e('Vérification GPS échouée: $e');
      return GpsReadiness.serviceDisabled;
    }
  }

  /// Ouvre les réglages de localisation du système.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Ouvre la fiche de l'application dans les réglages du système, seul endroit
  /// où revenir sur une autorisation refusée définitivement.
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Demande la permission GPS et retourne la position réelle.
  /// Retourne null si l'utilisateur refuse ou si le GPS est indisponible.
  Future<Position?> requestGpsPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logger.w('Service GPS désactivé');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w('Permission GPS refusée');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        logger.w('Permission GPS refusée définitivement');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      logger.i('📍 GPS: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      logger.e('Erreur GPS: $e');
      return null;
    }
  }

  /// Récupère la localisation basée sur l'IP publique (pour l'accueil)
  Future<LocationData?> getCurrentLocation() async {
    try {
      final response = await _dio.get('/getIP', queryParameters: {'isp': 'true'});

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;

        if (data['rawIspInfo'] != null) {
          final ispInfo = data['rawIspInfo'];
          final loc = (ispInfo['loc'] as String).split(',');

          final locationData = LocationData(
            latitude: double.tryParse(loc[0]) ?? 0.0,
            longitude: double.tryParse(loc[1]) ?? 0.0,
            city: ispInfo['city'] ?? 'Unknown',
            region: ispInfo['region'] ?? '',
            country: ispInfo['country'] ?? 'Unknown',
            countryName: _getCountryName(ispInfo['country'] ?? ''),
            operator: ispInfo['org']?.toString().split(' ').skip(1).join(' ') ?? 'Unknown',
            ip: ispInfo['ip'] ?? 'Unknown',
            timezone: ispInfo['timezone'] ?? 'UTC',
            processedString: data['processedString'] ?? '',
          );

          logger.i('🌍 Localisation IP: ${locationData.city}, ${locationData.countryName}');
          return locationData;
        }
      }
    } on DioException catch (e) {
      logger.e('❌ Erreur localisation IP: ${e.message}');
    } catch (e) {
      logger.e('❌ Erreur inattendue localisation: $e');
    }

    return null;
  }

  /// Adresse textuelle d'une position GPS (ISS-10) : « rue, quartier, ville ».
  ///
  /// Passe par Nominatim (OpenStreetMap), déjà utilisé par le tableau de bord
  /// pour sa recherche d'adresse : les deux interfaces nomment donc les lieux
  /// de la même façon. Sa charte d'usage impose un User-Agent identifiant
  /// l'application et au plus une requête par seconde — une par mesure en est
  /// très loin.
  ///
  /// Retourne null en cas d'échec : l'adresse est un complément, jamais une
  /// raison de bloquer ou de retarder l'enregistrement d'une mesure.
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _nominatim.get('/reverse', queryParameters: {
        'format': 'jsonv2',
        'lat': lat,
        'lon': lng,
        // 18 : niveau de la rue. Au-delà, Nominatim renvoie des numéros de
        // bâtiment, rarement renseignés au Burkina Faso.
        'zoom': 18,
        'addressdetails': 1,
        'accept-language': 'fr',
      });
      final data = response.data;
      if (data is! Map || data['address'] is! Map) return null;
      return _formatAddress(Map<String, dynamic>.from(data['address'] as Map));
    } catch (e) {
      logger.w('Géocodage inverse indisponible: $e');
      return null;
    }
  }

  /// Compose une adresse courte à partir du détail Nominatim. Le
  /// `display_name` complet (« …, Kadiogo, Centre, Burkina Faso ») ne tient
  /// pas sur une ligne d'historique ; on garde rue, quartier et ville.
  static String? _formatAddress(Map<String, dynamic> a) {
    String? first(List<String> keys) {
      for (final k in keys) {
        final v = a[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final parts = <String>[];
    void add(String? v) {
      if (v != null && !parts.contains(v)) parts.add(v);
    }

    add(first(['road', 'pedestrian', 'footway', 'residential', 'path']));
    add(first(['neighbourhood', 'quarter', 'suburb', 'city_district']));
    add(first(['city', 'town', 'village', 'municipality', 'county']));
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Récupère le nom de la localisation (ville, pays) depuis les coordonnées IP
  Future<String?> getLocationName(double lat, double lng) async {
    try {
      final location = await getCurrentLocation();
      if (location != null) {
        return '${location.city}, ${location.countryName}';
      }
    } catch (e) {
      logger.e('Erreur récupération nom localisation: $e');
    }
    return null;
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<dynamic> requestLocationPermission() async {
    return await requestGpsPosition();
  }

  String _getCountryName(String countryCode) {
    const countryNames = {
      'US': 'États-Unis',
      'GB': 'Royaume-Uni',
      'FR': 'France',
      'DE': 'Allemagne',
      'IT': 'Italie',
      'ES': 'Espagne',
      'CA': 'Canada',
      'AU': 'Australie',
      'JP': 'Japon',
      'CN': 'Chine',
      'IN': 'Inde',
      'BR': 'Brésil',
      'MX': 'Mexique',
      'SN': 'Sénégal',
      'MA': 'Maroc',
      'NG': 'Nigeria',
      'ZA': 'Afrique du Sud',
      'BF': 'Burkina Faso',
      'CI': "Côte d'Ivoire",
      'ML': 'Mali',
      'NE': 'Niger',
      'TG': 'Togo',
      'BJ': 'Bénin',
      'GH': 'Ghana',
      'KE': 'Kenya',
      'RW': 'Rwanda',
      'UG': 'Ouganda',
    };
    return countryNames[countryCode] ?? countryCode;
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String country;
  final String countryName;
  final String operator;
  final String ip;
  final String timezone;
  final String processedString;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.region,
    required this.country,
    required this.countryName,
    required this.operator,
    required this.ip,
    required this.timezone,
    required this.processedString,
  });

  @override
  String toString() => '$city, $countryName ($ip - $operator)';
}
