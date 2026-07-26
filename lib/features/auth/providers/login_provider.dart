import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final loginProvider = AsyncNotifierProvider<LoginNotifier, LoginResult?>(
  LoginNotifier.new,
);

class LoginResult {
  final String userKey;
  final String username;

  const LoginResult({required this.userKey, required this.username});
}

class LoginNotifier extends AsyncNotifier<LoginResult?> {
  final DatabaseReference _arisersRef = FirebaseDatabase.instance.ref(
    'arisers',
  );

  @override
  Future<LoginResult?> build() async {
    return null;
  }

  Future<LoginResult?> login({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty) {
      state = AsyncError('Please enter the username', StackTrace.current);
      return null;
    }

    if (cleanPassword.isEmpty) {
      state = AsyncError('Please enter the password', StackTrace.current);
      return null;
    }

    state = const AsyncLoading();

    try {
      final Query query = _arisersRef
          .orderByChild('username')
          .equalTo(cleanUsername);

      final DataSnapshot snapshot = await query.get();

      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('Username does not exist');
      }

      final Object? value = snapshot.value;

      if (value is! Map) {
        throw Exception('Invalid user data');
      }

      final Map<dynamic, dynamic> users = Map<dynamic, dynamic>.from(value);

      for (final entry in users.entries) {
        final Object? userValue = entry.value;

        if (userValue is! Map) {
          continue;
        }

        final Map<dynamic, dynamic> userData = Map<dynamic, dynamic>.from(
          userValue,
        );

        final String savedUsername = userData['username']?.toString() ?? '';
        final String savedPassword = userData['password']?.toString() ?? '';

        if (savedUsername == cleanUsername && savedPassword == cleanPassword) {
          final result = LoginResult(
            userKey: entry.key.toString(),
            username: savedUsername,
          );

          state = AsyncData(result);

          return result;
        }
      }

      throw Exception('Incorrect password');
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  void resetState() {
    state = const AsyncData(null);
  }
}
