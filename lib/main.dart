import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/test_selection.dart';
import 'screens/account_screen.dart';
import 'screens/coverage_screen.dart';
import 'screens/data_usage_screen.dart';
import 'screens/full_test_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/permissions_screen.dart';
import 'services/account_service.dart';
import 'services/local_storage_service.dart';
import 'services/settings_service.dart';
import 'services/test_reminder_service.dart';
import 'theme/yele_theme.dart';

/// Permet d'ouvrir un écran depuis l'extérieur de l'arbre de widgets —
/// ici, à l'appui sur un rappel alors que l'application est déjà lancée.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalStorageService().initialize();
  } catch (_) {
    // Le stockage local n'est pas bloquant pour lancer un test.
  }

  // Avant runApp : sinon les valeurs par défaut s'appliqueraient le temps du
  // premier affichage, et l'écran de test s'ouvrirait avec le mauvais style.
  await Settings.initialize();

  // Compte mémorisé (IMP-03) : restauré sans réseau pour que l'application
  // démarre hors connexion, puis revérifié en arrière-plan.
  AccountService.instance.restore();
  AccountService.instance.refresh();

  final reminders = TestReminderService();
  await reminders.initialize(onSelect: (route) {
    if (route != null) navigatorKey.currentState?.pushNamed(route);
  });

  // Application fermée et relancée par un appui sur le rappel : on ouvre
  // directement l'écran de test au lieu de l'accueil.
  final launchRoute =
      await reminders.routeFromLaunch() ?? await _nativeLaunchRoute();

  // Notification native (seuil de données, débit en direct) touchée alors
  // que l'application était déjà ouverte.
  _telephony.setMethodCallHandler((call) async {
    if (call.method == 'openRoute' && call.arguments is String) {
      navigatorKey.currentState?.pushNamed(call.arguments as String);
    }
  });

  // Priorité au rappel touché par l'utilisateur ; à défaut, le test qu'il a
  // choisi comme test par défaut.
  runApp(YeleApp(initialRoute: launchRoute ?? Settings.defaultTest.route));
}

const _telephony = MethodChannel('com.yele/telephony');

/// Écran demandé par une notification native (IMP-09) qui a lancé
/// l'application.
Future<String?> _nativeLaunchRoute() async {
  try {
    return await _telephony.invokeMethod<String>('takeLaunchRoute');
  } catch (_) {
    return null; // iOS : pas de notification native
  }
}

class YeleApp extends StatelessWidget {
  final String initialRoute;
  const YeleApp({super.key, this.initialRoute = '/full'});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yélé',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      initialRoute: initialRoute,
      routes: {
        '/full': (_) => const FullTestScreen(
              selection: TestSelection.all(),
              title: 'Test complet',
              route: '/full',
              launchLabel: 'LANCER LE\nTEST COMPLET',
            ),
        '/speed': (_) => const FullTestScreen(
              selection: TestSelection(speed: true),
              title: 'Speed test',
              route: '/speed',
              launchLabel: 'LANCER LE\nSPEEDTEST',
            ),
        '/browsing': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, browsing: true),
              title: 'Test de navigation',
              route: '/browsing',
              launchLabel: 'LANCER LE\nTEST NAVIGATION',
            ),
        '/streaming': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, streaming: true),
              title: 'Test de streaming',
              route: '/streaming',
              launchLabel: 'LANCER LE\nTEST STREAMING',
            ),
        '/history': (_) => const HistoryScreen(),
        '/coverage': (_) => const CoverageScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/account': (_) => const AccountScreen(),
        '/data': (_) => const DataUsageScreen(),
        '/permissions': (_) => const PermissionsScreen(),
      },
    );
  }
}
