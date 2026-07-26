import 'package:arisers/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Reusable App TextField widget with consistent styling & input action support.
class CustomTextField extends StatelessWidget {
  const CustomTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.suffixIcon,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool enabled;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, color: AppColors.primary),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
      ),
    );
  }
}
