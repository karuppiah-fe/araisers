import 'dart:async';
import 'dart:convert';

import 'package:arisers/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MotorControllerWidget extends StatefulWidget {
  const MotorControllerWidget({
    required this.mqttClient,
    required this.baseTopic,
    this.onLogEvent,
    super.key,
  });

  final MqttServerClient? mqttClient;
  final String baseTopic;
  final Function(String motorName, String action, String trigger)? onLogEvent;

  @override
  State<MotorControllerWidget> createState() => _MotorControllerWidgetState();
}

class _MotorControllerWidgetState extends State<MotorControllerWidget> {
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
    for (final message in messages) {
      final String topic = message.topic;
      final MqttPublishMessage publishMessage =
          message.payload as MqttPublishMessage;

      final String rawPayload = utf8.decode(
        publishMessage.payload.message,
        allowMalformed: true,
      );

      final String payload = rawPayload.trim();

      if (!mounted) return;

      setState(() {
        if (topic == _motor1StatusTopic) {
          _motor1Status = payload;
          _motor1On = _isMotorOnPayload(payload);
        } else if (topic == _motor2StatusTopic) {
          _motor2Status = payload;
          _motor2On = _isMotorOnPayload(payload);
        }
      });
    }
  }

  bool _isMotorOnPayload(String payload) {
    final String cleanPayload = payload.toUpperCase();

    return cleanPayload == 'ON' ||
        cleanPayload == 'RUNNING' ||
        cleanPayload == '1' ||
        cleanPayload == 'TRUE' ||
        cleanPayload == 'START';
  }

  Future<void> _toggleMotor1Toggle() async {
    final bool nextState = !_motor1On;
    final String command = nextState ? 'ON' : 'OFF';

    await _publishMqttMessage(_motor1CommandTopic, command);
    widget.onLogEvent?.call('Motor 1', command, 'Manual');

    if (!mounted) return;

    setState(() {
      _motor1On = nextState;
      _motor1Status = nextState ? 'ON (Command sent)' : 'OFF (Command sent)';
    });
  }

  Future<void> _toggleMotor2Toggle() async {
    final bool nextState = !_motor2On;
    final String command = nextState ? 'ON' : 'OFF';

    await _publishMqttMessage(_motor2CommandTopic, command);
    widget.onLogEvent?.call('Motor 2', command, 'Manual');

    if (!mounted) return;

    setState(() {
      _motor2On = nextState;
      _motor2Status = nextState ? 'ON (Command sent)' : 'OFF (Command sent)';
    });
  }

  Future<void> _sendMotor1Pulse(String command) async {
    setState(() {
      _motor1PulseActive = true;
    });

    await _publishMqttMessage(_motor1CommandTopic, command);
    widget.onLogEvent?.call('Motor 1', command == 'START' ? 'ON' : 'OFF', 'Manual');

    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _motor1PulseActive = false;
      _motor1Status = '$command (Pulse sent)';
    });
  }

  Future<void> _sendMotor2Pulse(String command) async {
    setState(() {
      _motor2PulseActive = true;
    });

    await _publishMqttMessage(_motor2CommandTopic, command);
    widget.onLogEvent?.call('Motor 2', command == 'START' ? 'ON' : 'OFF', 'Manual');

    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _motor2PulseActive = false;
      _motor2Status = '$command (Pulse sent)';
    });
  }

  Future<void> _publishMqttMessage(String topic, String payload) async {
    final MqttServerClient? client = widget.mqttClient;

    if (client == null || !_isConnected) {
      _showSnackBar('MQTT is not connected');
      return;
    }

    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMotorCard(
          title: 'Motor 1',
          isOn: _motor1On,
          statusText: _motor1Status,
          isPulseActive: _motor1PulseActive,
          onToggle: _toggleMotor1Toggle,
          onStart: () => _sendMotor1Pulse('START'),
          onStop: () => _sendMotor1Pulse('STOP'),
        ),
        const SizedBox(height: 16),
        _buildMotorCard(
          title: 'Motor 2',
          isOn: _motor2On,
          statusText: _motor2Status,
          isPulseActive: _motor2PulseActive,
          onToggle: _toggleMotor2Toggle,
          onStart: () => _sendMotor2Pulse('START'),
          onStop: () => _sendMotor2Pulse('STOP'),
        ),
      ],
    );
  }

  Widget _buildMotorCard({
    required String title,
    required bool isOn,
    required String statusText,
    required bool isPulseActive,
    required VoidCallback onToggle,
    required VoidCallback onStart,
    required VoidCallback onStop,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isOn ? AppColors.primaryLight : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOn
                      ? AppColors.primaryLight.withValues(alpha: 0.25)
                      : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: isOn ? AppColors.primaryDark : Colors.grey.shade600,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 2),
                    Text(
                      'Status: $statusText',
                      style: TextStyle(
                        fontSize: 13,
                        color: isOn ? AppColors.primaryDark : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isOn,
                onChanged: _isConnected ? (_) => onToggle() : null,
                activeColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnected && !isPulseActive ? onStart : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Start Pulse'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConnected && !isPulseActive ? onStop : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  label: const Text('Stop Pulse'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
