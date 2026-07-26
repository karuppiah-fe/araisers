import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/auth/views/first_page.dart';
import 'package:arisers/features/bluetooth_setup/views/bluetooth_page.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';

class SettingsBottomSheet extends ConsumerWidget {
  const SettingsBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLanguage = ref.watch(localeProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                const Icon(Icons.settings, color: AppColors.primary),
                const SizedBox(width: 10),
                Text(
                  Words.get('settings', activeLanguage),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Language Selector Section
            Text(
              Words.get('language', activeLanguage),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            Card(
              elevation: 0,
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: AppLanguage.values.map((lang) {
                  final isSelected = lang == activeLanguage;
                  return RadioListTile<AppLanguage>(
                    title: Text(
                      '${lang.nativeName} (${lang.englishName})',
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    value: lang,
                    groupValue: activeLanguage,
                    activeColor: AppColors.primary,
                    onChanged: (newLang) {
                      if (newLang != null) {
                        ref.read(localeProvider.notifier).setLanguage(newLang);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Bluetooth Reconfigure Section
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bluetooth, color: AppColors.primary),
              ),
              title: Text(
                Words.get('reconfig_device', activeLanguage),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BluetoothPage(),
                  ),
                );
              },
            ),
            const Divider(),

            // Logout Section
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, color: AppColors.error),
              ),
              title: Text(
                Words.get('logout', activeLanguage),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.error,
                ),
              ),
              onTap: () {
                _showLogoutConfirmation(context, ref, activeLanguage);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(
    BuildContext context,
    WidgetRef ref,
    AppLanguage activeLanguage,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Words.get('logout', activeLanguage)),
        content: Text(Words.get('logout_confirm', activeLanguage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Words.get('cancel', activeLanguage)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FirstPage(),
                  ),
                  (route) => false,
                );
              }
            },
            child: Text(Words.get('confirm', activeLanguage)),
          ),
        ],
      ),
    );
  }
}
