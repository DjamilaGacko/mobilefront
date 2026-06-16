import 'package:flutter/material.dart';

// ========== COULEURS ==========
const Color colorGreen700 = Color(0xFF0a5c38);
const Color colorGreen600 = Color(0xFF0e7a4a);
const Color colorGreen500 = Color(0xFF12975c);
const Color colorGreen400 = Color(0xFF1db870);
const Color colorGreen100 = Color(0xFFd6f5e7);
const Color colorGreen50 = Color(0xFFf0faf5);

const Color colorLimeBrand = Color(0xFFa6e22e);
const Color colorGreenBrand = Color(0xFF0e7a4a);
const List<Color> gradientYele = [Color(0xFFa6e22e), Color(0xFF0e7a4a)];

const Color colorNeutral900 = Color(0xFF111827);
const Color colorNeutral800 = Color(0xFF1f2937);
const Color colorNeutral700 = Color(0xFF374151);
const Color colorNeutral600 = Color(0xFF4b5563);
const Color colorNeutral400 = Color(0xFF9ca3af);
const Color colorNeutral300 = Color(0xFFd1d5db);
const Color colorNeutral200 = Color(0xFFe5e7eb);
const Color colorNeutral100 = Color(0xFFf3f4f6);
const Color colorNeutral50 = Color(0xFFf9fafb);

const Color colorWhite = Color(0xFFffffff);
const Color colorAmber = Color(0xFFb45309);
const Color colorAmberBg = Color(0xFFfffbeb);
const Color colorBlue = Color(0xFF1d4ed8);
const Color colorBlueBg = Color(0xFFeff6ff);
const Color colorRed = Color(0xFFdc2626);
const Color colorRedBg = Color(0xFFfef2f2);
const Color colorOrange = Color(0xFFea580c);
const Color colorOrangeBg = Color(0xFFfff7ed);

// ========== TEXTSTYLES ==========
TextStyle titleStyle({double size = 20, FontWeight weight = FontWeight.w700}) {
  return TextStyle(
    fontFamily: 'DMSerifDisplay',
    fontSize: size,
    fontWeight: weight,
    color: colorNeutral900,
  );
}

TextStyle bodyStyle({double size = 13, FontWeight weight = FontWeight.w400}) {
  return TextStyle(
    fontFamily: 'DMSans',
    fontSize: size,
    fontWeight: weight,
    color: colorNeutral900,
  );
}

TextStyle labelStyle({double size = 11, FontWeight weight = FontWeight.w600}) {
  return TextStyle(
    fontFamily: 'DMSans',
    fontSize: size,
    fontWeight: weight,
    color: colorNeutral400,
    letterSpacing: 0.04,
  );
}

// ========== API CONSTANTS ==========
// Base URL sans /api car speedtest-go n'utilise pas ce préfixe
const String API_BASE_URL = 'https://mobiletest-j0c6.onrender.com';
const int API_TIMEOUT = 300000; // 5 minutes
