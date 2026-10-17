import 'package:arisers/core/theme/app_theme.dart';
import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/auth/views/first_page.dart';
import 'package:arisers/features/auth/views/password_page.dart';
import 'package:arisers/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:arisers/core/services/notification_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();

  final title =
      message.notification?.title ??
      message.data['title'] ??
      '⚠️ Smart Irrigation Alert';
  final body =
      message.notification?.body ??
      message.data['body'] ??
      'Power cut or trip event detected';

  await NotificationService.showNotification(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: title,
    body: body,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
    } catch (_) {}
    await NotificationService.initialize();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e, stack) {
    debugPrint('Firebase init error: $e\n$stack');
  }

  try {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(SessionNotifier.boxName)) {
      await Hive.openBox(SessionNotifier.boxName);
    }
  } catch (e, stack) {
    debugPrint('Hive init error: $e\n$stack');
    try {
      if (!Hive.isBoxOpen(SessionNotifier.boxName)) {
        await Hive.openBox(SessionNotifier.boxName);
      }
    } catch (retryErr) {
      debugPrint('Hive retry box error: $retryErr');
    }
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KAT',
      theme: AppTheme.lightTheme,
      home: session.isLoggedIn ? const PasswordPage() : const FirstPage(),
    );
  }
}
//hello