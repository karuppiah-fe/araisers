import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/widgets/custom_button.dart';
import 'package:arisers/features/auth/views/login_page.dart';
import 'package:arisers/features/auth/views/signup_page.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirstPage extends ConsumerWidget {
  const FirstPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordsProvider);
    final Size size = MediaQuery.sizeOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(words.english['arisers'] ?? 'ARISERS'),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: Image.asset('assets/images/arisers.jpeg', fit: BoxFit.cover),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
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
                  const SizedBox(height: 10),
                  Text(
                    words.english['arisers'] ?? 'ARISERS',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart Controller Application',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  CustomButton(
                    text: words.english['login'] ?? 'Login',
                    icon: Icons.login_rounded,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  CustomButton(
                    text: words.english['signup'] ?? 'Sign Up',
                    icon: Icons.person_add_rounded,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
