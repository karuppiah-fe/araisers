import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/core/widgets/custom_button.dart';
import 'package:arisers/core/widgets/custom_text_field.dart';
import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/bluetooth_setup/views/bluetooth_page.dart';
import 'package:arisers/features/home/views/home_page.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PasswordPage extends ConsumerStatefulWidget {
  const PasswordPage({super.key});

  @override
  ConsumerState<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends ConsumerState<PasswordPage> {
  final TextEditingController passwordController = TextEditingController();

  bool hidePassword = true;
  bool isChecking = false;

  Future<void> submitPassword() async {
    FocusScope.of(context).unfocus();

    final String password = passwordController.text.trim();

    if (password.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter the password',
        color: AppColors.error,
      );
      return;
    }

    setState(() {
      isChecking = true;
    });

    try {
      final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);
      final String? userKey = sessionBox.get('userKey')?.toString();

      if (userKey != null && userKey.trim().isNotEmpty) {
        final DatabaseReference userRef = FirebaseDatabase.instance.ref(
          'arisers/$userKey/password',
        );
        final DataSnapshot snapshot = await userRef.get();
        if (snapshot.exists && snapshot.value != null) {
          final String savedPassword = snapshot.value.toString().trim();
          if (password != savedPassword) {
            throw Exception('Incorrect password. Please try again.');
          }
        }
      }

      final bool deviceAlreadyConfigured = await checkDeviceConfiguration();

      if (!mounted) return;

      if (deviceAlreadyConfigured) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const HomePage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const BluetoothPage()),
        );
      }
    } catch (error) {
      if (!mounted) return;
      UIHelpers.showSnackBar(
        context,
        message: UIHelpers.cleanError(error),
        color: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          isChecking = false;
        });
      }
    }
  }

  Future<bool> checkDeviceConfiguration() async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    final String? userKey = sessionBox.get('userKey')?.toString();

    if (userKey == null || userKey.trim().isEmpty) {
      throw Exception('User session was not found. Please log in again.');
    }

    final DatabaseReference deviceReference = FirebaseDatabase.instance.ref(
      'arisers/$userKey/deviceInfo',
    );

    // 1. Check if the current user already has valid deviceInfo in Firebase
    final DataSnapshot snapshot = await deviceReference.get();

    if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
      final Map<String, dynamic> deviceData = Map<String, dynamic>.from(
        snapshot.value as Map,
      );

      final bool configured = deviceData['configured'] == true;
      final String deviceName =
          deviceData['deviceName']?.toString().trim() ?? '';
      final String wifiSsid = deviceData['wifiSsid']?.toString().trim() ?? '';
      final int? phase = int.tryParse(deviceData['phase']?.toString() ?? '');
      final bool validPhase = phase == 1 || phase == 2 || phase == 3;

      if (configured &&
          deviceName.isNotEmpty &&
          wifiSsid.isNotEmpty &&
          validPhase) {
        await sessionBox.put('deviceConfigured', true);
        await sessionBox.put('deviceName', deviceName);
        await sessionBox.put('wifiSsid', wifiSsid);
        await sessionBox.put('phase', phase);
        return true;
      }
    }

    // 2. Fallback: If this user doesn't have deviceInfo yet in Firebase,
    // check if ANY user under 'arisers' already has a configured device!
    try {
      final DatabaseReference arisersRef = FirebaseDatabase.instance.ref(
        'arisers',
      );
      final DataSnapshot arisersSnapshot = await arisersRef.get();

      if (arisersSnapshot.exists &&
          arisersSnapshot.value != null &&
          arisersSnapshot.value is Map) {
        final Map<dynamic, dynamic> usersMap = Map<dynamic, dynamic>.from(
          arisersSnapshot.value as Map,
        );

        for (final entry in usersMap.entries) {
          final Object? userVal = entry.value;
          if (userVal is! Map) continue;

          final Map<dynamic, dynamic> userMap = Map<dynamic, dynamic>.from(
            userVal,
          );
          final Object? devInfoVal = userMap['deviceInfo'];

          if (devInfoVal is Map) {
            final Map<String, dynamic> devInfo = Map<String, dynamic>.from(
              devInfoVal,
            );

            final bool configured = devInfo['configured'] == true;
            final String deviceName =
                devInfo['deviceName']?.toString().trim() ?? '';
            final String wifiSsid =
                devInfo['wifiSsid']?.toString().trim() ?? '';
            final int? phase = int.tryParse(
              devInfo['phase']?.toString() ?? '',
            );
            final bool validPhase = phase == 1 || phase == 2 || phase == 3;

            if (configured &&
                deviceName.isNotEmpty &&
                wifiSsid.isNotEmpty &&
                validPhase) {
              await deviceReference.update({
                'deviceName': deviceName,
                'wifiSsid': wifiSsid,
                'phase': phase,
                'bluetoothName': devInfo['bluetoothName'] ?? 'arisers',
                'bluetoothType': devInfo['bluetoothType'] ?? 'classic',
                'configured': true,
                'updatedAt': ServerValue.timestamp,
              });

              await sessionBox.put('deviceConfigured', true);
              await sessionBox.put('deviceName', deviceName);
              await sessionBox.put('wifiSsid', wifiSsid);
              await sessionBox.put('phase', phase);

              return true;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking global device info in Firebase: $e');
    }

    await sessionBox.put('deviceConfigured', false);
    return false;
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeLanguage = ref.watch(localeProvider);
    final Size size = MediaQuery.sizeOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(Words.get('arisers', activeLanguage)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.06,
              vertical: size.height * 0.03,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Words.get('password', activeLanguage),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Words.get('enter_password', activeLanguage),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  CustomTextField(
                    controller: passwordController,
                    hintText: Words.get('enter_password', activeLanguage),
                    prefixIcon: Icons.password_rounded,
                    enabled: !isChecking,
                    obscureText: hidePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!isChecking) {
                        submitPassword();
                      }
                    },
                    suffixIcon: IconButton(
                      onPressed: isChecking
                          ? null
                          : () {
                              setState(() {
                                hidePassword = !hidePassword;
                              });
                            },
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  CustomButton(
                    text: Words.get('submit', activeLanguage),
                    isLoading: isChecking,
                    onPressed: submitPassword,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
