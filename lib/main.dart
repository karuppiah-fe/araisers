import 'package:arisers/firebase_options.dart';
import 'package:arisers/riverpod/session_provider.dart';
import 'package:arisers/ui/first_page.dart';
import 'package:arisers/ui/password..dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Hive.initFlutter();

  await Hive.openBox(SessionNotifier.boxName);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: session.isLoggedIn ? const PasswordPage() : const FirstPage(),
    );
  }
}
