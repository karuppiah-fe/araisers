import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MotorController extends StatefulWidget {
  const MotorController({
    required this.mqttClient,
    required this.baseTopic,
    super.key,
  });

  final MqttServerClient? mqttClient;
  final String baseTopic;

  @override
  State<MotorController> createState() => _MotorControllerState();
}

class _MotorControllerState extends State<MotorController> {
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _statusSubscription;

  bool _motor1On = false;
  bool _motor2On = false;

  bool _motor1PulseActive = false;
  bool _motor2PulseActive = false;

  String _motor1Status = 'Unknown';
  String _motor2Status = 'Unknown';

  bool get _isConnected {
    return widget.mqttClient?.connectionStatus?.state ==
        MqttConnectionState.connected;
  }

  String get _motor1CommandTopic => '${widget.baseTopic}/command/motor1';

  String get _motor2CommandTopic => '${widget.baseTopic}/command/motor2';

  String get _motor1StatusTopic => '${widget.baseTopic}/status/motor1';

  String get _motor2StatusTopic => '${widget.baseTopic}/status/motor2';

  @override
  void initState() {
    super.initState();
    _subscribeToMotorStatus();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToMotorStatus() {
    final MqttServerClient? client = widget.mqttClient;

    if (client == null || !_isConnected) {
      return;
    }

    client.subscribe(_motor1StatusTopic, MqttQos.atLeastOnce);

    client.subscribe(_motor2StatusTopic, MqttQos.atLeastOnce);

    final Stream<List<MqttReceivedMessage<MqttMessage?>>>? updates =
        client.updates;

    if (updates == null) {
      return;
    }

    _statusSubscription = updates.listen(_handleMotorStatusMessages);
  }

  void _handleMotorStatusMessages(
    List<MqttReceivedMessage<MqttMessage?>> messages,
  ) {
    for (final MqttReceivedMessage<MqttMessage?> received in messages) {
      final MqttMessage? mqttMessage = received.payload;

      if (mqttMessage is! MqttPublishMessage) {
        continue;
      }

      final String payload = MqttPublishPayload.bytesToStringAsString(
        mqttMessage.payload.message,
      );

      if (received.topic == _motor1StatusTopic) {
        _updateMotorStatus(motorNumber: 1, payload: payload);
      } else if (received.topic == _motor2StatusTopic) {
        _updateMotorStatus(motorNumber: 2, payload: payload);
      }
    }
  }

  void _updateMotorStatus({required int motorNumber, required String payload}) {
    String statusText = payload.trim();
    bool pulseActive = false;
    bool motorOn = false;

    try {
      final dynamic decoded = jsonDecode(payload);

      if (decoded is Map) {
        statusText = decoded['state']?.toString() ?? statusText;

        pulseActive = _toBool(decoded['pulseActive']);

        final String normalized = statusText.trim().toUpperCase();

        motorOn = normalized == 'ON' || normalized == 'STARTING';
      } else {
        motorOn = _toBool(decoded);
      }
    } catch (_) {
      final String normalized = statusText.trim().toUpperCase();

      motorOn = normalized == 'ON' || normalized == 'STARTING';

      pulseActive = normalized == 'STARTING' || normalized == 'STOPPING';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (motorNumber == 1) {
        _motor1On = motorOn;
        _motor1PulseActive = pulseActive;
        _motor1Status = statusText;
      } else {
        _motor2On = motorOn;
        _motor2PulseActive = pulseActive;
        _motor2Status = statusText;
      }
    });
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
        text == 'on' ||
        text == 'online' ||
        text == 'active';
  }

  Future<void> _sendMotorCommand({
    required int motorNumber,
    required bool turnOn,
  }) async {
    final MqttServerClient? client = widget.mqttClient;

    if (client == null || !_isConnected) {
      _showMessage('MQTT is not connected.', isError: true);
      return;
    }

    final bool pulseActive = motorNumber == 1
        ? _motor1PulseActive
        : _motor2PulseActive;

    if (pulseActive) {
      _showMessage(
        'Motor $motorNumber relay pulse is still active.',
        isError: true,
      );
      return;
    }

    final String topic = motorNumber == 1
        ? _motor1CommandTopic
        : _motor2CommandTopic;

    final String command = turnOn ? 'ON' : 'OFF';

    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();

    builder.addString(command);

    final int messageId = client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: false,
    );

    if (messageId <= 0) {
      _showMessage('Motor command could not be published.', isError: true);
      return;
    }

    if (mounted) {
      setState(() {
        if (motorNumber == 1) {
          _motor1PulseActive = true;
          _motor1Status = turnOn ? 'STARTING' : 'STOPPING';
        } else {
          _motor2PulseActive = true;
          _motor2Status = turnOn ? 'STARTING' : 'STOPPING';
        }
      });
    }

    _showMessage('Motor $motorNumber $command command sent.');

    // Local safety timeout. ESP32 status should normally clear this.
    Timer(const Duration(seconds: 8), () {
      if (!mounted) {
        return;
      }

      setState(() {
        if (motorNumber == 1) {
          _motor1PulseActive = false;
        } else {
          _motor2PulseActive = false;
        }
      });
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: Colors.lightGreen,
        centerTitle: true,
        title: const Text(
          'Motor Control',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 18),
            _buildMotorCard(
              motorNumber: 1,
              isOn: _motor1On,
              status: _motor1Status,
              pulseActive: _motor1PulseActive,
            ),
            const SizedBox(height: 18),
            _buildMotorCard(
              motorNumber: 2,
              isOn: _motor2On,
              status: _motor2Status,
              pulseActive: _motor2PulseActive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final bool connected = _isConnected;

    return Card(
      child: ListTile(
        leading: Icon(
          connected ? Icons.cloud_done : Icons.cloud_off,
          color: connected ? Colors.green : Colors.red,
        ),
        title: Text(
          connected ? 'MQTT connected' : 'MQTT disconnected',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(widget.baseTopic),
      ),
    );
  }

  Widget _buildMotorCard({
    required int motorNumber,
    required bool isOn,
    required String status,
    required bool pulseActive,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isOn
                      ? Colors.green.shade100
                      : Colors.grey.shade200,
                  child: Icon(
                    Icons.settings_input_component,
                    color: isOn ? Colors.green : Colors.grey.shade700,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Motor $motorNumber',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: $status',
                        style: TextStyle(
                          color: pulseActive
                              ? Colors.orange
                              : isOn
                              ? Colors.green
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pulseActive)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'The ESP32 activates the selected relay for 6 seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isConnected || pulseActive
                        ? null
                        : () {
                            _sendMotorCommand(
                              motorNumber: motorNumber,
                              turnOn: true,
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isConnected || pulseActive
                        ? null
                        : () {
                            _sendMotorCommand(
                              motorNumber: motorNumber,
                              turnOn: false,
                            );
                          },
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
