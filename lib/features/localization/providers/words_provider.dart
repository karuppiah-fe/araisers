import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Words extends ChangeNotifier {
  final Map<String, String> english = const {
    'arisers': 'ARISERS',
    'login': 'Login',
    'signup': 'Sign Up',
    'enter the username': 'Enter the username',
    'enter the password': 'Enter the password',
    'password': 'Password',
    'submit': 'Submit',
    'bluetooth': 'Bluetooth not connected',
    'connect': 'Connect',
    'disconnect': 'Disconnect',
    'enter the wifi ssid': 'Enter the Wi-Fi SSID',
    'enter the wifi password': 'Enter the Wi-Fi Password',
  };
}

final wordsProvider = ChangeNotifierProvider<Words>((ref) {
  return Words();
});
