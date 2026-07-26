import 'dart:async';
import 'dart:convert';

import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/auth/views/first_page.dart';
import 'package:arisers/features/home/views/widgets/motor_controller_widget.dart';
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
  static const String mqttBroker = 'broker.hivemq.com';
  static const int mqttPort = 1883;

  // MQTT OBJECTS
  MqttServerClient? _mqttClient;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _mqttSubscription;

  Timer? _sensorTimeoutTimer;

  bool _isConnecting = false;
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false;

  String _connectionMessage = 'MQTT disconnected';

  // DEVICE DETAILS FROM HIVE
  String _userKey = '';
  String _deviceName = '';
  String _controllerId = 'controller01';

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

  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _initializeApplication();
  }

  @override
  void dispose() {
    _sensorTimeoutTimer?.cancel();
    _mqttSubscription?.cancel();
    _mqttClient?.disconnect();
    super.dispose();
  }

  Future<void> _initializeApplication() async {
    try {
      await _loadDeviceInformation();

      if (_deviceName.isEmpty) {
        throw Exception(
          'Device name was not found. Configure the ESP32 first.',
        );
      }

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

      UIHelpers.showSnackBar(
        context,
        message: message,
        color: AppColors.error,
      );
    }
  }

  Future<void> _loadDeviceInformation() async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    _userKey = sessionBox.get('userKey', defaultValue: '').toString().trim();

    String storedDeviceName = sessionBox
        .get('deviceName', defaultValue: '')
        .toString()
        .trim();

    if (storedDeviceName.isEmpty && _userKey.isNotEmpty) {
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
            if (devData['wifiSsid'] != null) {
              await sessionBox.put('wifiSsid', devData['wifiSsid'].toString());
            }
            if (devData['phase'] != null) {
              await sessionBox.put('phase', devData['phase']);
            }
          }
        }

        if (storedDeviceName.isEmpty) {
          final DatabaseReference arisersRef = FirebaseDatabase.instance.ref(
            'arisers',
          );
          final DataSnapshot arisersSnapshot = await arisersRef.get();

          if (arisersSnapshot.exists && arisersSnapshot.value is Map) {
            final Map<dynamic, dynamic> usersMap = Map<dynamic, dynamic>.from(
              arisersSnapshot.value as Map,
            );

            for (final entry in usersMap.entries) {
              final Object? userVal = entry.value;
              if (userVal is! Map) continue;

              final Map<dynamic, dynamic> userMap = Map<dynamic, dynamic>.from(
                userVal,
              );
              final Object? devInfoVal = userMap['deviceInfo'];

              if (devInfoVal is Map) {
                final Map<String, dynamic> devInfo = Map<String, dynamic>.from(
                  devInfoVal,
                );
                final String name =
                    devInfo['deviceName']?.toString().trim() ?? '';
                final bool configured = devInfo['configured'] == true;

                if (configured && name.isNotEmpty) {
                  storedDeviceName = name;
                  await sessionBox.put('deviceName', name);
                  await sessionBox.put('deviceConfigured', true);
                  if (devInfo['wifiSsid'] != null) {
                    await sessionBox.put(
                      'wifiSsid',
                      devInfo['wifiSsid'].toString(),
                    );
                  }
                  if (devInfo['phase'] != null) {
                    await sessionBox.put('phase', devInfo['phase']);
                  }

                  await deviceRef.update({
                    'deviceName': name,
                    'wifiSsid': devInfo['wifiSsid'] ?? '',
                    'phase': devInfo['phase'] ?? 1,
                    'bluetoothName': devInfo['bluetoothName'] ?? 'arisers',
                    'bluetoothType': devInfo['bluetoothType'] ?? 'classic',
                    'configured': true,
                    'updatedAt': ServerValue.timestamp,
                  });
                  break;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error syncing device information in Home: $e');
      }
    }

    final String storedControllerId = sessionBox
        .get('controllerId', defaultValue: 'controller01')
        .toString();

    _deviceName = _sanitizeTopicLevel(storedDeviceName);

    _controllerId = storedControllerId.trim().isEmpty
        ? 'controller01'
        : _sanitizeTopicLevel(storedControllerId);

    debugPrint('Hive user key: $_userKey');
    debugPrint('Hive device name: $_deviceName');
    debugPrint('Controller ID: $_controllerId');
  }

  String _sanitizeTopicLevel(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[/+#\s]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _createMqttTopics() {
    _baseTopic = 'ariserskaruppiahs/$_deviceName/$_controllerId';
    _electricalTopic = '$_baseTopic/telemetry/all';
    _availabilityTopic = '$_baseTopic/status/connection';

    debugPrint('MQTT base topic: $_baseTopic');
    debugPrint('Electrical topic: $_electricalTopic');
    debugPrint('Availability topic: $_availabilityTopic');
  }

  Future<void> _connectToMqttBroker() async {
    if (_isConnecting) return;

    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = true;
      _connectionMessage = 'Connecting to HiveMQ broker...';
    });

    final String clientIdentifier =
        'arisers_${DateTime.now().millisecondsSinceEpoch % 1000000}';

    // 1. Attempt TCP Port 1883
    MqttServerClient client = MqttServerClient.withPort(
      mqttBroker,
      clientIdentifier,
      mqttPort,
    );

    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.useWebSocket = false;
    client.secure = false;
    client.connectTimeoutPeriod = 15000;

    client.onConnected = _onMqttConnected;
    client.onDisconnected = _onMqttDisconnected;

    final MqttConnectMessage connectMessage = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client.connectionMessage = connectMessage;
    _mqttClient = client;

    try {
      debugPrint('Attempting TCP connection to $mqttBroker:$mqttPort...');
      await client.connect();

      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        debugPrint('Successfully connected to $mqttBroker via TCP');
        if (!mounted) return;

        setState(() {
          _isConnecting = false;
          _isMqttConnected = true;
          _connectionMessage = 'Connected to $mqttBroker';
        });

        _subscribeToTelemetryTopics();
        return;
      }
    } catch (tcpError) {
      debugPrint('TCP Connection to HiveMQ failed: $tcpError. Trying WebSocket port 8000...');
      client.disconnect();
    }

    // 2. Attempt WebSocket Port 8000 Fallback
    try {
      final MqttServerClient wsClient = MqttServerClient.withPort(
        mqttBroker,
        '${clientIdentifier}_ws',
        8000,
      );

      wsClient.logging(on: false);
      wsClient.keepAlivePeriod = 20;
      wsClient.autoReconnect = true;
      wsClient.resubscribeOnAutoReconnect = true;
      wsClient.useWebSocket = true;
      wsClient.websocketProtocols = ['mqtt'];
      wsClient.secure = false;
      wsClient.connectTimeoutPeriod = 5000;

      wsClient.onConnected = _onMqttConnected;
      wsClient.onDisconnected = _onMqttDisconnected;
      wsClient.connectionMessage = connectMessage;

      _mqttClient = wsClient;
      debugPrint('Attempting WebSocket connection to $mqttBroker:8000...');
      await wsClient.connect();

      if (wsClient.connectionStatus?.state == MqttConnectionState.connected) {
        debugPrint('Successfully connected to $mqttBroker via WebSocket (8000)');
        if (!mounted) return;

        setState(() {
          _isConnecting = false;
          _isMqttConnected = true;
          _connectionMessage = 'Connected to $mqttBroker (WS)';
        });

        _subscribeToTelemetryTopics();
        return;
      }
    } catch (wsError) {
      debugPrint('WebSocket Connection to HiveMQ failed: $wsError');
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _isMqttConnected = false;
      _connectionMessage = 'HiveMQ connection failed';
    });

    UIHelpers.showSnackBar(
      context,
      message: 'Could not connect to HiveMQ broker. Check internet connection.',
      color: AppColors.error,
    );
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

      if (topic == _availabilityTopic) {
        _handleDeviceAvailability(payload);
      }

      if (topic == _electricalTopic ||
          payload.contains('rVoltage') ||
          payload.contains('voltage') ||
          payload.contains('phases')) {
        _handleElectricalTelemetry(payload);
      }
    }
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
      } else if (isExplicitOnline) {
        _isDeviceOnline = true;
      }
    });
  }

  void _handleElectricalTelemetry(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);

      if (decoded is! Map<String, dynamic>) return;

      final Map<String, dynamic>? phases =
          decoded['phases'] is Map ? Map<String, dynamic>.from(decoded['phases']) : null;

      final Map<String, dynamic>? rPhase =
          phases?['r'] is Map ? Map<String, dynamic>.from(phases!['r']) : null;
      final Map<String, dynamic>? yPhase =
          phases?['y'] is Map ? Map<String, dynamic>.from(phases!['y']) : null;
      final Map<String, dynamic>? bPhase =
          phases?['b'] is Map ? Map<String, dynamic>.from(phases!['b']) : null;

      final double rV = _parseDouble(
        decoded['rVoltage'] ?? decoded['vr'] ?? rPhase?['voltage'],
      );
      final double yV = _parseDouble(
        decoded['yVoltage'] ?? decoded['vy'] ?? yPhase?['voltage'],
      );
      final double bV = _parseDouble(
        decoded['bVoltage'] ?? decoded['vb'] ?? bPhase?['voltage'],
      );

      final double rA = _parseDouble(
        decoded['rCurrent'] ?? decoded['ir'] ?? rPhase?['current'],
      );
      final double yA = _parseDouble(
        decoded['yCurrent'] ?? decoded['iy'] ?? yPhase?['current'],
      );
      final double bA = _parseDouble(
        decoded['bCurrent'] ?? decoded['ib'] ?? bPhase?['current'],
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

      if (!mounted) return;

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
        _isDeviceOnline = true;
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

  Future<void> _logoutUser() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await ref.read(sessionProvider.notifier).logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FirstPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_deviceName.isEmpty ? 'ARISERS' : _deviceName.toUpperCase()),
        actions: [
          IconButton(
            onPressed: _initializeApplication,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Connection',
          ),
          IconButton(
            onPressed: _logoutUser,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _initializeApplication,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusBanner(),
                const SizedBox(height: 16),
                _buildTelemetryGrid(),
                const SizedBox(height: 16),
                _buildPhaseAndFaultCard(),
                const SizedBox(height: 20),
                MotorControllerWidget(
                  mqttClient: _mqttClient,
                  baseTopic: _baseTopic,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
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
                  online ? 'Device Online' : 'Device Offline',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _connectionMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
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

  Widget _buildTelemetryGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                title: 'R Voltage',
                value: '${_rVoltage.toStringAsFixed(1)} V',
                icon: Icons.flash_on_rounded,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: 'Y Voltage',
                value: '${_yVoltage.toStringAsFixed(1)} V',
                icon: Icons.flash_on_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: 'B Voltage',
                value: '${_bVoltage.toStringAsFixed(1)} V',
                icon: Icons.flash_on_rounded,
                color: Colors.blue.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                title: 'R Current',
                value: '${_rCurrent.toStringAsFixed(1)} A',
                icon: Icons.electric_meter_rounded,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: 'Y Current',
                value: '${_yCurrent.toStringAsFixed(1)} A',
                icon: Icons.electric_meter_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: 'B Current',
                value: '${_bCurrent.toStringAsFixed(1)} A',
                icon: Icons.electric_meter_rounded,
                color: Colors.blue.shade600,
              ),
            ),
          ],
        ),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseAndFaultCard() {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text(
                'Frequency',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
          Container(width: 1, height: 36, color: Colors.grey.shade300),
          Column(
            children: [
              Text(
                'Sequence',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
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
          Container(width: 1, height: 36, color: Colors.grey.shade300),
          Column(
            children: [
              Text(
                'Fault Status',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                _phaseFailure ? 'PHASE FAILURE' : _faultMessage,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _phaseFailure ? AppColors.error : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
