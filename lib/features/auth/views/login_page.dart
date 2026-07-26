import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/core/widgets/custom_button.dart';
import 'package:arisers/core/widgets/custom_text_field.dart';
import 'package:arisers/features/auth/providers/login_provider.dart';
import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/auth/views/password_page.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool hidePassword = true;

  Future<void> loginUser() async {
    FocusScope.of(context).unfocus();

    final String username = usernameController.text.trim();
    final String password = passwordController.text.trim();

    if (username.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter the username',
        color: AppColors.error,
      );
      return;
    }

    if (password.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter the password',
        color: AppColors.error,
      );
      return;
    }

    final LoginResult? result = await ref
        .read(loginProvider.notifier)
        .login(username: username, password: password);

    if (!mounted) return;

    if (result == null) {
      final loginState = ref.read(loginProvider);
      loginState.whenOrNull(
        error: (error, _) {
          UIHelpers.showSnackBar(
            context,
            message: UIHelpers.cleanError(error),
            color: AppColors.error,
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

    UIHelpers.showSnackBar(
      context,
      message: 'Welcome ${result.username}',
      color: AppColors.success,
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PasswordPage()),
      (route) => false,
    );
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
    final Size size = MediaQuery.sizeOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(words.english['arisers'] ?? 'ARISERS'),
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
                  Text(
                    words.english['login'] ?? 'Login',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  CustomTextField(
                    controller: usernameController,
                    hintText:
                        words.english['enter the username'] ??
                        'Enter the username',
                    prefixIcon: Icons.person_rounded,
                    enabled: !loginState.isLoading,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    controller: passwordController,
                    hintText:
                        words.english['enter the password'] ??
                        'Enter the password',
                    prefixIcon: Icons.lock_rounded,
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
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  CustomButton(
                    text: words.english['login'] ?? 'Login',
                    isLoading: loginState.isLoading,
                    onPressed: loginUser,
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
