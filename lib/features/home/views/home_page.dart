import 'dart:async';
import 'dart:convert';

import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/features/home/providers/cyclic_timer_provider.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';
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
  static const List<String> publicBrokers = [
    'test.mosquitto.org',
    'broker.emqx.io',
    'broker.hivemq.com',
  ];
  static const int mqttPort = 1883;

  int _selectedTabIndex = 0;

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
    _setupAutomationHandlers();
  }

  @override
  void dispose() {
    _sensorTimeoutTimer?.cancel();
    _mqttSubscription?.cancel();
    _mqttClient?.disconnect();
    super.dispose();
  }

  void _setupAutomationHandlers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(schedulerProvider.notifier).setCommandHandler(_sendMqttCommand);
      ref
          .read(cyclicTimerProvider.notifier)
          .setCommandHandler(_sendMqttCommand);

      ref.read(schedulerProvider.notifier).setMqttSyncHandler(
            (payload) => _publishConfigMqtt('$_baseTopic/config/scheduler', payload),
          );

      ref.read(cyclicTimerProvider.notifier).setMqttSyncHandler(
            (payload) => _publishConfigMqtt('$_baseTopic/config/cyclic', payload),
          );
    });
  }

  void _publishConfigMqtt(String topic, String payload) {
    final MqttServerClient? client = _mqttClient;
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected ||
        topic.isEmpty) {
      return;
    }

    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: true);
    debugPrint('Published Config to ESP32 [$topic]: $payload');
  }

  void _sendMqttCommand(String motorName, bool turnOn) {
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
    final Box<dynamic> sessionBox = Hive.box('sessionBox');

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
          }
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
    });
  }

  void _createMqttTopics() {
    final String safeDeviceName = _deviceName.trim();

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

    final String clientIdentifier =
        'arisers_${DateTime.now().millisecondsSinceEpoch % 1000000}';

    for (final String host in publicBrokers) {
      if (!mounted) return;

      setState(() {
        _connectionMessage = 'Connecting to $host...';
      });

      debugPrint('Attempting MQTT connection to $host:$mqttPort...');

      final MqttServerClient client = MqttServerClient.withPort(
        host,
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
        await client.connect();

        if (client.connectionStatus?.state == MqttConnectionState.connected) {
          debugPrint('Successfully connected to $host');
          if (!mounted) return;

          setState(() {
            _isConnecting = false;
            _isMqttConnected = true;
            _connectionMessage = 'Connected to $host';
          });

          _subscribeToTelemetryTopics();
          return;
        }
      } catch (error) {
        debugPrint('Failed to connect to $host: $error');
        client.disconnect();
      }
    }

    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _isMqttConnected = false;
      _connectionMessage = 'Broker connection failed';
    });

    UIHelpers.showSnackBar(
      context,
      message: 'Could not connect to any MQTT public broker. Check internet connection.',
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

      if (pFail && !_phaseFailure) {
        // Record Safety Trip Log
        ref.read(dataLogProvider.notifier).addLog(
              motorName: 'System',
              action: 'OFF',
              trigger: 'Safety Trip',
              details: fault,
            );
      }

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
        title: Text(_deviceName.isEmpty ? 'ARISERS' : _deviceName.toUpperCase()),
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

  Widget _buildDashboardView(AppLanguage activeLanguage) {
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
                onLogEvent: (motorName, action, trigger) {
                  ref.read(dataLogProvider.notifier).addLog(
                        motorName: motorName,
                        action: action,
                        trigger: trigger,
                      );
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

  Widget _buildTelemetryGrid(AppLanguage activeLanguage) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                title: Words.get('r_voltage', activeLanguage),
                value: '${_rVoltage.toStringAsFixed(1)} V',
                icon: Icons.flash_on_rounded,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: Words.get('y_voltage', activeLanguage),
                value: '${_yVoltage.toStringAsFixed(1)} V',
                icon: Icons.flash_on_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: Words.get('b_voltage', activeLanguage),
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
                title: Words.get('r_current', activeLanguage),
                value: '${_rCurrent.toStringAsFixed(1)} A',
                icon: Icons.electric_meter_rounded,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: Words.get('y_current', activeLanguage),
                value: '${_yCurrent.toStringAsFixed(1)} A',
                icon: Icons.electric_meter_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                title: Words.get('b_current', activeLanguage),
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

  Widget _buildPhaseAndFaultCard(AppLanguage activeLanguage) {
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
                Words.get('frequency', activeLanguage),
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
                Words.get('phase_sequence', activeLanguage),
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
                Words.get('fault_status', activeLanguage),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                _phaseFailure
                    ? 'PHASE FAILURE'
                    : (_faultMessage == 'No fault'
                        ? Words.get('no_fault', activeLanguage)
                        : _faultMessage),
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
