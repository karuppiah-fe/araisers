import 'package:arisers/riverpod/session_provider.dart';
import 'package:arisers/riverpod/signup_riverpod.dart';
import 'package:arisers/riverpod/words.dart';
import 'package:arisers/ui/password..dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Signup extends ConsumerStatefulWidget {
  const Signup({super.key});

  @override
  ConsumerState<Signup> createState() => _SignupState();
}

class _SignupState extends ConsumerState<Signup> {
  final TextEditingController usernameController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  bool hidePassword = true;

  Future<void> signupUser() async {
    FocusScope.of(context).unfocus();

    final String username = usernameController.text.trim();

    final String password = passwordController.text.trim();

    if (username.isEmpty) {
      showMessage(message: 'Please enter the username', color: Colors.red);
      return;
    }

    if (password.isEmpty) {
      showMessage(message: 'Please enter the password', color: Colors.red);
      return;
    }

    if (password.length < 4) {
      showMessage(
        message: 'Password must contain at least 4 characters',
        color: Colors.red,
      );
      return;
    }

    final String? userKey = await ref
        .read(signupProvider.notifier)
        .signup(username: username, password: password);

    if (!mounted) return;

    if (userKey == null) {
      final signupState = ref.read(signupProvider);

      signupState.whenOrNull(
        error: (error, stackTrace) {
          showMessage(
            message: error.toString().replaceFirst('Exception: ', ''),
            color: Colors.red,
          );
        },
      );

      return;
    }

    // Store the successful login session locally in Hive.
    await ref
        .read(sessionProvider.notifier)
        .saveLogin(username: username, userKey: userKey);

    if (!mounted) return;

    usernameController.clear();
    passwordController.clear();

    ref.read(signupProvider.notifier).resetState();

    showMessage(message: 'Signup successful', color: Colors.green);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const PasswordPage()),
      (route) => false,
    );
  }

  void showMessage({required String message, required Color color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(wordsProvider);
    final signupState = ref.watch(signupProvider);

    final Size screenSize = MediaQuery.sizeOf(context);
    final double width = screenSize.width;
    final double height = screenSize.height;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightGreen,
        centerTitle: true,
        title: Text(
          words.english['arisers'] ?? 'Arisers',
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
              horizontal: width * 0.05,
              vertical: height * 0.03,
            ),
            child: Container(
              width: width * 0.85,
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.06,
                vertical: height * 0.04,
              ),
              decoration: BoxDecoration(
                color: Colors.lightGreen,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    words.english['signup'] ?? 'Sign Up',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  SizedBox(height: height * 0.04),

                  // Username
                  TextField(
                    controller: usernameController,
                    enabled: !signupState.isLoading,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText:
                          words.english['enter the username'] ??
                          'Enter the username',
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(84, 0, 0, 0),
                      ),
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.grey.shade400,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  SizedBox(height: height * 0.025),

                  // Password
                  TextField(
                    controller: passwordController,
                    enabled: !signupState.isLoading,
                    obscureText: hidePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) {
                      if (!signupState.isLoading) {
                        signupUser();
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText:
                          words.english['enter the password'] ??
                          'Enter the password',
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(84, 0, 0, 0),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        onPressed: signupState.isLoading
                            ? null
                            : () {
                                setState(() {
                                  hidePassword = !hidePassword;
                                });
                              },
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.grey.shade400,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  SizedBox(height: height * 0.04),

                  SizedBox(
                    width: double.infinity,
                    height: height * 0.06,
                    child: ElevatedButton(
                      onPressed: signupState.isLoading ? null : signupUser,
                      child: signupState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              words.english['signup'] ?? 'Sign Up',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
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
