// Configuration des constantes de l'application Yélé

// ========== API CONFIGURATION ==========
// Modifier cette URL pour pointer vers votre backend speedtest-go
const String API_BASE_URL = 'https://mobiletest-j0c6.onrender.com';
// API MongoDB intégrée au même backend speedtest-go (/api/*)
const String MONGO_API_BASE_URL = '$API_BASE_URL/api';
const Duration API_TIMEOUT = Duration(seconds: 300); // 5 minutes

// ========== APPLICATION CONFIGURATION ==========
const String APP_NAME = 'Yélé - Test de Vitesse';
const String APP_VERSION = '1.0.0';
const String APP_BUILD_NUMBER = '1';

// ========== FEATURE FLAGS ==========
const bool ENABLE_OFFLINE_MODE = true;
const bool ENABLE_ANALYTICS = true;
const bool ENABLE_CRASH_REPORTING = true;
const bool ENABLE_DEBUG_LOGGING = true;

// ========== TEST CONFIGURATION ==========
const int TEST_POLLING_INTERVAL = 5; // secondes
const int TEST_POLLING_MAX_ATTEMPTS = 60; // 5 minutes au total
const int TEST_SOCKET_TIMEOUT = 60; // secondes

// ========== STREAMING & BROWSING TESTS ==========
// Flux vidéo HLS multi-qualités utilisé par le test de streaming réel.
// Big Buck Bunny (libre de droits), renditions 240p → 1080p — le lecteur
// adapte la qualité au réseau comme YouTube. Remplacer par votre propre
// flux HLS (ffmpeg + hébergement statique) pour mesurer votre infrastructure.
const String STREAMING_VIDEO_URL =
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
// Repli pour Flutter Web : Chrome ne lit pas le HLS nativement → MP4 progressif
// (pas d'adaptation de qualité, mais démarrage et interruptions restent mesurés)
const String STREAMING_VIDEO_URL_WEB =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
// Durée de lecture mesurée (consommation : ~10-30 Mo selon la qualité atteinte)
const int STREAMING_VIDEO_DURATION_SEC = 30;
// Durée réelle maximale du test (sécurité réseaux très lents)
const int STREAMING_MAX_TEST_DURATION_SEC = 90;
// Pages de référence du test de navigation web (critère ARCEP : chargée en < 10 s)
const List<String> BROWSING_REFERENCE_PAGES = [
  'https://www.google.com',
  'https://www.wikipedia.org',
  'https://www.facebook.com',
  'https://lefaso.net',
  'https://www.youtube.com',
  'https://www.bing.com',
];

// ========== UI CONFIGURATION ==========
const double DEFAULT_BORDER_RADIUS = 12.0;
const double DEFAULT_PADDING = 20.0;
const double LARGE_PADDING = 32.0;
const double SMALL_PADDING = 8.0;

// ========== DATABASE CONFIGURATION ==========
const String HIVE_BOX_NAME = 'speedTestResults';
const int HIVE_TYPE_ID = 0;
const int MAX_LOCAL_RESULTS = 1000; // Limite du stockage local

// ========== PERMISSIONS CONFIGURATION ==========
const Map<String, String> PERMISSION_MESSAGES = {
  'location': 'Yélé a besoin d\'accéder à votre localisation',
  'battery': 'Yélé a besoin d\'accéder à l\'info batterie',
  'network': 'Yélé a besoin d\'accéder à l\'info réseau',
};

// ========== API ENDPOINTS ==========
const String ENDPOINT_START_TEST = '/speed-test';
const String ENDPOINT_GET_RESULTS = '/results/';
const String ENDPOINT_GET_IP = '/ip';
const String ENDPOINT_GET_SERVERS = '/servers';
const String ENDPOINT_UPLOAD_RESULT = '/results';
const String ENDPOINT_GET_HISTORY = '/results';

// ========== TIMING CONFIGURATION ==========
const Duration ANIMATION_DURATION_SHORT = Duration(milliseconds: 300);
const Duration ANIMATION_DURATION_MEDIUM = Duration(milliseconds: 500);
const Duration ANIMATION_DURATION_LONG = Duration(milliseconds: 1000);

// ========== LOGGING CONFIGURATION ==========
enum LogLevel { verbose, debug, info, warning, error }

class LoggingConfig {
  static const LogLevel DEFAULT_LEVEL = LogLevel.info;
  static const bool PRINT_METHOD_NAMES = true;
  static const bool PRINT_EMOJI = true;
  static const int STACKTRACE_LEVEL = 5;
}

// ========== NETWORK CONFIGURATION ==========
class NetworkConfig {
  static const int CONNECTION_TIMEOUT = 30000; // ms
  static const int RECEIVE_TIMEOUT = 300000; // ms (5 min)
  static const int SEND_TIMEOUT = 300000; // ms (5 min)
  static const String CONTENT_TYPE = 'application/json';
}

// ========== STORAGE CONFIGURATION ==========
class StorageConfig {
  static const String RESULTS_BOX_NAME = 'speedTestResults';
  static const String SETTINGS_BOX_NAME = 'appSettings';
  static const String CACHE_BOX_NAME = 'cache';
  static const Duration AUTO_BACKUP_INTERVAL = Duration(hours: 24);
}

// ========== RATING CONFIGURATION ==========
class RatingConfig {
  static const int EXCELLENT_THRESHOLD = 100; // Mbps
  static const int VERY_GOOD_THRESHOLD = 50;
  static const int GOOD_THRESHOLD = 20;
  static const int AVERAGE_THRESHOLD = 10;
  // Below 10 = Poor

  static String getRating(double speed) {
    if (speed > EXCELLENT_THRESHOLD) return 'Excellent';
    if (speed > VERY_GOOD_THRESHOLD) return 'Très bon';
    if (speed > GOOD_THRESHOLD) return 'Bon';
    if (speed > AVERAGE_THRESHOLD) return 'Moyen';
    return 'Faible';
  }
}

// ========== USAGE RECOMMENDATIONS ==========
class UsageRecommendations {
  static const Map<String, String> RECOMMENDATIONS = {
    'excellent':
        'Votre connexion est idéale pour toutes les activités en ligne incluant la diffusion 4K et les jeux online.',
    'veryGood':
        'Votre connexion est très bonne pour la plupart des activités y compris la vidéo HD et les réunions vidéo.',
    'good':
        'Votre connexion est satisfaisante pour la navigation web, les emails et la vidéo standard.',
    'average':
        'Votre connexion est acceptable mais peut être limitée pour la diffusion vidéo HD.',
    'poor':
        'Votre connexion est lente. Considérez de contacter votre fournisseur d\'accès Internet.',
  };
}

// ========== SERVER REGIONS ==========
class ServerRegions {
  static const Map<String, String> REGIONS = {
    'bamako': 'Bamako, Mali',
    'dakar': 'Dakar, Sénégal',
    'abidjan': 'Abidjan, Côte d\'Ivoire',
    'lagos': 'Lagos, Nigeria',
    'kinshasa': 'Kinshasa, RDC',
    'paris': 'Paris, France',
  };
}

// ========== ERROR MESSAGES ==========
class ErrorMessages {
  static const String NETWORK_ERROR = 'Erreur de connexion Internet';
  static const String LOCATION_ERROR =
      'Impossible d\'accéder à la localisation';
  static const String API_ERROR = 'Erreur serveur API';
  static const String TIMEOUT_ERROR = 'Délai d\'attente dépassé';
  static const String STORAGE_ERROR =
      'Erreur d\'accès à la base de données locale';
  static const String PERMISSION_ERROR = 'Permission refusée';
  static const String UNKNOWN_ERROR = 'Erreur inconnue';
}

// ========== DEVICE CONFIGURATION ==========
class DeviceConfig {
  static const List<String> SUPPORTED_ANDROID_VERSIONS = [
    '8.0',
    '9.0',
    '10.0',
    '11.0',
    '12.0',
    '13.0',
    '14.0'
  ];
  static const List<String> SUPPORTED_IOS_VERSIONS = [
    '12.0',
    '13.0',
    '14.0',
    '15.0',
    '16.0',
    '17.0'
  ];
  static const int MIN_RAM_MB = 512;
  static const int MIN_STORAGE_MB = 50;
}

// ========== ANALYTICS EVENTS ==========
class AnalyticsEvents {
  static const String TEST_STARTED = 'test_started';
  static const String TEST_COMPLETED = 'test_completed';
  static const String TEST_FAILED = 'test_failed';
  static const String RESULT_VIEWED = 'result_viewed';
  static const String RESULT_SHARED = 'result_shared';
  static const String HISTORY_VIEWED = 'history_viewed';
  static const String STATS_VIEWED = 'stats_viewed';
}

// ========== SAMPLE DATA FOR TESTING ==========
class SampleData {
  static const List<Map<String, dynamic>> SAMPLE_RESULTS = [
    {
      'download': 87.5,
      'upload': 42.3,
      'ping': 22,
      'jitter': 2.1,
      'location': 'Bamako, Mali',
      'network': 'WiFi',
    },
    {
      'download': 75.2,
      'upload': 38.1,
      'ping': 25,
      'jitter': 3.2,
      'location': 'Bamako, Mali',
      'network': '4G',
    },
  ];
}
