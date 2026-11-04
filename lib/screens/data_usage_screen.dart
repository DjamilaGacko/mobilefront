import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/data_usage_service.dart';
import '../services/traffic_stats_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// Écran « Consommation data » (IMP-09) : cumul du mois, seuil mensuel avec
/// alerte, débit en direct dans la barre d'état.
class DataUsageScreen extends StatefulWidget {
  const DataUsageScreen({super.key});

  @override
  State<DataUsageScreen> createState() => _DataUsageScreenState();
}

class _DataUsageScreenState extends State<DataUsageScreen>
    with WidgetsBindingObserver {
  final _service = DataUsageService();
  DataUsageSnapshot? _s;
  bool _live = false;

  static const _gb = 1000 * 1000 * 1000;
  static const _presets = [0, _gb ~/ 2, _gb, 2 * _gb, 5 * _gb, 10 * _gb, 20 * _gb];
  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _service.checkLimit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour depuis les réglages du système : l'accès aux données
  /// d'utilisation vient peut-être d'être accordé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await _service.snapshot();
    final live = await _service.isLiveMonitorOn();
    if (!mounted) return;
    setState(() {
      _s = s;
      _live = live;
    });
  }

  String _fmt(int bytes) => TrafficStatsService.formatBytes(bytes);

  String _limitLabel(int bytes) => bytes == 0 ? 'Aucun' : _fmt(bytes);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return YeleScaffold(
      title: 'Consommation data',
      route: '/data',
      body: Container(
        color: YeleColors.panel,
        child: s == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  children: [
                    _hero(s),
                    if (_service.isAndroid && !s.usageAccess) ...[
                      const SizedBox(height: 12),
                      _accessCard(),
                    ],
                    const SizedBox(height: 16),
                    if (_service.isAndroid) _settings(s) else _iosNote(),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Cumul du mois ───────────────────────────────────────────────────────────

  Widget _hero(DataUsageSnapshot s) {
    final ratio = s.ratio;
    final color = ratio == null
        ? YeleColors.primary
        : ratio >= 1
            ? YeleColors.danger
            : ratio >= 0.8
                ? YeleColors.warn
                : YeleColors.primary;
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: Column(
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: (ratio ?? 0).clamp(0.0, 1.0),
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: YeleColors.panel2,
                  color: color,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fmt(s.usedBytes),
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: ratio != null && ratio >= 1
                                  ? YeleColors.danger
                                  : YeleColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                          s.limitBytes > 0
                              ? 'sur ${_fmt(s.limitBytes)}'
                              : 'ce mois-ci',
                          style: const TextStyle(
                              fontSize: 14, color: YeleColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
              'Depuis le 1er ${_months[s.monthStart.month - 1]} · '
              '${s.coversWholePhone ? 'données mobiles du téléphone' : 'tests Yélé uniquement'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: YeleColors.muted)),
          if (s.coversWholePhone) ...[
            const SizedBox(height: 4),
            Text('Dont tests Yélé : ${_fmt(s.yeleBytes)}',
                style: const TextStyle(fontSize: 13, color: YeleColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _accessCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: YeleColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Suivre tout le téléphone',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: YeleColors.ink)),
          const SizedBox(height: 4),
          const Text(
              'Autorisez l\'« accès aux données d\'utilisation » pour compter '
              'toutes les applications, et pas seulement les tests Yélé.',
              style: TextStyle(
                  fontSize: 13, color: YeleColors.ink, height: 1.4)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _service.openUsageAccessSettings,
              child: const Text('Autoriser'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Réglages ────────────────────────────────────────────────────────────────

  Widget _settings(DataUsageSnapshot s) {
    return _Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: YeleColors.primary),
            title: const Text('Seuil mensuel'),
            subtitle: const Text('Alerte à 80 % puis au dépassement'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_limitLabel(s.limitBytes),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: YeleColors.ink)),
                const Icon(Icons.chevron_right, color: YeleColors.muted),
              ],
            ),
            onTap: () => _pickLimit(s.limitBytes),
          ),
          const Divider(height: 1, indent: 56),
          SwitchListTile(
            secondary:
                const Icon(Icons.speed, color: YeleColors.primary),
            title: const Text('Débit en direct'),
            subtitle: const Text('Affiché en permanence dans la barre d\'état'),
            value: _live,
            activeThumbColor: YeleColors.primary,
            onChanged: (on) async {
              final ok = await _service.setLiveMonitor(on);
              if (!mounted) return;
              setState(() => _live = ok);
              if (on && !ok) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Autorisez les notifications pour afficher le débit.')));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _iosNote() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
          'Sur iPhone, le système ne permet de compter que les données des '
          'tests Yélé ; le seuil mensuel et le débit en direct ne sont '
          'disponibles que sur Android.',
          style: TextStyle(fontSize: 13, color: YeleColors.muted, height: 1.4)),
    );
  }

  Future<void> _pickLimit(int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Seuil mensuel',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              for (final v in _presets)
                ListTile(
                  title: Text(_limitLabel(v)),
                  trailing: v == current
                      ? const Icon(Icons.check, color: YeleColors.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, v),
                ),
              ListTile(
                title: const Text('Autre…'),
                trailing: !_presets.contains(current)
                    ? const Icon(Icons.check, color: YeleColors.primary)
                    : null,
                onTap: () async {
                  final custom = await _customLimit(ctx);
                  if (custom != null && ctx.mounted) Navigator.pop(ctx, custom);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _service.setLimit(picked);
    await _refresh();
  }

  /// Saisie libre, en Go : les forfaits ne tombent pas tous sur un palier.
  Future<int?> _customLimit(BuildContext ctx) {
    final input = TextEditingController();
    return showDialog<int>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Seuil mensuel'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: const InputDecoration(suffixText: 'Go', hintText: '1,5'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              final go = double.tryParse(input.text.replaceAll(',', '.'));
              Navigator.pop(
                  d, go == null || go <= 0 ? null : (go * _gb).round());
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: YeleColors.line),
      ),
      child: child,
    );
  }
}
