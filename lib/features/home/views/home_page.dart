import 'dart:async';
import 'dart:convert';

import 'package:arisers/core/services/notification_service.dart';
import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/features/home/providers/cyclic_timer_provider.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';
import 'package:arisers/features/home/providers/device_online_provider.dart';
import 'package:arisers/features/home/providers/scheduler_provider.dart';
import 'package:arisers/features/home/views/widgets/cyclic_timer_view.dart';
import 'package:arisers/features/home/views/widgets/datalog_view.dart';
import 'package:arisers/features/home/views/widgets/motor_controller_widget.dart';
import 'package:arisers/features/home/views/widgets/schedulers_view.dart';
import 'package:arisers/features/home/views/widgets/settings_bottom_sheet.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _selectedTabIndex = 0;

  // MQTT OBJECTS
  MqttServerClient? _mqttClient;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _mqttSubscription;

  Timer? _sensorTimeoutTimer;
  Timer? _stalenessCheckTimer;

  bool _isConnecting = false;
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false;

  String _connectionMessage = 'MQTT disconnected';

  // DEVICE DETAILS FROM HIVE
  String _userKey = '';
  String _deviceName = '';
  final int _appLaunchTimestamp = DateTime.now().millisecondsSinceEpoch;

  String? _lastNotifiedReason;
  String? _lastNotifiedType;
  DateTime? _lastNotificationTime;

  String _baseTopic = '';
  String _electricalTopic = '';
  String _availabilityTopic = '';

  // SENSOR VALUES
  double _rVoltage = 0;
  double _yVoltage = 0;
  double _bVoltage = 0;

  double _rCurrent = 0;
  double _yCurrent = 0;
  double _bCurrent = 0;

  double _frequency = 0;

  String _phaseSequence = '--';
  String _faultMessage = 'No fault';

  bool _phaseFailure = false;
  bool _isPowerCut = false;
  int _phaseType = 3;

  DateTime? _lastUpdated;

  String? _motor1MqttStatus;
  String? _motor2MqttStatus;
  String? _motor1TelemetryState;
  String? _motor2TelemetryState;

  @override
  void initState() {
    super.initState();
    NotificationService.initialize();
    _initializeApplication();
    _setupAutomationHandlers();
    _startPeriodicStalenessCheck();
  }

  @override
  void dispose() {
    _sensorTimeoutTimer?.cancel();
    _stalenessCheckTimer?.cancel();
    _mqttSubscription?.cancel();
    _mqttClient?.disconnect();
    super.dispose();
  }

  void _setupAutomationHandlers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(schedulerProvider.notifier).setCommandHandler(_sendMqttCommand);
      ref
          .read(cyclicTimerProvider.notifier)
          .setCommandHandler(_sendMqttCommand);

      ref
          .read(schedulerProvider.notifier)
          .setMqttSyncHandler(
            (payload) =>
                _publishConfigMqtt('$_baseTopic/config/scheduler', payload),
          );

      ref
          .read(cyclicTimerProvider.notifier)
          .setMqttSyncHandler(
            (payload) =>
                _publishConfigMqtt('$_baseTopic/config/cyclic', payload),
          );

      ref.read(cyclicTimerProvider.notifier).restoreStateFromHive();
    });
  }

  void _publishConfigMqtt(String topic, String payload) {
    if (!mounted) return;
    final MqttServerClient? client = _mqttClient;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected ||
        topic.isEmpty) {
      return;
    }

    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
    debugPrint('Published Config to ESP32 [$topic]: $payload');
  }

  void _sendMqttCommand(String motorName, bool turnOn) {
    if (!mounted) return;
    if (turnOn && !_isVoltageValid) {
      debugPrint('Automated start rejected: Voltage out of range');
      return;
    }

    if (turnOn) {
      if (mounted) {
        setState(() {
          _phaseFailure = false;
          _faultMessage = 'No fault';
        });
      }
    }

    final MqttServerClient? client = _mqttClient;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    final String topic = (motorName == 'Motor 1')
        ? '$_baseTopic/command/motor1'
        : '$_baseTopic/command/motor2';

    final String command = turnOn ? 'ON' : 'OFF';
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(command);

    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('Automated Command Sent [$topic]: $command');
  }

  Future<void> _initializeApplication() async {
    try {
      await _loadDeviceInformation();

      if (_deviceName.isEmpty) {
        throw Exception(
          'Device name was not found. Configure the ESP32 first.',
        );
      }

      NotificationService.initializeFirebaseMessaging(_deviceName);

      _createMqttTopics();
      await _connectToMqttBroker();
    } catch (error) {
      final String message = UIHelpers.cleanError(error);

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _isMqttConnected = false;
        _connectionMessage = message;
      });

      UIHelpers.showSnackBar(context, message: message, color: AppColors.error);
    }
  }

  Future<void> _loadDeviceInformation() async {
    final Box<dynamic> sessionBox = Hive.box('sessionBox');

    _userKey = sessionBox.get('userKey', defaultValue: '').toString().trim();

    if (_userKey.isNotEmpty) {
      ref.read(schedulerProvider.notifier).refreshFirebaseListener();
    }

    String storedDeviceName = sessionBox
        .get('deviceName', defaultValue: '')
        .toString()
        .trim();

    int storedPhase =
        int.tryParse(sessionBox.get('phase', defaultValue: 3).toString()) ?? 3;

    if (_userKey.isNotEmpty) {
      try {
        final DatabaseReference deviceRef = FirebaseDatabase.instance.ref(
          'arisers/$_userKey/deviceInfo',
        );
        final DataSnapshot snapshot = await deviceRef.get();

        if (snapshot.exists && snapshot.value is Map) {
          final Map<String, dynamic> devData = Map<String, dynamic>.from(
            snapshot.value as Map,
          );
          final String name = devData['deviceName']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            storedDeviceName = name;
            await sessionBox.put('deviceName', name);
            await sessionBox.put('deviceConfigured', true);
          }

          final int? firebasePhase = int.tryParse(
            devData['phase']?.toString() ?? '',
          );
          if (firebasePhase != null &&
              firebasePhase >= 1 &&
              firebasePhase <= 3) {
            storedPhase = firebasePhase;
            await sessionBox.put('phase', firebasePhase);
          }

          final double? fbMinAmp = double.tryParse(
            devData['minAmp']?.toString() ?? '',
          );
          if (fbMinAmp != null) await sessionBox.put('minAmp', fbMinAmp);
          final double? fbMaxAmp = double.tryParse(
            devData['maxAmp']?.toString() ?? '',
          );
          if (fbMaxAmp != null) await sessionBox.put('maxAmp', fbMaxAmp);
          final double? fbMinVolt = double.tryParse(
            devData['minVolt']?.toString() ?? '',
          );
          if (fbMinVolt != null) await sessionBox.put('minVolt', fbMinVolt);
          final double? fbMaxVolt = double.tryParse(
            devData['maxVolt']?.toString() ?? '',
          );
          if (fbMaxVolt != null) await sessionBox.put('maxVolt', fbMaxVolt);
        }
      } catch (e) {
        debugPrint('Firebase fetch error: $e');
      }
    }

    if (storedDeviceName.isEmpty) {
      storedDeviceName = 'jai01';
    }

    setState(() {
      _deviceName = storedDeviceName;
      _phaseType = (storedPhase >= 1 && storedPhase <= 3) ? storedPhase : 3;
    });
  }

  String _sanitizeTopicLevel(String value) {
    String output = value.trim().toLowerCase();
    output = output.replaceAll(RegExp(r'[/+#\s\r\n]+'), '-');
    while (output.startsWith('-')) {
      output = output.substring(1);
    }
    while (output.endsWith('-')) {
      output = output.substring(0, output.length - 1);
    }
    return output;
  }

  void _createMqttTopics() {
    final String safeDeviceName = _sanitizeTopicLevel(_deviceName);

    _baseTopic = 'ariserskaruppiahs/$safeDeviceName/controller01';
    _electricalTopic = '$_baseTopic/telemetry/all';
    _availabilityTopic = '$_baseTopic/status/connection';

    debugPrint('MQTT base topic: $_baseTopic');
  }

  Future<void> _connectToMqttBroker() async {
    if (_isConnecting) return;

    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = true;
      _connectionMessage = 'Connecting to MQTT broker...';
    });

    // Enforce MQTT 3.1.1 protocol standard
    Protocol.version = MqttClientConstants.mqttV311ProtocolVersion;
    Protocol.name = MqttClientConstants.mqttV311ProtocolName;

    final String clientIdentifier =
        'arisers_${DateTime.now().millisecondsSinceEpoch % 1000000}';

    final List<Map<String, dynamic>> connectionConfigs = [
      {
        'host': '64.227.151.86',
        'port': 1883,
        'ws': false,
        'name': 'DigitalOcean',
      },
      {
        'host': 'broker.hivemq.com',
        'port': 1883,
        'ws': false,
        'name': 'HiveMQ',
      },
      {'host': 'broker.emqx.io', 'port': 1883, 'ws': false, 'name': 'EMQX'},
      {
        'host': 'test.mosquitto.org',
        'port': 1883,
        'ws': false,
        'name': 'Mosquitto',
      },
    ];

    for (final config in connectionConfigs) {
      if (!mounted) return;

      final String host = config['host'] as String;
      final int port = config['port'] as int;
      final bool useWs = config['ws'] as bool;
      final String brokerName = config['name'] as String;

      setState(() {
        _connectionMessage =
            'Connecting to $brokerName (${useWs ? "WebSocket" : "TCP"})...';
      });

      debugPrint(
        'Attempting MQTT connection to $host:$port ($brokerName, ws: $useWs)...',
      );

      final MqttServerClient client = MqttServerClient.withPort(
        host,
        clientIdentifier,
        port,
      );

      client.logging(on: false);
      client.keepAlivePeriod = 30;
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;
      client.secure = false;
      client.connectTimeoutPeriod = 10000;

      if (useWs) {
        client.useWebSocket = true;
        client.websocketProtocols = ['mqtt'];
      } else {
        client.useWebSocket = false;
      }

      client.onConnected = _onMqttConnected;
      client.onDisconnected = _onMqttDisconnected;

      final MqttConnectMessage connectMessage = MqttConnectMessage()
          .withClientIdentifier(clientIdentifier)
          .authenticateAs('iot_client', 'SecureIotPassword2026!')
          .startClean();

      client.connectionMessage = connectMessage;
      _mqttClient = client;

      try {
        await client.connect();

        if (client.connectionStatus?.state == MqttConnectionState.connected) {
          debugPrint('Successfully connected to $brokerName ($host:$port)');
          if (!mounted) return;

          setState(() {
            _isConnecting = false;
            _isMqttConnected = true;
            _connectionMessage = 'Connected to $brokerName ($host)';
          });

          _subscribeToTelemetryTopics();
          return;
        }
      } catch (error) {
        debugPrint('Failed to connect to $brokerName ($host:$port): $error');
        client.disconnect();
      }
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _isMqttConnected = false;
      _connectionMessage = 'Broker connection failed';
    });
  }

  void _onMqttConnected() {
    debugPrint('MQTT Client Connected Callback triggered');
  }

  void _onMqttDisconnected() {
    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _isMqttConnected = false;
      _isDeviceOnline = false;
      _connectionMessage = 'MQTT disconnected';
    });
  }

  void _subscribeToTelemetryTopics() {
    final MqttServerClient? client = _mqttClient;

    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    client.subscribe(_electricalTopic, MqttQos.atLeastOnce);
    client.subscribe(_availabilityTopic, MqttQos.atLeastOnce);
    client.subscribe(_baseTopic, MqttQos.atLeastOnce);
    client.subscribe('$_baseTopic/#', MqttQos.atLeastOnce);

    final Stream<List<MqttReceivedMessage<MqttMessage?>>>? updates =
        client.updates;

    if (updates == null) return;

    _mqttSubscription?.cancel();
    _mqttSubscription = updates.listen(_handleIncomingMqttMessages);
  }

  void _handleIncomingMqttMessages(
    List<MqttReceivedMessage<MqttMessage?>> messages,
  ) {
    for (final message in messages) {
      final String topic = message.topic;
      final MqttPublishMessage publishMessage =
          message.payload as MqttPublishMessage;

      final String rawPayload = utf8.decode(
        publishMessage.payload.message,
        allowMalformed: true,
      );

      final String payload = rawPayload.trim();
      debugPrint('MQTT received [$topic]: $payload');

      if (topic == _availabilityTopic || topic.endsWith('/status/connection')) {
        _handleDeviceAvailability(payload);
      }

      if (topic.endsWith('/status/motor1')) {
        if (mounted) {
          setState(() {
            _motor1MqttStatus = payload;
          });
        }
      } else if (topic.endsWith('/status/motor2')) {
        if (mounted) {
          setState(() {
            _motor2MqttStatus = payload;
          });
        }
      }

      if (topic.endsWith('/status/cyclic') || (payload.contains('"remSec"') && payload.contains('"currCycle"'))) {
        ref.read(cyclicTimerProvider.notifier).syncFromHardwareMqtt(payload);
      }

      if (topic.endsWith('/status/alert') || payload.contains('"alert"')) {
        _handleAlertNotification(payload);
      }

      if (topic == _electricalTopic ||
          topic.endsWith('/telemetry/all') ||
          payload.contains('rVoltage') ||
          payload.contains('voltage') ||
          payload.contains('phases')) {
        _handleElectricalTelemetry(payload);
      }
    }
  }

  void _handleAlertNotification(String payload) {
    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      final String alertType = data['alert']?.toString() ?? 'ALERT';
      final String reason = data['reason']?.toString() ?? 'Unknown event';
      final int msgTimestamp = (data['timestamp'] as num?)?.toInt() ?? 0;
      final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;

      // Suppress notification pop-ups and banners for retained messages delivered right after app launch (first 3.5s)
      final bool isAppLaunchRetained = (nowMs - _appLaunchTimestamp < 3500);
      final bool isStaleRetained = isAppLaunchRetained || ((msgTimestamp > 1600000000) && (nowSec - msgTimestamp > 60));

      if (!isStaleRetained) {
        final now = DateTime.now();
        final bool isDuplicate = (_lastNotifiedReason == reason &&
            _lastNotifiedType == alertType &&
            _lastNotificationTime != null &&
            now.difference(_lastNotificationTime!).inSeconds < 30);

        if (!isDuplicate) {
          _lastNotifiedType = alertType;
          _lastNotifiedReason = reason;
          _lastNotificationTime = now;

          NotificationCategory category = NotificationCategory.systemStatus;
          Color bannerColor = Colors.blue.shade900;
          String iconHeader = 'ℹ️ Info';

          final lowerType = alertType.toLowerCase();
          final lowerReason = reason.toLowerCase();

          if (lowerType.contains('fault') ||
              lowerType.contains('trip') ||
              lowerReason.contains('dry') ||
              lowerReason.contains('overload') ||
              lowerReason.contains('fault') ||
              lowerReason.contains('voltage out')) {
            category = NotificationCategory.criticalFault;
            bannerColor = Colors.red.shade900;
            iconHeader = '🚨 Critical Fault';
          } else if (lowerType.contains('power') ||
              lowerReason.contains('power') ||
              lowerReason.contains('outage') ||
              lowerReason.contains('restored')) {
            category = NotificationCategory.powerEvent;
            bannerColor = Colors.amber.shade900;
            iconHeader = '⚡ Power Event';
          }

          NotificationService.showProNotification(
            id: alertType.hashCode & 0x7FFFFFFF,
            title: '$iconHeader [$alertType]',
            body: reason,
            category: category,
          );

          if (mounted && context.mounted) {
            try {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        category == NotificationCategory.criticalFault
                            ? Icons.error_outline
                            : (category == NotificationCategory.powerEvent
                                ? Icons.bolt
                                : Icons.info_outline),
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$iconHeader [$alertType]: $reason',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: bannerColor,
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            } catch (_) {}
          }
        }
      }

      ref
          .read(dataLogProvider.notifier)
          .addLog(
            motorName: 'System',
            action: alertType,
            trigger: 'Priority Engine',
            details: reason,
          );
    } catch (_) {}
  }

  void _startPeriodicStalenessCheck() {
    _stalenessCheckTimer?.cancel();
    _stalenessCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_lastUpdated == null || now.difference(_lastUpdated!).inSeconds >= 10) {
        if (_isDeviceOnline) {
          setState(() {
            _isDeviceOnline = false;
            ref.read(deviceOnlineProvider.notifier).state = false;
          });
        }
      }
    });
  }

  void _handleDeviceAvailability(String payload) {
    final String cleanPayload = payload.toLowerCase();

    final bool isExplicitOffline =
        cleanPayload == 'offline' ||
        cleanPayload == 'disconnected' ||
        cleanPayload == 'false' ||
        cleanPayload == '0';

    final bool isExplicitOnline =
        cleanPayload == 'online' ||
        cleanPayload == 'connected' ||
        cleanPayload == 'ready' ||
        cleanPayload == 'true' ||
        cleanPayload == '1';

    if (!mounted) return;

    setState(() {
      if (isExplicitOffline) {
        _isDeviceOnline = false;
        ref.read(deviceOnlineProvider.notifier).state = false;
      } else if (isExplicitOnline) {
        if (_lastUpdated == null ||
            DateTime.now().difference(_lastUpdated!).inSeconds < 10) {
          _isDeviceOnline = true;
          ref.read(deviceOnlineProvider.notifier).state = true;
        } else {
          _isDeviceOnline = false;
          ref.read(deviceOnlineProvider.notifier).state = false;
        }
      }
    });
  }

  void _handleElectricalTelemetry(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);

      if (decoded is! Map<String, dynamic>) return;

      final Map<String, dynamic>? phases = decoded['phases'] is Map
          ? Map<String, dynamic>.from(decoded['phases'])
          : null;

      final Map<String, dynamic>? rPhase = phases?['r'] is Map
          ? Map<String, dynamic>.from(phases!['r'])
          : null;
      final Map<String, dynamic>? yPhase = phases?['y'] is Map
          ? Map<String, dynamic>.from(phases!['y'])
          : null;
      final Map<String, dynamic>? bPhase = phases?['b'] is Map
          ? Map<String, dynamic>.from(phases!['b'])
          : null;

      final double rV = _parseDouble(
        decoded['rv'] ??
            decoded['rVoltage'] ??
            decoded['vr'] ??
            decoded['v1'] ??
            decoded['r_voltage'] ??
            decoded['r_volt'] ??
            rPhase?['voltage'],
      );
      final double yV = _parseDouble(
        decoded['yv'] ??
            decoded['yVoltage'] ??
            decoded['vy'] ??
            decoded['v2'] ??
            decoded['y_voltage'] ??
            decoded['y_volt'] ??
            yPhase?['voltage'],
      );
      final double bV = _parseDouble(
        decoded['bv'] ??
            decoded['bVoltage'] ??
            decoded['vb'] ??
            decoded['v3'] ??
            decoded['b_voltage'] ??
            decoded['b_volt'] ??
            bPhase?['voltage'],
      );

      final double rA = _parseDouble(
        decoded['ra'] ??
            decoded['rCurrent'] ??
            decoded['ir'] ??
            decoded['i1'] ??
            decoded['r_current'] ??
            decoded['r_amp'] ??
            rPhase?['current'],
      );
      final double yA = _parseDouble(
        decoded['ya'] ??
            decoded['yCurrent'] ??
            decoded['iy'] ??
            decoded['i2'] ??
            decoded['y_current'] ??
            decoded['y_amp'] ??
            yPhase?['current'],
      );
      final double bA = _parseDouble(
        decoded['ba'] ??
            decoded['bCurrent'] ??
            decoded['ib'] ??
            decoded['i3'] ??
            decoded['b_current'] ??
            decoded['b_amp'] ??
            bPhase?['current'],
      );

      final double freq = _parseDouble(
        decoded['frequency'] ?? decoded['freq'] ?? rPhase?['frequency'],
      );

      final String seq =
          decoded['phaseSequence']?.toString() ??
          decoded['seq']?.toString() ??
          'RYB';

      final String fault =
          decoded['faultMessage']?.toString() ??
          decoded['fault']?.toString() ??
          'No fault';

      final bool pFail =
          decoded['phaseFailure'] == true || decoded['pfail'] == true;

      final String? m1TelState =
          decoded['motor1State']?.toString() ?? decoded['m1']?.toString();
      final String? m2TelState =
          decoded['motor2State']?.toString() ?? decoded['m2']?.toString();

      if (!mounted) return;

      if (pFail && !_phaseFailure) {
        // Record Safety Trip Log
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(dataLogProvider.notifier)
              .addLog(
                motorName: 'System',
                action: 'OFF',
                trigger: 'Safety Trip',
                details: fault,
              );
        });
      }

      // Track Power Cut & Power Restored state transitions
      final int phaseMode = (decoded['phaseMode'] as num?)?.toInt() ?? 3;
      bool isCurrentlyPowerCut = false;
      bool isCurrentlyPowerRestored = false;

      if (phaseMode == 1) {
        isCurrentlyPowerCut = (rV < 50.0);
        isCurrentlyPowerRestored = (rV >= 150.0);
      } else if (phaseMode == 2) {
        isCurrentlyPowerCut = (rV < 50.0 && yV < 50.0);
        isCurrentlyPowerRestored = (rV >= 150.0 || yV >= 150.0);
      } else {
        isCurrentlyPowerCut = (rV < 50.0 && yV < 50.0 && bV < 50.0);
        isCurrentlyPowerRestored = (rV >= 150.0 || yV >= 150.0 || bV >= 150.0);
      }

      if (isCurrentlyPowerCut && !_isPowerCut) {
        _isPowerCut = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final cyclicState = ref.read(cyclicTimerProvider);
          if (cyclicState.status == CyclicStatus.running) {
            ref.read(cyclicTimerProvider.notifier).pauseTimer(isPowerOutage: true);
          }
          ref
              .read(dataLogProvider.notifier)
              .addLog(
                motorName: 'Power Grid',
                action: 'POWER CUT',
                trigger: 'Power Event',
                details: 'Grid Supply Outage Detected (0.0V)',
              );
        });
      } else if (isCurrentlyPowerRestored && _isPowerCut) {
        _isPowerCut = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final cyclicState = ref.read(cyclicTimerProvider);
          if (cyclicState.status == CyclicStatus.paused && cyclicState.isPausedByPower) {
            ref.read(cyclicTimerProvider.notifier).resumeTimer();
          }
          ref
              .read(dataLogProvider.notifier)
              .addLog(
                motorName: 'Power Grid',
                action: 'POWER RESTORED',
                trigger: 'Power Event',
                details:
                    'Grid Power Restored [R: ${rV.toStringAsFixed(1)}V | Y: ${yV.toStringAsFixed(1)}V | B: ${bV.toStringAsFixed(1)}V]',
              );
        });
      }

      ref.read(rVoltageProvider.notifier).state = rV;
      setState(() {
        _rVoltage = rV;
        _yVoltage = yV;
        _bVoltage = bV;

        _rCurrent = rA;
        _yCurrent = yA;
        _bCurrent = bA;

        _frequency = freq;
        _phaseSequence = seq;
        _faultMessage = fault;
        _phaseFailure = pFail;
        _motor1TelemetryState = m1TelState;
        _motor2TelemetryState = m2TelState;
        _isDeviceOnline = true;
        ref.read(deviceOnlineProvider.notifier).state = true;
        _lastUpdated = DateTime.now();
      });

      _restartSensorTimeoutTimer();
    } catch (e) {
      debugPrint('Error parsing telemetry JSON: $e');
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  void _restartSensorTimeoutTimer() {
    _sensorTimeoutTimer?.cancel();
    _sensorTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() {
        _isDeviceOnline = false;
      });
    });
  }

  void _openSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeLanguage = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _deviceName.isEmpty ? 'KAT' : _deviceName.toUpperCase(),
        ),
        actions: [
          IconButton(
            onPressed: _initializeApplication,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Connection',
          ),
          IconButton(
            onPressed: _openSettingsBottomSheet,
            icon: const Icon(Icons.settings_rounded),
            tooltip: Words.get('settings', activeLanguage),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildDashboardView(activeLanguage),
          const SchedulersView(),
          const CyclicTimerView(),
          const DataLogView(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() => _selectedTabIndex = index);
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_rounded),
            label: Words.get('dashboard', activeLanguage),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.alarm_rounded),
            label: Words.get('schedulers', activeLanguage),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.loop_rounded),
            label: Words.get('cyclic_timer', activeLanguage),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_rounded),
            label: Words.get('data_logs', activeLanguage),
          ),
        ],
      ),
    );
  }

  bool get _isVoltageValid {
    if (!_isDeviceOnline) return false;

    final bool rValid = _rVoltage >= 150.0 && _rVoltage <= 280.0;
    if (_phaseType == 1) {
      return rValid;
    }

    final bool yValid = _yVoltage >= 150.0 && _yVoltage <= 280.0;
    if (_phaseType == 2) {
      return rValid && yValid;
    }

    final bool bValid = _bVoltage >= 150.0 && _bVoltage <= 280.0;

    return rValid && yValid && bValid;
  }

  Widget _buildDashboardView(AppLanguage activeLanguage) {
    final cyclicState = ref.watch(cyclicTimerProvider);
    final bool isCyclicRunningPhase =
        cyclicState.status == CyclicStatus.running &&
        cyclicState.isRunningPhase;

    final String? effectiveM1State = !_isDeviceOnline
        ? 'OFFLINE'
        : ((isCyclicRunningPhase && cyclicState.motorName == 'Motor 1')
            ? 'ON'
            : (_motor1TelemetryState ?? _motor1MqttStatus));

    final String? effectiveM2State = !_isDeviceOnline
        ? 'OFFLINE'
        : ((isCyclicRunningPhase && cyclicState.motorName == 'Motor 2')
            ? 'ON'
            : (_motor2TelemetryState ?? _motor2MqttStatus));

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _initializeApplication,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusBanner(activeLanguage),
              const SizedBox(height: 16),
              _buildTelemetryGrid(activeLanguage),
              const SizedBox(height: 16),
              _buildPhaseAndFaultCard(activeLanguage),
              const SizedBox(height: 20),
              MotorControllerWidget(
                mqttClient: _mqttClient,
                baseTopic: _baseTopic,
                isVoltageValid: _isVoltageValid,
                faultMessage: _faultMessage,
                rCurrent: _rCurrent,
                yCurrent: _yCurrent,
                bCurrent: _bCurrent,
                motor1ExternalStatus: _motor1MqttStatus,
                motor2ExternalStatus: _motor2MqttStatus,
                motor1TelemetryState: effectiveM1State,
                motor2TelemetryState: effectiveM2State,
                onLogEvent: (motorName, action, trigger) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    ref
                        .read(dataLogProvider.notifier)
                        .addLog(
                          motorName: motorName,
                          action: action,
                          trigger: trigger,
                        );
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(AppLanguage activeLanguage) {
    final bool online = _isMqttConnected && _isDeviceOnline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: online ? AppColors.primaryLight : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online ? AppColors.success : AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online
                      ? Words.get('device_online', activeLanguage)
                      : Words.get('device_offline', activeLanguage),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _connectionMessage,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (_lastUpdated != null)
            Text(
              '${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(AppLanguage activeLanguage) {
    final List<Widget> voltageCards = [
      Expanded(
        child: _buildSensorCard(
          title: Words.get('r_voltage', activeLanguage),
          value: '${_rVoltage.toStringAsFixed(1)} V',
          icon: Icons.flash_on_rounded,
          color: Colors.red.shade600,
        ),
      ),
    ];

    final List<Widget> currentCards = [
      Expanded(
        child: _buildSensorCard(
          title: Words.get('r_current', activeLanguage),
          value: '${_rCurrent.toStringAsFixed(1)} A',
          icon: Icons.electric_meter_rounded,
          color: Colors.red.shade600,
        ),
      ),
    ];

    if (_phaseType >= 2) {
      voltageCards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _buildSensorCard(
            title: Words.get('y_voltage', activeLanguage),
            value: '${_yVoltage.toStringAsFixed(1)} V',
            icon: Icons.flash_on_rounded,
            color: Colors.amber.shade700,
          ),
        ),
      ]);

      currentCards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _buildSensorCard(
            title: Words.get('y_current', activeLanguage),
            value: '${_yCurrent.toStringAsFixed(1)} A',
            icon: Icons.electric_meter_rounded,
            color: Colors.amber.shade700,
          ),
        ),
      ]);
    }

    if (_phaseType >= 3) {
      voltageCards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _buildSensorCard(
            title: Words.get('b_voltage', activeLanguage),
            value: '${_bVoltage.toStringAsFixed(1)} V',
            icon: Icons.flash_on_rounded,
            color: Colors.blue.shade600,
          ),
        ),
      ]);

      currentCards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _buildSensorCard(
            title: Words.get('b_current', activeLanguage),
            value: '${_bCurrent.toStringAsFixed(1)} A',
            icon: Icons.electric_meter_rounded,
            color: Colors.blue.shade600,
          ),
        ),
      ]);
    }

    return Column(
      children: [
        Row(children: voltageCards),
        const SizedBox(height: 12),
        Row(children: currentCards),
      ],
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseAndFaultCard(AppLanguage activeLanguage) {
    final String displayFault = _phaseFailure
        ? 'PHASE FAILURE'
        : (_faultMessage == 'No fault'
              ? Words.get('no_fault', activeLanguage)
              : _faultMessage);

    final bool isError = _phaseFailure || _faultMessage != 'No fault';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      Words.get('frequency', activeLanguage),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_frequency.toStringAsFixed(1)} Hz',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: Colors.grey.shade300),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      Words.get('phase_sequence', activeLanguage),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _phaseSequence,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                isError
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: isError ? AppColors.error : AppColors.success,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Words.get('fault_status', activeLanguage),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      displayFault,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isError ? AppColors.error : AppColors.success,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
