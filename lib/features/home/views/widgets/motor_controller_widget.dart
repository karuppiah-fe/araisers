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
    this.isVoltageValid = true,
    this.faultMessage = '',
    this.rCurrent = 0.0,
    this.yCurrent = 0.0,
    this.bCurrent = 0.0,
    this.motor1ExternalStatus,
    this.motor2ExternalStatus,
    this.motor1TelemetryState,
    this.motor2TelemetryState,
    this.onLogEvent,
    super.key,
  });

  final MqttServerClient? mqttClient;
  final String baseTopic;
  final bool isVoltageValid;
  final String faultMessage;
  final double rCurrent;
  final double yCurrent;
  final double bCurrent;
  final String? motor1ExternalStatus;
  final String? motor2ExternalStatus;
  final String? motor1TelemetryState;
  final String? motor2TelemetryState;
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

  bool _motor1IsManual = false;
  bool _motor2IsManual = false;

  DateTime? _lastAppCommandTimeMotor1;
  DateTime? _lastAppCommandTimeMotor2;

  String _motor1Status = 'OFF';
  String _motor2Status = 'OFF';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluateExternalStates(null);
    });
  }

  @override
  void didUpdateWidget(covariant MotorControllerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_statusSubscription == null && _isConnected) {
      _subscribeToMotorStatus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluateExternalStates(oldWidget);
      _evaluateManualStartFromCurrent();
    });
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

      if (topic == _motor1StatusTopic) {
        _updateMotor1StateFromExternal(payload);
      } else if (topic == _motor2StatusTopic) {
        _updateMotor2StateFromExternal(payload);
      }
    }
  }

  void _evaluateExternalStates(MotorControllerWidget? oldWidget) {
    if (widget.motor1ExternalStatus != null) {
      _updateMotor1StateFromExternal(widget.motor1ExternalStatus!);
    } else if (widget.motor1TelemetryState != null) {
      _updateMotor1StateFromExternal(widget.motor1TelemetryState!);
    }

    if (widget.motor2ExternalStatus != null) {
      _updateMotor2StateFromExternal(widget.motor2ExternalStatus!);
    } else if (widget.motor2TelemetryState != null) {
      _updateMotor2StateFromExternal(widget.motor2TelemetryState!);
    }
  }

  void _updateMotor1StateFromExternal(String rawPayload) {
    if (!mounted) return;

    final String extStatus =
        (widget.motor1ExternalStatus ?? widget.motor1TelemetryState ?? '')
            .toUpperCase();
    final bool isOffline =
        rawPayload.toUpperCase() == 'OFFLINE' || extStatus == 'OFFLINE';

    if (isOffline) {
      setState(() {
        _motor1On = false;
        _motor1IsManual = false;
        _motor1Status = 'OFFLINE';
      });
      return;
    }

    final bool isOn = _isMotorOnPayload(rawPayload);
    final bool isRecentCmd = _isAppCommandRecent(1);

    if (!isRecentCmd || isOn == _motor1On) {
      setState(() {
        _motor1On = isOn;
        if (!isOn) {
          _motor1IsManual = false;
          _motor1Status = rawPayload.toUpperCase() == 'OFF' ? 'OFF' : rawPayload;
        } else {
          if (!isRecentCmd) {
            _motor1IsManual = false;
          }
          if (!_motor1IsManual || rawPayload.toUpperCase() == 'ON') {
            _motor1Status = rawPayload.toUpperCase() == 'ON' ? 'ON' : rawPayload;
          }
        }
      });
    }
  }

  void _updateMotor2StateFromExternal(String rawPayload) {
    if (!mounted) return;

    final String extStatus =
        (widget.motor2ExternalStatus ?? widget.motor2TelemetryState ?? '')
            .toUpperCase();
    final bool isOffline =
        rawPayload.toUpperCase() == 'OFFLINE' || extStatus == 'OFFLINE';

    if (isOffline) {
      setState(() {
        _motor2On = false;
        _motor2IsManual = false;
        _motor2Status = 'OFFLINE';
      });
      return;
    }

    final bool isOn = _isMotorOnPayload(rawPayload);
    final bool isRecentCmd = _isAppCommandRecent(2);

    if (!isRecentCmd || isOn == _motor2On) {
      setState(() {
        _motor2On = isOn;
        if (!isOn) {
          _motor2IsManual = false;
          _motor2Status = rawPayload.toUpperCase() == 'OFF' ? 'OFF' : rawPayload;
        } else {
          if (!isRecentCmd) {
            _motor2IsManual = false;
          }
          if (!_motor2IsManual || rawPayload.toUpperCase() == 'ON') {
            _motor2Status = rawPayload.toUpperCase() == 'ON' ? 'ON' : rawPayload;
          }
        }
      });
    }
  }

  void _evaluateManualStartFromCurrent() {
    // Only evaluate physical starter box manual start after telemetry state is available and device is online
    if (widget.motor1TelemetryState == null && widget.motor2TelemetryState == null) {
      return;
    }
    if (widget.motor1ExternalStatus == 'OFFLINE' || widget.motor1TelemetryState == 'OFFLINE') {
      return;
    }

    final double maxCurrent = [
      widget.rCurrent,
      widget.yCurrent,
      widget.bCurrent,
    ].reduce((a, b) => a > b ? a : b);

    final bool isCurrentFlowing = maxCurrent >= 0.5;

    if (!mounted) return;

    if (isCurrentFlowing) {
      if (!_motor1On && !_motor2On) {
        // Motor turned ON manually at starter box!
        setState(() {
          _motor1On = true;
          _motor1IsManual = true;
          _motor1Status = 'ON (Manual Start)';
        });
        widget.onLogEvent?.call('Motor 1', 'ON', 'Manual');
      }
    } else {
      if (maxCurrent < 0.2) {
        if (_motor1On && _motor1IsManual) {
          setState(() {
            _motor1On = false;
            _motor1IsManual = false;
            _motor1Status = 'OFF (Manual Stop)';
          });
          widget.onLogEvent?.call('Motor 1', 'OFF', 'Manual');
        }
        if (_motor2On && _motor2IsManual) {
          setState(() {
            _motor2On = false;
            _motor2IsManual = false;
            _motor2Status = 'OFF (Manual Stop)';
          });
          widget.onLogEvent?.call('Motor 2', 'OFF', 'Manual');
        }
      }
    }
  }

  bool _isAppCommandRecent(int motorNum) {
    final DateTime? lastCmd =
        motorNum == 1 ? _lastAppCommandTimeMotor1 : _lastAppCommandTimeMotor2;
    if (lastCmd == null) return false;
    return DateTime.now().difference(lastCmd).inSeconds < 15;
  }

  bool _isMotorOnPayload(String payload) {
    final String cleanPayload = payload.toUpperCase();

    return cleanPayload == 'ON' ||
        cleanPayload == 'RUNNING' ||
        cleanPayload == '1' ||
        cleanPayload == 'TRUE' ||
        cleanPayload == 'START' ||
        cleanPayload == 'STARTING' ||
        cleanPayload == 'PULSING_ON';
  }

  Future<void> _toggleMotor1Toggle() async {
    final bool nextState = !_motor1On;

    if (nextState && !widget.isVoltageValid) {
      _showSnackBar(
        '⚠️ Cannot start Motor 1: Line voltage is out of safe range (150V - 280V required)',
      );
      return;
    }

    _lastAppCommandTimeMotor1 = DateTime.now();

    if (nextState && _motor2On) {
      await _publishMqttMessage(_motor2CommandTopic, 'OFF');
      widget.onLogEvent?.call('Motor 2', 'OFF', 'Interlock');
      if (mounted) {
        setState(() {
          _motor2On = false;
          _motor2IsManual = false;
          _motor2Status = 'OFF (Interlock)';
        });
      }
    }

    final String command = nextState ? 'ON' : 'OFF';

    await _publishMqttMessage(_motor1CommandTopic, command);
    widget.onLogEvent?.call('Motor 1', command, 'Manual');

    if (!mounted) return;

    setState(() {
      _motor1On = nextState;
      _motor1IsManual = false;
      _motor1Status = nextState ? 'ON (Command sent)' : 'OFF (Command sent)';
    });
  }

  Future<void> _toggleMotor2Toggle() async {
    final bool nextState = !_motor2On;

    if (nextState && !widget.isVoltageValid) {
      _showSnackBar(
        '⚠️ Cannot start Motor 2: Line voltage is out of safe range (150V - 280V required)',
      );
      return;
    }

    _lastAppCommandTimeMotor2 = DateTime.now();

    if (nextState && _motor1On) {
      await _publishMqttMessage(_motor1CommandTopic, 'OFF');
      widget.onLogEvent?.call('Motor 1', 'OFF', 'Interlock');
      if (mounted) {
        setState(() {
          _motor1On = false;
          _motor1IsManual = false;
          _motor1Status = 'OFF (Interlock)';
        });
      }
    }

    final String command = nextState ? 'ON' : 'OFF';

    await _publishMqttMessage(_motor2CommandTopic, command);
    widget.onLogEvent?.call('Motor 2', command, 'Manual');

    if (!mounted) return;

    setState(() {
      _motor2On = nextState;
      _motor2IsManual = false;
      _motor2Status = nextState ? 'ON (Command sent)' : 'OFF (Command sent)';
    });
  }

  Future<void> _sendMotor1Pulse(String command) async {
    if (command == 'START' && !widget.isVoltageValid) {
      _showSnackBar(
        'Cannot start Motor 1: Voltage out of valid range (150V - 280V)',
      );
      setState(() => _motor1On = false);
      return;
    }

    _lastAppCommandTimeMotor1 = DateTime.now();

    if (command == 'START' && _motor2On) {
      await _publishMqttMessage(_motor2CommandTopic, 'OFF');
      widget.onLogEvent?.call('Motor 2', 'OFF', 'Interlock');
      if (mounted) {
        setState(() {
          _motor2On = false;
          _motor2IsManual = false;
          _motor2Status = 'OFF (Interlock)';
        });
      }
    }

    final bool isStart = command == 'START';

    setState(() {
      _motor1PulseActive = true;
      _motor1On = isStart;
      _motor1IsManual = false;
      _motor1Status = isStart ? 'ON (Pulse sent)' : 'OFF (Pulse sent)';
    });

    await _publishMqttMessage(_motor1CommandTopic, command);
    widget.onLogEvent?.call('Motor 1', isStart ? 'ON' : 'OFF', 'Manual');

    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _motor1PulseActive = false;
    });
  }

  Future<void> _sendMotor2Pulse(String command) async {
    if (command == 'START' && !widget.isVoltageValid) {
      _showSnackBar(
        'Cannot start Motor 2: Voltage out of valid range (150V - 280V)',
      );
      setState(() => _motor2On = false);
      return;
    }

    _lastAppCommandTimeMotor2 = DateTime.now();

    if (command == 'START' && _motor1On) {
      await _publishMqttMessage(_motor1CommandTopic, 'OFF');
      widget.onLogEvent?.call('Motor 1', 'OFF', 'Interlock');
      if (mounted) {
        setState(() {
          _motor1On = false;
          _motor1IsManual = false;
          _motor1Status = 'OFF (Interlock)';
        });
      }
    }

    final bool isStart = command == 'START';

    setState(() {
      _motor2PulseActive = true;
      _motor2On = isStart;
      _motor2IsManual = false;
      _motor2Status = isStart ? 'ON (Pulse sent)' : 'OFF (Pulse sent)';
    });

    await _publishMqttMessage(_motor2CommandTopic, command);
    widget.onLogEvent?.call('Motor 2', isStart ? 'ON' : 'OFF', 'Manual');

    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _motor2PulseActive = false;
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
    if (!mounted || !context.mounted) return;

    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMotorCard(
          title: 'Motor 1',
          isOn: _motor1On,
          isManual: _motor1IsManual,
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
          isManual: _motor2IsManual,
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
    required bool isManual,
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
          color: isOn
              ? (isManual ? Colors.orange.shade400 : AppColors.primaryLight)
              : Colors.grey.shade300,
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
                      ? (isManual
                          ? Colors.orange.shade100
                          : AppColors.primaryLight.withValues(alpha: 0.25))
                      : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isManual
                      ? Icons.touch_app_rounded
                      : Icons.power_settings_new_rounded,
                  color: isOn
                      ? (isManual
                          ? Colors.orange.shade800
                          : AppColors.primaryDark)
                      : Colors.grey.shade600,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isOn && isManual) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.back_hand_rounded,
                                  size: 12,
                                  color: Colors.orange.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'MANUAL START',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Status: $statusText',
                      style: TextStyle(
                        fontSize: 13,
                        color: isOn
                            ? (isManual
                                ? Colors.orange.shade900
                                : AppColors.primaryDark)
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isOn,
                onChanged: _isConnected ? (_) => onToggle() : null,
                activeColor: isManual ? Colors.orange.shade700 : AppColors.primary,
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
