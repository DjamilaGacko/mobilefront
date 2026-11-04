import 'package:flutter/material.dart';

import '../models/speed_test_result.dart';
import '../services/barometer_service.dart';
import '../services/settings_service.dart';
import '../theme/yele_theme.dart';

/// Baromètre (IMP-11) : où se situe ce résultat parmi les autres mesures, et
/// comment se classent les opérateurs.
///
/// Discret par construction : rien ne s'affiche tant que la comparaison n'est
/// pas prête, et la carte disparaît si le serveur ne répond pas — l'absence
/// de comparaison ne doit pas encombrer le bilan d'un message d'erreur.
class BarometerCard extends StatefulWidget {
  final SpeedTestResult result;
  const BarometerCard({super.key, required this.result});

  @override
  State<BarometerCard> createState() => _BarometerCardState();
}

class _BarometerCardState extends State<BarometerCard> {
  late final Future<Barometer?> _future =
      BarometerService().compare(widget.result);

  static const _maxOperators = 4;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Barometer?>(
      future: _future,
      builder: (context, snap) {
        final b = snap.data;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: b == null ? const SizedBox(width: double.infinity) : _card(b),
        );
      },
    );
  }

  Widget _card(Barometer b) {
    final pct = b.downloadPct;
    final who = b.network == 'wifi' ? 'mesures en Wi-Fi' : 'mesures mobiles';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VOTRE POSITION',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: YeleColors.muted)),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 15, color: YeleColors.ink),
              children: [
                const TextSpan(text: 'Plus rapide que '),
                TextSpan(
                    text: '$pct %',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _color(pct))),
                TextSpan(text: ' des $who'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _scale(pct),
          if (b.operatorName != null) ...[
            const SizedBox(height: 8),
            Text('Parmi les clients ${b.operatorName} : ${b.operatorPct} %',
                style: const TextStyle(fontSize: 13, color: YeleColors.muted)),
          ],
          if (b.operators.length >= 2) ...[
            const Divider(height: 26),
            const Text('Débit médian par opérateur',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: YeleColors.ink)),
            const SizedBox(height: 8),
            ..._operatorBars(b),
          ],
          const SizedBox(height: 8),
          Text('${b.count} mesures · ${b.days} derniers jours',
              style: const TextStyle(fontSize: 11, color: YeleColors.muted)),
        ],
      ),
    );
  }

  /// Échelle 0–100 % avec un repère sur la position.
  Widget _scale(int pct) {
    return LayoutBuilder(builder: (context, c) {
      final x = c.maxWidth * pct / 100;
      return SizedBox(
        height: 16,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 5,
              bottom: 5,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(colors: [
                    YeleColors.danger,
                    YeleColors.warn,
                    YeleColors.good,
                  ]),
                ),
              ),
            ),
            Positioned(
              left: (x - 8).clamp(0, c.maxWidth - 16),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: YeleColors.ink, width: 3),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Une barre par opérateur, et la vôtre pour comparer d'un coup d'œil.
  List<Widget> _operatorBars(Barometer b) {
    final unit = Settings.speedUnit;
    final mine = widget.result.downloadSpeed;
    final rows = <({String name, double value, bool you})>[
      for (final o in b.operators.take(_maxOperators))
        (name: o.name, value: o.medianDownload, you: false),
      (name: 'Vous', value: mine, you: true),
    ]..sort((a, z) => z.value.compareTo(a.value));
    final max = rows.map((r) => r.value).fold<double>(0.1, (a, v) => v > a ? v : a);

    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: Text(row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: row.you ? FontWeight.w800 : FontWeight.w500,
                        color: YeleColors.ink)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: row.value / max,
                    minHeight: 8,
                    backgroundColor: YeleColors.panel2,
                    color: row.you ? YeleColors.ink : YeleColors.primary,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(unit.value(row.value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: row.you ? FontWeight.w800 : FontWeight.w600,
                        color: YeleColors.ink)),
              ),
            ],
          ),
        ),
    ];
  }

  Color _color(int pct) {
    if (pct >= 66) return YeleColors.good;
    if (pct >= 33) return YeleColors.warn;
    return YeleColors.danger;
  }
}
