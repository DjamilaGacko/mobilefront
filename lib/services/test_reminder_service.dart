import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/config.dart';

/// Rappels périodiques invitant l'utilisateur à lancer un test.
///
/// **Rien ne tourne** entre deux rappels : l'échéance est déposée auprès du système (AlarmManager sur
/// Android, centre de notifications sur iOS), qui réveille l'utilisateur au
/// moment voulu. L'application dort complètement d'ici là — aucune batterie,
/// aucune donnée consommée.
class TestReminderService {
  final logger = Logger();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Identifiant du rappel récurrent. Fixe : replanifier avec le même
  /// identifiant remplace l'échéance précédente au lieu d'en empiler une
  /// seconde — c'est ce qui évite les notifications en double.
  static const int _reminderId = 9001;

  static const String _channelId = 'yele_reminders';

  /// Route ouverte au toucher de la notification. Le speedtest seul plutôt que
  /// le test complet : à cette cadence, un test complet consommerait plusieurs
  /// centaines de mégaoctets par jour.
  static const String reminderRoute = '/speed';

  static bool _initialized = false;

  /// La planification passe par des API système absentes du web.
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Prépare le plugin et la base de fuseaux horaires.
  ///
  /// [onSelect] reçoit la charge utile lorsque l'utilisateur touche la
  /// notification ; c'est par là que l'application ouvre l'écran de test.
  Future<void> initialize({void Function(String? payload)? onSelect}) async {
    if (!isSupported || _initialized) return;

    // Le plugin refuse un DateTime brut et impose une heure localisée : sans
    // cette initialisation, toute planification échoue.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(REMINDER_TIMEZONE));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Les autorisations sont demandées explicitement à l'activation,
          // pas au premier lancement de l'application.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onSelect?.call(response.payload),
    );
    _initialized = true;
  }

  /// Demande l'autorisation d'afficher des notifications.
  /// Android 13+ et iOS l'exigent ; en dessous, elle est acquise d'office.
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await initialize();

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  /// Active les rappels. Retourne false si l'utilisateur refuse la
  /// notification — sans elle, le rappel ne s'afficherait jamais.
  Future<bool> enable() async {
    if (!isSupported) return false;
    if (!await requestPermission()) {
      logger.w('Rappels : autorisation de notification refusée');
      return false;
    }

    await _plugin.periodicallyShowWithDuration(
      _reminderId,
      'Yélé — c\'est le moment de mesurer',
      'Lancez un test pour enrichir la carte de couverture.',
      const Duration(hours: REMINDER_INTERVAL_HOURS),
      _details(),
      // Volontairement INEXACT : depuis Android 12, la planification à la
      // minute près exige SCHEDULE_EXACT_ALARM, que Google réserve aux
      // réveils, agendas et rappels de médicaments. Un rappel de test n'entre
      // dans aucune de ces catégories et la demande serait refusée à la
      // publication. Le rappel peut donc arriver avec quelques dizaines de
      // minutes de décalage — sans conséquence pour cet usage.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminderRoute,
    );

    logger.i('Rappels activés — toutes les $REMINDER_INTERVAL_HOURS heures');
    return true;
  }

  /// Annule les rappels. L'échéance est retirée du système.
  Future<void> disable() async {
    if (!isSupported) return;
    await initialize();
    await _plugin.cancel(_reminderId);
    logger.i('Rappels désactivés');
  }

  /// Vrai si un rappel est effectivement en attente auprès du système.
  ///
  /// On interroge le système plutôt qu'un drapeau local : c'est la seule
  /// source de vérité, l'échéance pouvant avoir été perdue (réinstallation,
  /// nettoyage par le constructeur).
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((r) => r.id == _reminderId);
  }

  /// Récupère la route à ouvrir lorsque l'application a été lancée par un
  /// appui sur la notification alors qu'elle était fermée.
  Future<String?> routeFromLaunch() async {
    if (!isSupported) return null;
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Rappels de test',
          channelDescription:
              'Invitation périodique à lancer un test de qualité réseau',
          // IMPORTANCE_DEFAULT : la notification apparaît dans le volet sans
          // s'imposer par-dessus ce que fait l'utilisateur.
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
}
