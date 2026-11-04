import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../constants/config.dart';
import '../services/device_info_service.dart';
import '../services/settings_service.dart';
import '../services/test_reminder_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _reminders = TestReminderService();
  final Future<String> _deviceId = DeviceInfoService().getAnonymousDeviceId();
  bool _remindersOn = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshReminders();
  }

  // L'état est relu auprès du système, seule source de vérité : une échéance
  // peut avoir été supprimée sans que l'application en soit informée.
  Future<void> _refreshReminders() async {
    final on = await _reminders.isEnabled();
    if (!mounted) return;
    setState(() => _remindersOn = on);
  }

  Future<void> _toggleReminders(bool value) async {
    setState(() => _busy = true);
    if (value) {
      final ok = await _reminders.enable();
      if (!ok && mounted) {
        _snack('Autorisez les notifications pour recevoir les rappels.');
      }
    } else {
      await _reminders.disable();
    }
    await _refreshReminders();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Réglages',
      route: '/settings',
      body: Container(
        color: YeleColors.panel,
        child: ListView(
          children: [
            _section('Général'),
            _choice<DefaultTest>(
              'Test par défaut au démarrage',
              DefaultTest.values,
              Settings.defaultTest,
              (v) => v.label,
              (v) async {
                await Settings.setDefaultTest(v);
                _snack("Appliqué au prochain lancement de l'application.");
              },
            ),
            _choice<SpeedUnit>(
              'Unité de débit',
              SpeedUnit.values,
              Settings.speedUnit,
              (v) => v.label,
              Settings.setSpeedUnit,
            ),
            _choice<TestStyle>(
              "Style de l'écran de test",
              TestStyle.values,
              Settings.testStyle,
              (v) => v.label,
              Settings.setTestStyle,
            ),
            _section('Autorisations'),
            _link(
              "Permissions de l'application",
              'Consulter les autorisations nécessaires et leur état',
              () => Navigator.of(context).pushNamed('/permissions'),
            ),
            if (_reminders.isSupported) ...[
              _section('Rappels de test'),
              _toggle(
                'Me rappeler de tester',
                'Une notification toutes les $REMINDER_INTERVAL_HOURS heures, '
                    'de jour comme de nuit',
                _remindersOn,
                _busy ? null : _toggleReminders,
              ),
            ],
            _section("Identifiant de l'appareil"),
            _deviceIdTile(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// IMP-15 : affiché pour pouvoir vérifier, avant et après une réinstallation,
  /// que l'identifiant ne change pas. Appui long pour le copier.
  Widget _deviceIdTile() {
    return FutureBuilder<String>(
      future: _deviceId,
      builder: (context, snap) {
        final id = snap.data ?? '…';
        return InkWell(
          onLongPress: snap.hasData
              ? () async {
                  await Clipboard.setData(ClipboardData(text: id));
                  _snack('Identifiant copié.');
                }
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(id,
                    style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: YeleColors.ink)),
                const SizedBox(height: 4),
                const Text(
                    'Identifiant anonyme, joint à chaque mesure pour relier '
                    'celles d\'un même appareil. Il ne contient aucune donnée '
                    'personnelle.',
                    style: TextStyle(fontSize: 13, color: YeleColors.muted)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Éléments de liste ─────────────────────────────────────────────────────

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
        child: Text(t,
            style: const TextStyle(
                color: YeleColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      );

  /// Réglage à choix multiple. La valeur courante est affichée sous le titre,
  /// et le choix se fait dans une feuille : un menu déroulant dans une liste de
  /// réglages passe mal sur un petit écran.
  Widget _choice<T>(
    String title,
    List<T> values,
    T current,
    String Function(T) label,
    Future<void> Function(T) onPick,
  ) {
    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                ...values.map((v) => ListTile(
                      title: Text(label(v)),
                      trailing: v == current
                          ? const Icon(Icons.check, color: YeleColors.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, v),
                    )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (picked == null) return;
        await onPick(picked);
        if (mounted) setState(() {}); // reflète la nouvelle valeur courante
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontSize: 16, color: YeleColors.ink)),
                  const SizedBox(height: 2),
                  Text(label(current),
                      style: const TextStyle(
                          fontSize: 13, color: YeleColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: YeleColors.muted),
          ],
        ),
      ),
    );
  }

  /// Ligne renvoyant vers un autre écran.
  Widget _link(String title, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontSize: 16, color: YeleColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 13, color: YeleColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: YeleColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
      String title, String sub, bool value, ValueChanged<bool>? onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, color: YeleColors.ink)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        const TextStyle(fontSize: 13, color: YeleColors.muted)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: YeleColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
