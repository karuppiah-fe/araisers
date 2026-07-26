import 'package:arisers/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Common UI utilities and helpers.
abstract class UIHelpers {
  /// Displays a floating SnackBar with standardized styling.
  static void showSnackBar(
    BuildContext context, {
    required String message,
    Color color = AppColors.primary,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Cleans raw exception messages for clean UI display.
  static String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('TimeoutException: ', '')
        .replaceFirst('FirebaseException: ', '');
  }
}
