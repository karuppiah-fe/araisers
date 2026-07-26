import 'package:arisers/riverpod/login_provider.dart';
import 'package:arisers/riverpod/session_provider.dart';
import 'package:arisers/riverpod/words.dart';
import 'package:arisers/ui/password..dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Login extends ConsumerStatefulWidget {
  const Login({super.key});

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login> {
  final TextEditingController usernameController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  bool hidePassword = true;

  Future<void> loginUser() async {
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

    final LoginResult? result = await ref
        .read(loginProvider.notifier)
        .login(username: username, password: password);

    if (!mounted) return;

    if (result == null) {
      final loginState = ref.read(loginProvider);

      loginState.whenOrNull(
        error: (error, stackTrace) {
          showMessage(
            message: error.toString().replaceFirst('Exception: ', ''),
            color: Colors.red,
          );
        },
      );

      return;
    }

    await ref
        .read(sessionProvider.notifier)
        .saveLogin(username: result.username, userKey: result.userKey);

    if (!mounted) return;

    usernameController.clear();
    passwordController.clear();

    ref.read(loginProvider.notifier).resetState();

    showMessage(message: 'Welcome ${result.username}', color: Colors.green);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PasswordPage()),
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
    final loginState = ref.watch(loginProvider);

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
                    words.english['login'] ?? 'Login',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  SizedBox(height: height * 0.04),

                  TextField(
                    controller: usernameController,
                    enabled: !loginState.isLoading,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText:
                          words.english['enter the username'] ??
                          'Enter the username',
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

                  TextField(
                    controller: passwordController,
                    enabled: !loginState.isLoading,
                    obscureText: hidePassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) {
                      if (!loginState.isLoading) {
                        loginUser();
                      }
                    },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText:
                          words.english['enter the password'] ??
                          'Enter the password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        onPressed: loginState.isLoading
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
                      onPressed: loginState.isLoading ? null : loginUser,
                      child: loginState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              words.english['login'] ?? 'Login',
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
