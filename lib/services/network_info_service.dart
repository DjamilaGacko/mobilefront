import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// État réseau à un instant donné.
///
/// Distingue deux notions volontairement séparées :
///  - [connectionType] : par où passe Internet *maintenant* (WiFi ou mobile) ;
///  - [cellularTech] / [simOperator] : la techno et l'opérateur de la **SIM**,
///    lisibles même quand Internet passe par le WiFi.
class NetworkStatus {
  /// 'WiFi', 'Mobile', 'Ethernet', 'Aucune', 'Web' ou 'Inconnu'.
  final String connectionType;

  /// Techno radio mobile : '2G'/'3G'/'4G'/'5G', ou null si indisponible.
  final String? cellularTech;

  /// Nom de l'opérateur de la SIM **portant les données**. null sur iOS 16+,
  /// sans SIM, ou si READ_PHONE_STATE n'est pas accordée.
  final String? simOperator;

  /// Emplacement physique de cette SIM : 0 = SIM 1, 1 = SIM 2. null si inconnu.
  /// Permet de vérifier sur le terrain que c'est bien la bonne SIM qui a servi.
  final int? simSlot;

  /// Puissance du signal de référence, en dBm. 4G et 5G uniquement.
  final int? rsrp;

  /// Qualité du signal de référence, en dB. 4G et 5G uniquement.
  final int? rsrq;

  /// Puissance générale, toutes technologies, en dBm.
  final int? signalDbm;

  const NetworkStatus({
    required this.connectionType,
    this.cellularTech,
    this.simOperator,
    this.simSlot,
    this.rsrp,
    this.rsrq,
    this.signalDbm,
  });

  bool get isWifi => connectionType == 'WiFi';

  /// Badge réseau affiché et stocké : 'WiFi' en WiFi, sinon la techno mobile.
  String get networkBadge =>
      isWifi ? 'WiFi' : (cellularTech ?? connectionType);

  /// Vrai si des informations radio mobiles ont été lues.
  bool get hasCellular =>
      cellularTech != null || (simOperator?.isNotEmpty ?? false);

  /// ISS-03 : la mesure porte-t-elle réellement sur le réseau mobile ?
  ///
  /// En Wi-Fi, la SIM reste enregistrée sur son réseau et continue de fournir
  /// techno, opérateur et niveau de signal. Ces valeurs sont réelles, mais
  /// elles ne décrivent PAS ce que le test a mesuré. Elles ne doivent donc
  /// jamais être présentées comme le réseau utilisé pour le test.
  bool get cellularCarriedTest => !isWifi && hasCellular;

  @override
  String toString() => 'NetworkStatus($connectionType, tech=$cellularTech, '
      'sim=$simOperator, slot=$simSlot, rsrp=$rsrp, rsrq=$rsrq)';
}

/// Service d'information réseau : type de connexion (connectivity_plus) +
/// opérateur SIM et techno radio (canal natif [_channel]).
class NetworkInfoService {
  final logger = Logger();
  final Connectivity _connectivity = Connectivity();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  // Repli MCC/MNC → nom d'opérateur, utilisé uniquement quand le nom natif est
  // vide. Le nom fourni par le système reste la source principale. Limité au
  // Burkina Faso (pays de déploiement) pour éviter des libellés erronés.
  static const Map<String, String> operatorsByMccMnc = {
    '61301': 'Telmob (Onatel)', // MCC 613 = Burkina Faso
    '61302': 'Orange Burkina Faso',
    '61303': 'Telecel Faso',
  };

  /// Récupère l'état réseau complet.
  Future<NetworkStatus> getStatus() async {
    if (kIsWeb) {
      return const NetworkStatus(connectionType: 'Web');
    }

    final connectionType = await _connectionType();

    String? cellularTech;
    String? simOperator;

    // Sur Android, on s'assure d'avoir la permission avant de lire.
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<bool>('requestPhonePermission');
      } catch (_) {
        // Permission non demandable : lecture en mode dégradé.
      }
    }

    int? simSlot;
    int? rsrp;
    int? rsrq;
    int? signalDbm;

    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('getTelephony');
      if (info != null) {
        cellularTech = (info['cellularTech'] as String?)?.trim();
        if (cellularTech != null && cellularTech.isEmpty) cellularTech = null;

        simOperator = (info['simOperator'] as String?)?.trim();
        final mccMnc = (info['mccMnc'] as String?)?.trim();
        // Beaucoup de téléphones ne provisionnent pas le nom commercial et
        // renvoient le code MCC+MNC à la place. Envoyé tel quel, « 61301 » se
        // retrouverait traité comme un opérateur à part entière dans toutes les
        // statistiques — c'est ce qu'on observe déjà en base.
        simOperator = _resolveOperator(simOperator, mccMnc);

        simSlot = (info['simSlot'] as num?)?.toInt();
        rsrp = (info['rsrp'] as num?)?.toInt();
        rsrq = (info['rsrq'] as num?)?.toInt();
        signalDbm = (info['signalDbm'] as num?)?.toInt();
      }
    } on MissingPluginException {
      // Canal natif absent (ex. tests) : on reste sur le type de connexion.
    } catch (e) {
      logger.w('Lecture téléphonie échouée: $e');
    }

    final status = NetworkStatus(
      connectionType: connectionType,
      cellularTech: cellularTech,
      simOperator: simOperator,
      simSlot: simSlot,
      rsrp: rsrp,
      rsrq: rsrq,
      signalDbm: signalDbm,
    );
    logger.i('📶 $status');
    return status;
  }

  Future<String> _connectionType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      // connectivity_plus 6.x renvoie une liste ; on prend le lien actif.
      if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'Mobile';
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.none)) return 'Aucune';
      return 'Inconnu';
    } catch (e) {
      logger.e('Erreur détection connexion: $e');
      return 'Inconnu';
    }
  }

  String? _operatorFromMccMnc(String? mccMnc) {
    if (mccMnc == null || mccMnc.isEmpty) return null;
    return operatorsByMccMnc[mccMnc];
  }

  /// Nom d'opérateur exploitable, ou null si rien n'est déterminable.
  ///
  /// [reported] est le nom remonté par le système : il est parfois vide,
  /// parfois égal au code MCC+MNC lui-même. Dans ces deux cas on retombe sur la
  /// table locale, seule source d'un libellé lisible. Sans cette normalisation,
  /// « 61301 » apparaît comme un opérateur distinct dans les statistiques.
  String? _resolveOperator(String? reported, String? mccMnc) {
    final known = _operatorFromMccMnc(mccMnc);
    if (reported == null || reported.isEmpty) return known;
    // Un nom entièrement numérique est un code, pas un nom commercial.
    if (RegExp(r'^\d+$').hasMatch(reported)) return known ?? reported;
    return reported;
  }

  // ── Compatibilité : anciens appels ponctuels ────────────────────────────────

  /// Badge réseau (WiFi / 4G / …). Conserve l'ancienne signature.
  Future<String?> getNetworkType() async => (await getStatus()).networkBadge;
}
