import 'package:flutter/material.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useGps = true;

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
            _item('Langue', 'Auto'),
            _item('Test par défaut au démarrage', 'Test complet'),
            _item('Unité de débit', 'Mb/s'),
            _item('Style de fond', 'Vert'),
            _toggle('Utiliser le GPS',
                'Active/désactive la géolocalisation des tests', _useGps,
                (v) => setState(() => _useGps = v)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
        child: Text(t,
            style: const TextStyle(
                color: YeleColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      );

  Widget _item(String title, String sub) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 16, color: YeleColors.ink)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(fontSize: 13, color: YeleColors.muted)),
          ],
        ),
      );

  Widget _toggle(
      String title, String sub, bool value, ValueChanged<bool> onChanged) {
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
            activeColor: YeleColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
