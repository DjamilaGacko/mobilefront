import 'package:flutter/material.dart';

/// Palette et styles repris de la maquette interactive Yélé.
class YeleColors {
  // Fonds & navigation (thème sombre)
  static const bg = Color(0xFF0E1726);
  static const header = Color(0xFF16213A);
  static const header2 = Color(0xFF1D2A47);
  static const drawerBg = Color(0xFF1B2030);

  // Marque
  static const primary = Color(0xFF0BB89C); // teal Yélé
  static const primaryDk = Color(0xFF089A83);
  static const accent = Color(0xFF19C3FF); // cyan data
  static const field = Color(0xFF0FA3DF); // bleu valeurs

  // Statuts
  static const good = Color(0xFF2BB673);
  static const warn = Color(0xFFF5A623);
  static const danger = Color(0xFFE0464B);

  // Écran de test (fond vert dégradé)
  static const testTop = Color(0xFFCFE86B);
  static const testMid = Color(0xFFA9DD3B);
  static const testBot = Color(0xFF7FC91F);
  static const scoreRing = Color(0xFF9AD11F);

  // Surfaces claires
  static const panel = Color(0xFFF3F5F7);
  static const panel2 = Color(0xFFE7EBEF);
  static const line = Color(0xFFDDE3EA);
  static const ink = Color(0xFF1B2333);
  static const muted = Color(0xFF7C8AA0);

  // Couleurs par technologie réseau
  static const g2 = Color(0xFF1F7AE0);
  static const g3 = Color(0xFF7AC943);
  static const g4 = Color(0xFFF5921E);
  static const g4p = Color(0xFFD2353A);
  static const g5 = Color(0xFF8A3FFC);

  static const testGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [testTop, testMid, testBot],
  );
}

ThemeData buildYeleTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: YeleColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YeleColors.primary,
      primary: YeleColors.primary,
      brightness: Brightness.light,
    ),
    fontFamily: 'Roboto',
  );
}
