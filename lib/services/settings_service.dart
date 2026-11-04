import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../constants/config.dart';
import '../theme/yele_theme.dart';

/// Unité d'affichage des débits.
///
/// La mesure est toujours calculée en mégabits par seconde — c'est l'unité des
/// réseaux. Ce réglage ne change que la présentation : on convertit au dernier
/// moment, jamais la valeur stockée, sans quoi l'historique deviendrait
/// inexploitable après un changement d'unité.
enum SpeedUnit {
  megabits('Mb/s', 1, 2),
  megabytes('MB/s', 0.125, 2),
  kilobits('kb/s', 1000, 0);

  const SpeedUnit(this.label, this.factor, this.decimals);

  /// Libellé affiché à côté de la valeur.
  final String label;

  /// Facteur appliqué à une valeur exprimée en Mb/s.
  final double factor;

  /// Nombre de décimales pertinent pour cette unité.
  final int decimals;

  /// Convertit une valeur en Mb/s vers cette unité.
  double from(double mbps) => mbps * factor;

  /// Valeur formatée, sans l'unité.
  String value(double mbps) => from(mbps).toStringAsFixed(decimals);

  /// Valeur formatée suivie de l'unité.
  String format(double mbps) => '${value(mbps)} $label';
}

/// Habillage de l'écran de test.
enum TestStyle {
  vert('Vert', YeleColors.testGradient, YeleColors.testBot),
  bleu('Bleu', YeleColors.blueGradient, YeleColors.blueRing),
  sombre('Sombre', YeleColors.darkGradient, YeleColors.darkRing);

  const TestStyle(this.label, this.gradient, this.ring);

  final String label;
  final LinearGradient gradient;

  /// Couleur de l'anneau de la jauge et des accents, pour rester lisible sur
  /// le dégradé correspondant.
  final Color ring;
}

/// Test proposé au lancement de l'application.
enum DefaultTest {
  full('/full', 'Test complet'),
  speed('/speed', 'Speed test'),
  streaming('/streaming', 'Test de streaming'),
  browsing('/browsing', 'Test de navigation');

  const DefaultTest(this.route, this.label);

  final String route;
  final String label;
}

/// Réglages de l'application, persistés d'un lancement à l'autre.
///
/// Les options étaient auparavant du texte figé : l'utilisateur voyait
/// « Unité de débit : Mb/s » sans pouvoir y toucher. Elles sont désormais
/// stockées dans une boîte Hive dédiée (distincte de celle des résultats) et
/// relues au démarrage.

class Settings {
  static final _logger = Logger();
  static Box? _box;

  static const _kDefaultTest = 'defaultTest';
  static const _kSpeedUnit = 'speedUnit';
  static const _kTestStyle = 'testStyle';

  /// Ouvre la boîte de réglages. À appeler avant `runApp`, sans quoi les
  /// valeurs par défaut s'appliqueraient le temps du premier affichage.
  static Future<void> initialize() async {
    if (_box?.isOpen ?? false) return;
    try {
      _box = await Hive.openBox(StorageConfig.SETTINGS_BOX_NAME);
    } catch (e) {
      // Réglages inaccessibles : l'application reste utilisable avec les
      // valeurs par défaut, un test ne doit pas être empêché pour si peu.
      _logger.e('Réglages indisponibles, valeurs par défaut utilisées: $e');
    }
  }

  static T _read<T>(String key, List<T> values, T fallback) {
    final raw = _box?.get(key);
    if (raw == null) return fallback;
    for (final v in values) {
      if ((v as Enum).name == raw) return v;
    }
    return fallback;
  }

  static Future<void> _write(String key, Enum value) async {
    try {
      await _box?.put(key, value.name);
    } catch (e) {
      _logger.w('Enregistrement du réglage $key échoué: $e');
    }
  }

  // ── Test par défaut ─────────────────────────────────────────────────────────

  static DefaultTest get defaultTest =>
      _read(_kDefaultTest, DefaultTest.values, DefaultTest.full);

  static Future<void> setDefaultTest(DefaultTest v) =>
      _write(_kDefaultTest, v);

  // ── Unité de débit ──────────────────────────────────────────────────────────

  static SpeedUnit get speedUnit =>
      _read(_kSpeedUnit, SpeedUnit.values, SpeedUnit.megabits);

  static Future<void> setSpeedUnit(SpeedUnit v) => _write(_kSpeedUnit, v);

  // ── Style de l'écran de test ────────────────────────────────────────────────

  static TestStyle get testStyle =>
      _read(_kTestStyle, TestStyle.values, TestStyle.vert);

  static Future<void> setTestStyle(TestStyle v) => _write(_kTestStyle, v);

  // ── Identifiant d'appareil de repli (IMP-15) ────────────────────────────────

  static const _kDeviceId = 'deviceId';

  /// Identifiant tiré au hasard puis conservé, pour les appareils dont
  /// l'identifiant système est illisible. Contrairement à celui dérivé
  /// d'Android, il ne survit pas à une désinstallation.
  static Future<String> fallbackDeviceId() async {
    final stored = _box?.get(_kDeviceId);
    if (stored is String && stored.isNotEmpty) return stored;
    final created = const Uuid().v4();
    try {
      await _box?.put(_kDeviceId, created);
    } catch (e) {
      _logger.w('Enregistrement de l\'identifiant d\'appareil échoué: $e');
    }
    return created;
  }

  // ── Valeurs libres (compte, consommation data) ──────────────────────────────

  static dynamic readValue(String key) => _box?.get(key);

  /// Enregistre une valeur ; null l'efface.
  static Future<void> writeValue(String key, Object? value) async {
    try {
      if (value == null) {
        await _box?.delete(key);
      } else {
        await _box?.put(key, value);
      }
    } catch (e) {
      _logger.w('Enregistrement de $key échoué: $e');
    }
  }
}
