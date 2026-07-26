import 'package:flutter/material.dart';

/// Centralized color palette for the Arisers application.
abstract class AppColors {
  // Brand Colors
  static const Color primary = Colors.lightGreen;
  static const Color primaryDark = Color(0xFF689F38);
  static const Color primaryLight = Color(0xFFAED581);

  // Gradient Colors
  static const Color gradientStart = Colors.lightGreen;
  static const Color gradientEnd = Color(0xFF7CB342);

  // Neutral Colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color cardBackground = Colors.white;
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF2C3E50);
  static const Color textSecondary = Color(0xFF7F8C8D);
  static const Color border = Color(0xFFE2E8F0);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);
}
