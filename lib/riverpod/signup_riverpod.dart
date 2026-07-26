import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final signupProvider = AsyncNotifierProvider<SignupNotifier, String?>(
  SignupNotifier.new,
);

class SignupNotifier extends AsyncNotifier<String?> {
  DatabaseReference get _arisersRef => FirebaseDatabase.instance.ref('arisers');

  @override
  Future<String?> build() async {
    return null;
  }

  Future<String?> signup({
    required String username,
    required String password,
  }) async {
    final String cleanUsername = username.trim();
    final String cleanPassword = password.trim();

    // Username validation
    if (cleanUsername.isEmpty) {
      state = AsyncError('Please enter the username', StackTrace.current);

      return null;
    }

    if (cleanUsername.length < 3) {
      state = AsyncError(
        'Username must contain at least 3 characters',
        StackTrace.current,
      );

      return null;
    }

    // Password validation
    if (cleanPassword.isEmpty) {
      state = AsyncError('Please enter the password', StackTrace.current);

      return null;
    }

    if (cleanPassword.length < 4) {
      state = AsyncError(
        'Password must contain at least 4 characters',
        StackTrace.current,
      );

      return null;
    }

    state = const AsyncLoading();

    try {
      // Check whether the username already exists.
      final DataSnapshot usernameSnapshot = await _arisersRef
          .orderByChild('username')
          .equalTo(cleanUsername)
          .get();

      if (usernameSnapshot.exists) {
        throw Exception('This username is already registered');
      }

      // Create the next user number.
      final DatabaseReference counterRef = _arisersRef.child('userCount');

      final TransactionResult transactionResult = await counterRef
          .runTransaction((Object? currentValue) {
            final int currentCount =
                int.tryParse(currentValue?.toString() ?? '0') ?? 0;

            return Transaction.success(currentCount + 1);
          });

      if (!transactionResult.committed) {
        throw Exception('Unable to create user number');
      }

      final Object? counterValue = transactionResult.snapshot.value;

      if (counterValue == null) {
        throw Exception('Unable to read the generated user number');
      }

      final int? userNumber = int.tryParse(counterValue.toString());

      if (userNumber == null) {
        throw Exception('Invalid user number generated');
      }

      final String userKey = 'user$userNumber';

      // Save the user in Firebase.
      await _arisersRef.child(userKey).set({
        'username': cleanUsername,
        'password': cleanPassword,
        'createdAt': ServerValue.timestamp,
      });

      state = AsyncData(userKey);

      return userKey;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);

      return null;
    }
  }

  void resetState() {
    state = const AsyncData(null);
  }
}
