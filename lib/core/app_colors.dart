import 'package:flutter/material.dart';

/// Central color palette for the volcanic / obsidian visual theme.
class AppColors {
  AppColors._();

  static const Color emberOrange = Color(0xFFFF6A1A);
  static const Color emberYellow = Color(0xFFFFC93C);
  static const Color lavaRed = Color(0xFFE8380D);
  static const Color obsidianDark = Color(0xFF0B0A0C);
  static const Color obsidianPanel = Color(0xFF1A1416);
  static const Color obsidianPanelLight = Color(0xFF2A2023);
  static const Color ashGrey = Color(0xFF6E6669);
  static const Color textPrimary = Color(0xFFFDEEDC);
  static const Color textSecondary = Color(0xFFC9B9AE);

  static const LinearGradient emberGradient = LinearGradient(
    colors: [emberYellow, emberOrange, lavaRed],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const RadialGradient backdropGlow = RadialGradient(
    colors: [Color(0xFF3A1408), Color(0xFF0B0A0C)],
    center: Alignment.center,
    radius: 1.2,
  );
}
