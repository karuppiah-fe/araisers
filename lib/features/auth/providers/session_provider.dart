import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class SessionState {
  final bool isLoggedIn;
  final String? username;
  final String? userKey;

  const SessionState({required this.isLoggedIn, this.username, this.userKey});

  const SessionState.loggedOut()
    : isLoggedIn = false,
      username = null,
      userKey = null;
}

class SessionNotifier extends Notifier<SessionState> {
  static const String boxName = 'sessionBox';

  Box get _box => Hive.box(boxName);

  @override
  SessionState build() {
    final bool isLoggedIn = _box.get('isLoggedIn', defaultValue: false) as bool;
    final String? username = _box.get('username')?.toString();
    final String? userKey = _box.get('userKey')?.toString();

    return SessionState(
      isLoggedIn: isLoggedIn,
      username: username,
      userKey: userKey,
    );
  }

  Future<void> saveLogin({
    required String username,
    required String userKey,
  }) async {
    final String? previousUserKey = _box.get('userKey')?.toString();
    if (previousUserKey != null && previousUserKey != userKey) {
      await _box.delete('deviceConfigured');
      await _box.delete('deviceName');
      await _box.delete('wifiSsid');
      await _box.delete('phase');
    }

    await _box.put('isLoggedIn', true);
    await _box.put('username', username);
    await _box.put('userKey', userKey);

    state = SessionState(
      isLoggedIn: true,
      username: username,
      userKey: userKey,
    );
  }

  Future<void> updateCredentials({
    required String newUsername,
    required String newPassword,
  }) async {
    final String? currentKey = _box.get('userKey')?.toString();

    // 1. Update Firebase Realtime Database
    if (currentKey != null && currentKey.isNotEmpty) {
      try {
        final ref = FirebaseDatabase.instance.ref('arisers/$currentKey');
        final Map<String, dynamic> updates = {'username': newUsername};
        if (newPassword.isNotEmpty) {
          updates['password'] = newPassword;
        }
        await ref.update(updates);
      } catch (_) {}
    }

    // 2. Update Firebase Auth user profile if logged in
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (newPassword.isNotEmpty) {
          await user.updatePassword(newPassword);
        }
        await user.updateDisplayName(newUsername);
      }
    } catch (_) {}

    // 3. Update Hive Session Box
    await _box.put('username', newUsername);

    state = SessionState(
      isLoggedIn: true,
      username: newUsername,
      userKey: currentKey ?? state.userKey,
    );
  }

  Future<void> logout() async {
    await _box.delete('isLoggedIn');
    await _box.delete('username');
    await _box.delete('userKey');
    await _box.delete('deviceConfigured');
    await _box.delete('deviceName');
    await _box.delete('wifiSsid');
    await _box.delete('phase');

    state = const SessionState.loggedOut();
  }
}
