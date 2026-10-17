import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationCategory {
  criticalFault,
  powerEvent,
  systemStatus,
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? _lastNotificationTitle;
  static String? _lastNotificationBody;
  static DateTime? _lastNotificationTime;

  static const String channelCriticalId = 'critical_faults_channel';
  static const String channelPowerId = 'power_events_channel';
  static const String channelStatusId = 'system_status_channel';

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(initializationSettings);

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Channel 1: Critical Fault Trips (High Priority, Custom Vibration)
    final AndroidNotificationChannel criticalChannel = AndroidNotificationChannel(
      channelCriticalId,
      '🚨 Critical Safety Faults',
      description: 'Notifications for Dry Run, Overload, Voltage Out of Range, and Phase Trips',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
    );

    // Channel 2: Power Grid Events (Power Outage & Restoration)
    final AndroidNotificationChannel powerChannel = AndroidNotificationChannel(
      channelPowerId,
      '⚡ Power Grid Events',
      description: 'Notifications for Power Cut Outages and Grid Restoration',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Channel 3: Motor & Schedule Status
    final AndroidNotificationChannel statusChannel = AndroidNotificationChannel(
      channelStatusId,
      '⚙️ Motor & Schedule Actions',
      description: 'Notifications for Motor ON/OFF, Scheduled Run, and Cyclic Timer actions',
      importance: Importance.defaultImportance,
      playSound: true,
    );

    await androidPlugin?.createNotificationChannel(criticalChannel);
    await androidPlugin?.createNotificationChannel(powerChannel);
    await androidPlugin?.createNotificationChannel(statusChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> showProNotification({
    required int id,
    required String title,
    required String body,
    NotificationCategory category = NotificationCategory.criticalFault,
  }) async {
    final now = DateTime.now();

    // 30-Second Smart Deduplication Guard
    if (_lastNotificationTitle == title &&
        _lastNotificationBody == body &&
        _lastNotificationTime != null &&
        now.difference(_lastNotificationTime!).inSeconds < 30) {
      debugPrint('Notification suppressed (duplicate within 30s): $title');
      return;
    }

    _lastNotificationTitle = title;
    _lastNotificationBody = body;
    _lastNotificationTime = now;

    String targetChannelId = channelCriticalId;
    Importance importance = Importance.max;
    Priority priority = Priority.max;

    if (category == NotificationCategory.powerEvent) {
      targetChannelId = channelPowerId;
      importance = Importance.high;
      priority = Priority.high;
    } else if (category == NotificationCategory.systemStatus) {
      targetChannelId = channelStatusId;
      importance = Importance.defaultImportance;
      priority = Priority.defaultPriority;
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      targetChannelId,
      category == NotificationCategory.criticalFault
          ? '🚨 Critical Safety Faults'
          : (category == NotificationCategory.powerEvent ? '⚡ Power Grid Events' : '⚙️ Motor & Schedule Actions'),
      channelDescription: 'KAT Pro System Alerts',
      importance: importance,
      priority: priority,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformDetails,
    );
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    NotificationCategory category = NotificationCategory.systemStatus;

    final lowerTitle = title.toLowerCase();
    final lowerBody = body.toLowerCase();

    if (lowerTitle.contains('fault') ||
        lowerTitle.contains('dry') ||
        lowerTitle.contains('overload') ||
        lowerTitle.contains('trip') ||
        lowerBody.contains('dry') ||
        lowerBody.contains('overload') ||
        lowerBody.contains('fault') ||
        lowerBody.contains('voltage out')) {
      category = NotificationCategory.criticalFault;
    } else if (lowerTitle.contains('power') ||
        lowerBody.contains('power') ||
        lowerBody.contains('outage') ||
        lowerBody.contains('grid')) {
      category = NotificationCategory.powerEvent;
    }

    await showProNotification(
      id: id,
      title: title,
      body: body,
      category: category,
    );
  }

  static Future<void> initializeFirebaseMessaging(String deviceName) async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null && deviceName.isNotEmpty) {
          try {
            final ref = FirebaseDatabase.instance.ref('ariserskaruppiahs/$deviceName/fcm_token');
            await ref.set(token);
          } catch (e) {
            debugPrint('FCM Token DB save ignored: $e');
          }
        }

        if (deviceName.isNotEmpty) {
          try {
            await FirebaseMessaging.instance.subscribeToTopic(deviceName);
            await FirebaseMessaging.instance.subscribeToTopic('arisers_$deviceName');
            await FirebaseMessaging.instance.subscribeToTopic('all_devices');
            debugPrint('FCM Subscribed to topic: arisers_$deviceName');
          } catch (e) {
            debugPrint('FCM Topic subscribe error: $e');
          }
        }
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? message.data['title'] ?? '⚠️ KAT Alert';
        final body = message.notification?.body ?? message.data['body'] ?? '';
        final String categoryType = message.data['category']?.toString() ?? '';

        NotificationCategory cat = NotificationCategory.criticalFault;
        if (categoryType == 'power') {
          cat = NotificationCategory.powerEvent;
        } else if (categoryType == 'status') {
          cat = NotificationCategory.systemStatus;
        }

        showProNotification(
          id: title.hashCode & 0x7FFFFFFF,
          title: title,
          body: body,
          category: cat,
        );
      });
    } catch (e) {
      debugPrint('FCM Init error: $e');
    }
  }
}
