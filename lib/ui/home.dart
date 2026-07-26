import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arisers/riverpod/session_provider.dart';
import 'package:arisers/ui/motor_controller.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // ============================================================
  // MQTT PUBLIC BROKER SETTINGS
  // ============================================================

  static const String mqttBroker = 'broker.emqx.io';
  static const int mqttPort = 1883;
  static const bool useTls = false;

  // Keep empty for the EMQX public broker.
  static const String mqttUsername = '';
  static const String mqttPassword = '';

  // ============================================================
  // MQTT OBJECTS
  // ============================================================

  MqttServerClient? _mqttClient;

  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _mqttSubscription;

  Timer? _sensorTimeoutTimer;

  bool _isConnecting = false;
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false;

  String _connectionMessage = 'MQTT disconnected';

  // ============================================================
  // DEVICE DETAILS FROM HIVE
  // ============================================================

  String _userKey = '';
  String _deviceName = '';
  String _controllerId = 'controller01';

  String _baseTopic = '';
  String _electricalTopic = '';
  String _availabilityTopic = '';

  // ============================================================
  // SENSOR VALUES
  // ============================================================

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

  // ============================================================
  // INITIAL SETUP
  // ============================================================

  Future<void> _initializeApplication() async {
    try {
      await _loadDeviceInformation();

      if (_deviceName.isEmpty) {
        throw Exception(
          'Device name was not found. Configure the ESP32 first.',
        );
      }

      _createMqttTopics();
      await _connectToEmqx();
    } catch (error) {
      final String message = _readableError(error);

      if (!mounted) {
        return;
      }

      setState(() {
        _isConnecting = false;
        _isMqttConnected = false;
        _connectionMessage = message;
      });

      _showSnackBar(message);
    }
  }

  // ============================================================
  // LOAD DEVICE INFORMATION
  // ============================================================

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

  // ============================================================
  // MQTT TOPICS
  // Must match the ESP32 code exactly.
  // ============================================================

  void _createMqttTopics() {
    _baseTopic = 'ariserskaruppiahs/$_deviceName/$_controllerId';

    _electricalTopic = '$_baseTopic/telemetry/all';

    _availabilityTopic = '$_baseTopic/status/connection';

    debugPrint('MQTT base topic: $_baseTopic');
    debugPrint('Electrical topic: $_electricalTopic');
    debugPrint('Availability topic: $_availabilityTopic');
  }

  // ============================================================
  // MQTT CONNECTION
  // ============================================================

  Future<void> _connectToEmqx() async {
    if (_isConnecting) {
      return;
    }

    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _isMqttConnected = false;
      _connectionMessage = 'Connecting to MQTT...';
    });

    final String clientId =
        'arisers-flutter-${_deviceName}-'
        '${DateTime.now().millisecondsSinceEpoch}';

    final MqttServerClient client = MqttServerClient.withPort(
      mqttBroker,
      clientId,
      mqttPort,
    );

    client.logging(on: false);
    client.keepAlivePeriod = 30;
    client.connectTimeoutPeriod = 20000;

    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;

    client.secure = useTls;

    if (useTls) {
      client.securityContext = SecurityContext.defaultContext;
    }

    client.onConnected = _onMqttConnected;
    client.onDisconnected = _onMqttDisconnected;
    client.onSubscribed = _onMqttSubscribed;
    client.onAutoReconnect = _onMqttAutoReconnect;
    client.onAutoReconnected = _onMqttAutoReconnected;
    client.pongCallback = _onMqttPong;

    MqttConnectMessage connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillTopic('$_baseTopic/app-availability')
        .withWillMessage(jsonEncode({'online': false, 'source': 'flutter'}))
        .withWillQos(MqttQos.atLeastOnce);

    if (mqttUsername.isNotEmpty) {
      connectionMessage = connectionMessage.authenticateAs(
        mqttUsername,
        mqttPassword,
      );
    }

    client.connectionMessage = connectionMessage;
    _mqttClient = client;

    try {
      await client.connect();
    } on SocketException catch (error) {
      client.disconnect();
      throw Exception('Network connection failed: ${error.message}');
    } on HandshakeException catch (error) {
      client.disconnect();
      throw Exception('TLS connection failed: ${error.message}');
    } catch (error) {
      client.disconnect();
      throw Exception('Could not connect to MQTT: $error');
    }

    final MqttConnectionState? state = client.connectionStatus?.state;

    if (state != MqttConnectionState.connected) {
      final MqttConnectReturnCode? returnCode =
          client.connectionStatus?.returnCode;

      client.disconnect();

      throw Exception('MQTT rejected the connection. Code: $returnCode');
    }

    _subscribeToTopics();
  }

  // ============================================================
  // MQTT SUBSCRIPTIONS
  // ============================================================

  void _subscribeToTopics() {
    final MqttServerClient? client = _mqttClient;

    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    client.subscribe(_electricalTopic, MqttQos.atLeastOnce);

    client.subscribe(_availabilityTopic, MqttQos.atLeastOnce);

    _mqttSubscription?.cancel();

    final Stream<List<MqttReceivedMessage<MqttMessage?>>>? updates =
        client.updates;

    if (updates == null) {
      debugPrint('MQTT updates stream unavailable.');
      return;
    }

    _mqttSubscription = updates.listen(
      _handleMqttMessages,
      onError: (Object error) {
        debugPrint('MQTT stream error: $error');

        if (!mounted) {
          return;
        }

        setState(() {
          _connectionMessage = 'MQTT communication error';
        });
      },
    );
  }

  // ============================================================
  // RECEIVE MQTT MESSAGES
  // ============================================================

  void _handleMqttMessages(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final MqttReceivedMessage<MqttMessage?> received in messages) {
      final MqttMessage? mqttMessage = received.payload;

      if (mqttMessage is! MqttPublishMessage) {
        continue;
      }

      final String topic = received.topic;

      final String payload = MqttPublishPayload.bytesToStringAsString(
        mqttMessage.payload.message,
      );

      debugPrint('MQTT topic: $topic');
      debugPrint('MQTT payload: $payload');

      if (topic == _electricalTopic) {
        _parseElectricalPayload(payload);
      } else if (topic == _availabilityTopic) {
        _parseAvailabilityPayload(payload);
      }
    }
  }

  // ============================================================
  // PARSE ESP32 COMBINED PZEM TELEMETRY
  // ============================================================

  void _parseElectricalPayload(String payload) {
    try {
      final dynamic decoded = jsonDecode(payload);

      if (decoded is! Map) {
        throw const FormatException('Telemetry payload must be a JSON object.');
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(decoded);

      final Map<String, dynamic> phases = _convertToMap(data['phases']);

      final Map<String, dynamic> rPhase = _convertToMap(phases['r']);

      final Map<String, dynamic> yPhase = _convertToMap(phases['y']);

      final Map<String, dynamic> bPhase = _convertToMap(phases['b']);

      final double rVoltage = _toDouble(rPhase['voltage']);

      final double yVoltage = _toDouble(yPhase['voltage']);

      final double bVoltage = _toDouble(bPhase['voltage']);

      final double rCurrent = _toDouble(rPhase['current']);

      final double yCurrent = _toDouble(yPhase['current']);

      final double bCurrent = _toDouble(bPhase['current']);

      final double rFrequency = _toDouble(rPhase['frequency']);

      final double yFrequency = _toDouble(yPhase['frequency']);

      final double bFrequency = _toDouble(bPhase['frequency']);

      final List<double> validFrequencies = <double>[
        rFrequency,
        yFrequency,
        bFrequency,
      ].where((double value) => value > 0).toList();

      double averageFrequency = 0;

      if (validFrequencies.isNotEmpty) {
        averageFrequency =
            validFrequencies.reduce((double a, double b) => a + b) /
            validFrequencies.length;
      }

      final bool rValid = _toBool(rPhase['valid']);
      final bool yValid = _toBool(yPhase['valid']);
      final bool bValid = _toBool(bPhase['valid']);

      final bool phaseFailure = !rValid || !yValid || !bValid;

      final String faultMessage = phaseFailure
          ? 'One or more PZEM modules are unavailable'
          : 'No fault';

      if (!mounted) {
        return;
      }

      setState(() {
        _rVoltage = rVoltage;
        _yVoltage = yVoltage;
        _bVoltage = bVoltage;

        _rCurrent = rCurrent;
        _yCurrent = yCurrent;
        _bCurrent = bCurrent;

        _frequency = averageFrequency;

        _phaseSequence = 'R-Y-B';
        _phaseFailure = phaseFailure;
        _faultMessage = faultMessage;

        _lastUpdated = DateTime.now();
        _isDeviceOnline = true;
      });

      _startSensorTimeout();
    } catch (error) {
      debugPrint('Telemetry parsing error: $error');
      debugPrint('Invalid payload: $payload');
    }
  }

  // ============================================================
  // PARSE DEVICE AVAILABILITY
  // ============================================================

  void _parseAvailabilityPayload(String payload) {
    try {
      bool online;

      try {
        final dynamic decoded = jsonDecode(payload);

        if (decoded is Map) {
          online = _toBool(decoded['online']);
        } else {
          online = _toBool(decoded);
        }
      } catch (_) {
        online = _toBool(payload);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isDeviceOnline = online;
      });

      if (!online) {
        _sensorTimeoutTimer?.cancel();
      }
    } catch (error) {
      debugPrint('Availability parsing error: $error');
    }
  }

  // ============================================================
  // SENSOR TIMEOUT
  // ============================================================

  void _startSensorTimeout() {
    _sensorTimeoutTimer?.cancel();

    _sensorTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _isDeviceOnline = false;
      });
    });
  }

  // ============================================================
  // DATA CONVERSION
  // ============================================================

  Map<String, dynamic> _convertToMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map(
        (dynamic key, dynamic item) => MapEntry(key.toString(), item),
      );
    }

    return <String, dynamic>{};
  }

  double _toDouble(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString().trim()) ?? 0;
  }

  bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final String text = value?.toString().trim().toLowerCase() ?? '';

    return text == 'true' ||
        text == '1' ||
        text == 'yes' ||
        text == 'online' ||
        text == 'active';
  }

  // ============================================================
  // MQTT CALLBACKS
  // ============================================================

  void _onMqttConnected() {
    debugPrint('Connected to MQTT');

    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = false;
      _isMqttConnected = true;
      _connectionMessage = 'Connected — waiting for ESP32 data';
    });
  }

  void _onMqttDisconnected() {
    debugPrint('Disconnected from MQTT');

    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = false;
      _isMqttConnected = false;
      _isDeviceOnline = false;
      _connectionMessage = 'Disconnected from MQTT';
    });
  }

  void _onMqttSubscribed(String topic) {
    debugPrint('Subscribed: $topic');
  }

  void _onMqttAutoReconnect() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionMessage = 'Reconnecting to MQTT...';
    });
  }

  void _onMqttAutoReconnected() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isConnecting = false;
      _isMqttConnected = true;
      _connectionMessage = 'Reconnected — waiting for ESP32 data';
    });
  }

  void _onMqttPong() {
    debugPrint('MQTT pong received');
  }

  // ============================================================
  // MANUAL RECONNECT
  // ============================================================

  Future<void> _reconnectMqtt() async {
    _sensorTimeoutTimer?.cancel();

    await _mqttSubscription?.cancel();
    _mqttSubscription = null;

    _mqttClient?.disconnect();
    _mqttClient = null;

    if (mounted) {
      setState(() {
        _isMqttConnected = false;
        _isDeviceOnline = false;
        _connectionMessage = 'Reconnecting...';
      });
    }

    await _initializeApplication();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double width = screenSize.width;
    final double height = screenSize.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: Colors.lightGreen,
        centerTitle: true,
        title: const Text(
          'ARISERS',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reconnect',
            onPressed: _isConnecting ? null : _reconnectMqtt,
            icon: _isConnecting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white, size: 30),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reconnectMqtt,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(width * 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionCard(),
                SizedBox(height: height * 0.02),
                _buildSensorCard(),
                SizedBox(height: height * 0.025),
                _buildMenuButton(
                  icon: Icons.power_settings_new,
                  title: 'Motor Control',
                  subtitle: 'Control Motor 1 and Motor 2',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MotorController(
                          mqttClient: _mqttClient,
                          baseTopic: _baseTopic,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final Color mqttStatusColor = _isMqttConnected ? Colors.green : Colors.red;

    final String deviceStatusText = _isDeviceOnline
        ? 'Device online'
        : 'Device offline';

    final Color deviceStatusColor = _isDeviceOnline
        ? Colors.green
        : Colors.orange;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: mqttStatusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _connectionMessage,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isConnecting ? null : _reconnectMqtt,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Icon(Icons.memory, color: deviceStatusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device: ${_deviceName.isEmpty ? '--' : _deviceName}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  deviceStatusText,
                  style: TextStyle(
                    color: deviceStatusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.lightGreen,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sensors, color: Colors.white, size: 27),
              SizedBox(width: 8),
              Text(
                'Three-Phase Sensor Data',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildPhaseHeader(),
          const SizedBox(height: 8),
          _buildPhaseDataRow(
            phaseName: 'R',
            voltage: _rVoltage,
            current: _rCurrent,
          ),
          const Divider(color: Colors.white54),
          _buildPhaseDataRow(
            phaseName: 'Y',
            voltage: _yVoltage,
            current: _yCurrent,
          ),
          const Divider(color: Colors.white54),
          _buildPhaseDataRow(
            phaseName: 'B',
            voltage: _bVoltage,
            current: _bCurrent,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildExtraValue(
                  label: 'Frequency',
                  value: '${_frequency.toStringAsFixed(1)} Hz',
                ),
                const SizedBox(height: 8),
                _buildExtraValue(
                  label: 'Phase Sequence',
                  value: _phaseSequence,
                ),
                const SizedBox(height: 8),
                _buildExtraValue(
                  label: 'Phase Status',
                  value: _phaseFailure ? 'Phase Failure' : 'Phase Healthy',
                ),
                const SizedBox(height: 8),
                _buildExtraValue(label: 'Fault', value: _faultMessage),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _lastUpdated == null
                ? 'Waiting for first sensor message'
                : 'Last updated: '
                      '${_formatTime(_lastUpdated!)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseHeader() {
    return const Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            'Phase',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            'Voltage',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            'Current',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseDataRow({
    required String phaseName,
    required double voltage,
    required double current,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white,
              child: Text(
                phaseName,
                style: const TextStyle(
                  color: Colors.lightGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '${voltage.toStringAsFixed(1)} V',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '${current.toStringAsFixed(2)} A',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraValue({required String label, required String value}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.lightGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.lightGreen, size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    final String second = time.second.toString().padLeft(2, '0');

    return '$hour:$minute:$second';
  }

  String _readableError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
