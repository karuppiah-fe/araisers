import 'package:arisers/riverpod/session_provider.dart';
import 'package:arisers/riverpod/words.dart';
import 'package:arisers/ui/bluetooth.dart';
import 'package:arisers/ui/home.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PasswordPage extends ConsumerStatefulWidget {
  const PasswordPage({super.key});

  @override
  ConsumerState<PasswordPage> createState() {
    return _PasswordPageState();
  }
}

class _PasswordPageState extends ConsumerState<PasswordPage> {
  final TextEditingController passwordController = TextEditingController();

  bool hidePassword = true;
  bool isChecking = false;

  Future<void> submitPassword() async {
    FocusScope.of(context).unfocus();

    final String password = passwordController.text.trim();

    if (password.isEmpty) {
      showMessage(message: 'Please enter the password', color: Colors.red);
      return;
    }

    setState(() {
      isChecking = true;
    });

    try {
      /*
       * Add your password-validation logic here when needed.
       *
       * At present, this code checks whether the password field
       * is empty and then checks the device configuration.
       */

      final bool deviceAlreadyConfigured = await checkDeviceConfiguration();

      if (!mounted) {
        return;
      }

      if (deviceAlreadyConfigured) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const Home()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (_) => const BluetoothPage()),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      showMessage(message: cleanError(error), color: Colors.red);
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
      final bool validPhase = phase == 1 || phase == 3;

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
            final bool validPhase = phase == 1 || phase == 3;

            if (configured &&
                deviceName.isNotEmpty &&
                wifiSsid.isNotEmpty &&
                validPhase) {
              // Existing device found! Link it to current user in Firebase & Hive
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

    // 3. No device found anywhere in Firebase
    await sessionBox.put('deviceConfigured', false);
    return false;
  }

  String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('FirebaseException: ', '');
  }

  void showMessage({required String message, required Color color}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double width = screenSize.width;
    final double height = screenSize.height;

    final words = ref.watch(wordsProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.lightGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          words.english['arisers'] ?? 'ARISERS',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.08,
              vertical: height * 0.03,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 450),
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.06,
                vertical: height * 0.045,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.lightGreen, Color(0xFF7CB342)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),

                  SizedBox(height: height * 0.02),

                  Text(
                    words.english['password'] ?? 'Password',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  SizedBox(height: height * 0.012),

                  const Text(
                    'Enter your password to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),

                  SizedBox(height: height * 0.035),

                  TextField(
                    controller: passwordController,
                    enabled: !isChecking,
                    obscureText: hidePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!isChecking) {
                        submitPassword();
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText:
                          words.english['enter the password'] ??
                          'Enter the password',
                      prefixIcon: const Icon(
                        Icons.password_rounded,
                        color: Colors.lightGreen,
                      ),
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
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: height * 0.035),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: isChecking ? null : submitPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.lightGreen,
                        disabledBackgroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isChecking
                          ? const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.lightGreen,
                              ),
                            )
                          : Text(
                              words.english['submit'] ?? 'Submit',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
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
