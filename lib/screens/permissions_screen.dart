import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../services/location_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// État d'une autorisation, tel qu'affiché à l'utilisateur.
enum _State { granted, denied, unavailable }

class _Entry {
  final String title;
  final String why;
  final _State state;
  const _Entry(this.title, this.why, this.state);
}

/// Écran de consultation des permissions (IMP-04).
///
/// Les autorisations étaient demandées au fil de l'usage, sans qu'aucun écran
/// ne récapitule lesquelles sont nécessaires ni où elles en sont. Cet écran ne
/// demande rien de lui-même : il ne fait que refléter l'état du système et
/// renvoyer vers ses réglages, seul endroit où une autorisation refusée
/// définitivement peut être rétablie.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  final _location = LocationService();
  List<_Entry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final entries = <_Entry>[];

    // ── Localisation ─────────────────────────────────────────────────────────
    // Deux conditions distinctes : le service du téléphone doit être allumé ET
    // l'application autorisée. On les présente séparément, sinon l'utilisateur
    // ne sait pas laquelle des deux corriger.
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      entries.add(_Entry(
        'Service de localisation',
        'Doit être activé sur le téléphone pour situer chaque mesure.',
        serviceOn ? _State.granted : _State.denied,
      ));
      final perm = await Geolocator.checkPermission();
      final ok = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      entries.add(_Entry(
        'Accès à la position',
        'Géolocalise chaque mesure. Sans elle, les tests sont bloqués.',
        ok ? _State.granted : _State.denied,
      ));
    } catch (_) {
      entries.add(const _Entry('Accès à la position',
          'Géolocalise chaque mesure.', _State.unavailable));
    }

    // ── Notifications ────────────────────────────────────────────────────────
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      bool? notif;
      try {
        notif = await FlutterLocalNotificationsPlugin()
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
      } catch (_) {
        notif = null;
      }
      entries.add(_Entry(
        'Notifications',
        'Nécessaire pour les rappels de test.',
        notif == null
            ? _State.unavailable
            : (notif ? _State.granted : _State.denied),
      ));
    }

    // ── État du téléphone ────────────────────────────────────────────────────
    if (!kIsWeb && Platform.isAndroid) {
      bool? phone;
      try {
        phone = await _channel.invokeMethod<bool>('checkPhonePermission');
      } catch (_) {
        phone = null;
      }
      entries.add(_Entry(
        'État du téléphone',
        'Lit l\'opérateur de la carte SIM et la technologie radio (2G à 5G).',
        phone == null
            ? _State.unavailable
            : (phone ? _State.granted : _State.denied),
      ));
    }

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final missing = _entries.any((e) => e.state == _State.denied);
    return YeleScaffold(
      title: 'Permissions',
      route: '/permissions',
      body: Container(
        color: YeleColors.panel,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
              child: Text(
                missing
                    ? 'Certaines autorisations manquent : les mesures '
                        'correspondantes ne seront pas enregistrées.'
                    : 'Toutes les autorisations nécessaires sont accordées.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: missing ? const Color(0xFFB85C0E) : YeleColors.muted,
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: CircularProgressIndicator(color: YeleColors.primary),
                ),
              )
            else
              ..._entries.map(_tile),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: () => _location.openAppSettings(),
                    child: const Text('Réglages du système'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Actualiser'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 28),
              child: Text(
                'Les autorisations se modifient depuis les réglages du '
                'téléphone. Revenez ensuite ici et touchez « Actualiser ».',
                style: TextStyle(fontSize: 12, color: YeleColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(_Entry e) {
    final (icon, color, label) = switch (e.state) {
      _State.granted => (Icons.check_circle, YeleColors.good, 'Accordée'),
      _State.denied => (Icons.cancel, YeleColors.danger, 'Refusée'),
      _State.unavailable => (Icons.help, YeleColors.muted, 'Indéterminée'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        fontSize: 15.5, color: YeleColors.ink)),
                const SizedBox(height: 2),
                Text(e.why,
                    style: const TextStyle(
                        fontSize: 12.5, color: YeleColors.muted, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
