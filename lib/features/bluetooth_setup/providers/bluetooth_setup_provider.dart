import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

const String arisersBluetoothName = 'arisers';

final bluetoothSetupProvider =
    AsyncNotifierProvider<BluetoothSetupNotifier, BluetoothSetupState>(
      BluetoothSetupNotifier.new,
    );

class BluetoothSetupState {
  final bool isScanning;
  final bool isConnected;
  final bool isSending;
  final String connectionMessage;
  final String? connectedDeviceName;
  final String? connectedDeviceAddress;

  const BluetoothSetupState({
    this.isScanning = false,
    this.isConnected = false,
    this.isSending = false,
    this.connectionMessage = 'Bluetooth not connected',
    this.connectedDeviceName,
    this.connectedDeviceAddress,
  });

  BluetoothSetupState copyWith({
    bool? isScanning,
    bool? isConnected,
    bool? isSending,
    String? connectionMessage,
    String? connectedDeviceName,
    String? connectedDeviceAddress,
    bool clearDeviceName = false,
    bool clearDeviceAddress = false,
  }) {
    return BluetoothSetupState(
      isScanning: isScanning ?? this.isScanning,
      isConnected: isConnected ?? this.isConnected,
      isSending: isSending ?? this.isSending,
      connectionMessage: connectionMessage ?? this.connectionMessage,
      connectedDeviceName: clearDeviceName
          ? null
          : connectedDeviceName ?? this.connectedDeviceName,
      connectedDeviceAddress: clearDeviceAddress
          ? null
          : connectedDeviceAddress ?? this.connectedDeviceAddress,
    );
  }
}

class BluetoothSetupNotifier extends AsyncNotifier<BluetoothSetupState> {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;
  Completer<String>? _responseCompleter;

  String _receiveBuffer = '';
  bool _manualDisconnect = false;

  @override
  Future<BluetoothSetupState> build() async {
    ref.onDispose(() {
      _disposeBluetooth();
    });

    return const BluetoothSetupState();
  }

  BluetoothSetupState get currentState {
    return state.asData?.value ?? const BluetoothSetupState();
  }

  bool get isConnectionActive {
    return _connection != null && (_connection?.isConnected ?? false);
  }

  void updateState(BluetoothSetupState newState) {
    state = AsyncData(newState);
  }

  Future<void> requestBluetoothPermission() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    final bool connectDenied =
        statuses[Permission.bluetoothConnect]?.isDenied == true ||
        statuses[Permission.bluetoothConnect]?.isPermanentlyDenied == true;

    final bool scanDenied =
        statuses[Permission.bluetoothScan]?.isDenied == true ||
        statuses[Permission.bluetoothScan]?.isPermanentlyDenied == true;

    if (statuses[Permission.bluetoothConnect]?.isPermanentlyDenied == true ||
        statuses[Permission.bluetoothScan]?.isPermanentlyDenied == true) {
      throw Exception(
        'Bluetooth permissions are permanently denied. '
        'Please open app settings and enable Nearby devices.',
      );
    }

    if (connectDenied && scanDenied) {
      throw Exception('Bluetooth permission was denied.');
    }
  }

  Future<void> ensureBluetoothEnabled() async {
    final bool? available = await _bluetooth.isAvailable;

    if (available != true) {
      throw Exception('Bluetooth is not available on this phone.');
    }

    final bool? enabled = await _bluetooth.isEnabled;

    if (enabled == true) {
      return;
    }

    updateState(
      currentState.copyWith(
        isScanning: true,
        connectionMessage: 'Turning on Bluetooth...',
      ),
    );

    final bool? enableResult = await _bluetooth.requestEnable();

    if (enableResult != true) {
      throw Exception('Please turn on Bluetooth to continue.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 800));

    final bool? enabledAfterRequest = await _bluetooth.isEnabled;

    if (enabledAfterRequest != true) {
      throw Exception('Bluetooth is still turned off.');
    }
  }

  Future<List<BluetoothDevice>> getPairedArisersDevices() async {
    final List<BluetoothDevice> bondedDevices = await _bluetooth.getBondedDevices();
    final List<BluetoothDevice> matching = [];

    for (final BluetoothDevice device in bondedDevices) {
      final String deviceName = device.name?.trim().toLowerCase() ?? '';
      if (deviceName.contains('arisers') || deviceName.contains('esp32')) {
        matching.add(device);
      }
    }
    return matching;
  }

  Future<void> connectToArisers() async {
    if (isConnectionActive && currentState.isConnected) {
      return;
    }

    _manualDisconnect = false;

    updateState(
      currentState.copyWith(
        isScanning: true,
        isConnected: false,
        isSending: false,
        connectionMessage: 'Scanning paired Bluetooth devices...',
      ),
    );

    try {
      await requestBluetoothPermission();
      await ensureBluetoothEnabled();

      final List<BluetoothDevice> matchingDevices = await getPairedArisersDevices();

      if (matchingDevices.isEmpty) {
        final List<BluetoothDevice> allBonded = await _bluetooth.getBondedDevices();
        final String bondedNames = allBonded.isEmpty
            ? 'None'
            : allBonded.map((d) => d.name ?? 'Unknown').join(', ');
        throw Exception(
          'No paired "arisers" or "ESP32" device found. '
          'Pair with your ESP32 in phone Bluetooth settings first. (Paired on phone: $bondedNames)',
        );
      }

      await closeCurrentConnection();

      BluetoothConnection? activeConnection;
      BluetoothDevice? connectedDevice;

      for (final device in matchingDevices) {
        updateState(
          currentState.copyWith(
            connectionMessage: 'Connecting to ${device.name ?? "ESP32"}...',
            connectedDeviceName: device.name ?? arisersBluetoothName,
            connectedDeviceAddress: device.address,
          ),
        );

        try {
          final connection = await BluetoothConnection.toAddress(device.address).timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              throw TimeoutException('Connection to ${device.name} timed out.');
            },
          );

          if (connection.isConnected) {
            activeConnection = connection;
            connectedDevice = device;
            break;
          }
        } catch (e) {
          debugPrint('Could not connect to ${device.name} (${device.address}): $e');
        }
      }

      if (activeConnection == null || connectedDevice == null) {
        throw Exception('Could not connect to any paired ESP32 device. Ensure your ESP32 is powered ON and nearby.');
      }

      _connection = activeConnection;
      _receiveBuffer = '';

      listenForIncomingData(activeConnection);

      await saveBluetoothDevice(
        deviceName: connectedDevice.name ?? arisersBluetoothName,
        deviceAddress: connectedDevice.address,
      );

      updateState(
        currentState.copyWith(
          isScanning: false,
          isConnected: true,
          isSending: false,
          connectedDeviceName: connectedDevice.name ?? arisersBluetoothName,
          connectedDeviceAddress: connectedDevice.address,
          connectionMessage: 'Bluetooth connected to ${connectedDevice.name}',
        ),
      );
    } catch (error) {
      await closeCurrentConnection();

      final String cleanErrMsg = error.toString().contains('read failed') || error.toString().contains('socket')
          ? 'ESP32 Bluetooth device is powered OFF or unreachable'
          : error.toString().replaceFirst('Exception: ', '');

      updateState(
        currentState.copyWith(
          isScanning: false,
          isConnected: false,
          isSending: false,
          connectionMessage: cleanErrMsg,
          clearDeviceName: true,
          clearDeviceAddress: true,
        ),
      );
    }
  }

  void listenForIncomingData(BluetoothConnection connection) {
    _inputSubscription?.cancel();

    final Stream<Uint8List>? inputStream = connection.input;

    if (inputStream == null) {
      throw Exception('Bluetooth input stream is unavailable.');
    }

    _inputSubscription = inputStream.listen(
      (Uint8List data) {
        final String receivedText = utf8.decode(data, allowMalformed: true);

        _receiveBuffer += receivedText;

        while (_receiveBuffer.contains('\n')) {
          final int newlineIndex = _receiveBuffer.indexOf('\n');

          final String message = _receiveBuffer
              .substring(0, newlineIndex)
              .replaceAll('\r', '')
              .trim();

          _receiveBuffer = _receiveBuffer.substring(newlineIndex + 1);

          if (message.isNotEmpty) {
            handleBluetoothMessage(message);
          }
        }
      },
      onError: (Object error) {
        handleBluetoothDisconnected('Bluetooth communication error');
      },
      onDone: () {
        handleBluetoothDisconnected('Bluetooth disconnected');
      },
      cancelOnError: false,
    );
  }

  void handleBluetoothMessage(String message) {
    debugPrint('ESP32 response: $message');

    final Completer<String>? completer = _responseCompleter;

    if (message.startsWith('STATUS:')) {
      final String statusMessage = message
          .replaceFirst('STATUS:', '')
          .replaceAll('_', ' ')
          .trim();

      updateState(currentState.copyWith(connectionMessage: statusMessage));
      return;
    }

    if (message.startsWith('SUCCESS') || message.startsWith('ERROR')) {
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
      return;
    }

    try {
      final dynamic decoded = jsonDecode(message);

      if (decoded is! Map<String, dynamic>) {
        debugPrint('Ignored non-object Bluetooth JSON: $decoded');
        return;
      }

      final String type = decoded['type']?.toString() ?? 'result';
      final bool success = decoded['success'] == true;
      final String responseMessage =
          decoded['message']?.toString() ?? 'UNKNOWN_RESPONSE';
      final bool wifiConnected = decoded['wifiConnected'] == true;
      final bool mqttConnected = decoded['mqttConnected'] == true;

      updateState(
        currentState.copyWith(
          connectionMessage: responseMessage.replaceAll('_', ' '),
        ),
      );

      if ((type == 'ack' || type == 'result') &&
          completer != null &&
          !completer.isCompleted) {
        if (success) {
          completer.complete(
            'SUCCESS:$responseMessage'
            '|wifi=$wifiConnected'
            '|mqtt=$mqttConnected',
          );
        } else {
          completer.complete('ERROR:$responseMessage');
        }
      }
    } on FormatException {
      debugPrint('Unknown ESP32 Bluetooth message: $message');
    } catch (error, stackTrace) {
      debugPrint('Bluetooth response parsing failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void handleBluetoothDisconnected(String message) {
    _connection = null;
    _inputSubscription = null;

    if (_manualDisconnect) {
      return;
    }

    final Completer<String>? completer = _responseCompleter;

    if (completer != null && !completer.isCompleted) {
      completer.completeError(Exception(message));
    }

    updateState(
      currentState.copyWith(
        isScanning: false,
        isConnected: false,
        isSending: false,
        connectionMessage: message,
        clearDeviceName: true,
        clearDeviceAddress: true,
      ),
    );
  }

  String _sanitizeDeviceName(String value) {
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

  Future<void> sendConfiguration({
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
    required int phase,
    required double minAmp,
    required double maxAmp,
    required double minVolt,
    required double maxVolt,
  }) async {
    final String cleanSsid = wifiSsid.trim();
    final String cleanDeviceName = _sanitizeDeviceName(deviceName);

    if (cleanSsid.isEmpty) {
      throw Exception('Please enter Wi-Fi SSID.');
    }

    if (wifiPassword.isEmpty) {
      throw Exception('Please enter Wi-Fi password.');
    }

    if (cleanDeviceName.isEmpty) {
      throw Exception('Please enter device name.');
    }

    if (phase < 1 || phase > 3) {
      throw Exception('Please select Phase Type (1, 2, or 3 Phase).');
    }

    if (minAmp < 0 || maxAmp <= 0 || minAmp >= maxAmp) {
      throw Exception('Please enter valid Min and Max Ampere values.');
    }

    if (minVolt < 0 || maxVolt <= 0 || minVolt >= maxVolt) {
      throw Exception('Please enter valid Min and Max Voltage values.');
    }

    if (!isConnectionActive || !currentState.isConnected) {
      await connectToArisers();
    }

    final BluetoothConnection? connection = _connection;

    if (connection == null || !connection.isConnected) {
      throw Exception('Bluetooth is not connected.');
    }

    final Map<String, dynamic> configuration = {
      'ssid': cleanSsid,
      'pass': wifiPassword,
      'device': cleanDeviceName,
      'phase': phase,
      'minAmp': minAmp,
      'maxAmp': maxAmp,
      'minVolt': minVolt,
      'maxVolt': maxVolt,
    };

    final String jsonData = '${jsonEncode(configuration)}\n';

    _responseCompleter = Completer<String>();

    updateState(
      currentState.copyWith(
        isSending: true,
        isConnected: true,
        connectionMessage: 'Sending configuration...',
      ),
    );

    try {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonData));

      connection.output.add(bytes);

      await connection.output.allSent.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Sending Bluetooth data timed out.');
        },
      );

      final String response = await _responseCompleter!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException(
            'ESP32 configuration response timed out. Check the ESP32 serial monitor.',
          );
        },
      );

      if (response.startsWith('ERROR')) {
        final String errorMessage = response
            .replaceFirst('ERROR:', '')
            .replaceAll('_', ' ')
            .trim();

        throw Exception(
          errorMessage.isEmpty ? 'ESP32 configuration failed.' : errorMessage,
        );
      }

      if (!response.startsWith('SUCCESS')) {
        throw Exception('Unexpected ESP32 response: $response');
      }

      await saveConfigurationLocally(
        wifiSsid: cleanSsid,
        deviceName: cleanDeviceName,
        phase: phase,
        minAmp: minAmp,
        maxAmp: maxAmp,
        minVolt: minVolt,
        maxVolt: maxVolt,
      );

      String completionMessage = 'Configured and saved locally';

      try {
        await saveConfigurationToFirebase(
          wifiSsid: cleanSsid,
          deviceName: cleanDeviceName,
          phase: phase,
          minAmp: minAmp,
          maxAmp: maxAmp,
          minVolt: minVolt,
          maxVolt: maxVolt,
        );

        final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);
        await sessionBox.put('firebaseSyncPending', false);
        await sessionBox.delete('pendingDeviceConfiguration');

        completionMessage = 'Setup completed and synced to Firebase';
      } catch (firebaseError, stackTrace) {
        debugPrint('Firebase configuration save failed: $firebaseError');
        debugPrintStack(stackTrace: stackTrace);

        await savePendingFirebaseSync(
          wifiSsid: cleanSsid,
          deviceName: cleanDeviceName,
          phase: phase,
          minAmp: minAmp,
          maxAmp: maxAmp,
          minVolt: minVolt,
          maxVolt: maxVolt,
          errorMessage: firebaseError.toString(),
        );

        completionMessage = 'Configured locally. Firebase sync is pending.';
      }

      updateState(
        currentState.copyWith(
          isSending: false,
          isConnected: true,
          connectionMessage: completionMessage,
        ),
      );
    } catch (error) {
      updateState(
        currentState.copyWith(
          isSending: false,
          isConnected: isConnectionActive,
          connectionMessage: 'Configuration failed: Device unreachable',
        ),
      );
    } finally {
      _responseCompleter = null;
    }
  }

  Future<void> saveBluetoothDevice({
    required String deviceName,
    required String deviceAddress,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    await sessionBox.put('bluetoothDeviceName', deviceName);
    await sessionBox.put('bluetoothDeviceAddress', deviceAddress);
  }

  Future<void> saveConfigurationLocally({
    required String wifiSsid,
    required String deviceName,
    required int phase,
    required double minAmp,
    required double maxAmp,
    required double minVolt,
    required double maxVolt,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    await sessionBox.put('deviceName', deviceName);
    await sessionBox.put('wifiSsid', wifiSsid);
    await sessionBox.put('phase', phase);
    await sessionBox.put('minAmp', minAmp);
    await sessionBox.put('maxAmp', maxAmp);
    await sessionBox.put('minVolt', minVolt);
    await sessionBox.put('maxVolt', maxVolt);
    await sessionBox.put('deviceConfigured', true);
    await sessionBox.put('configuredAt', DateTime.now().toIso8601String());
  }

  Future<void> savePendingFirebaseSync({
    required String wifiSsid,
    required String deviceName,
    required int phase,
    required double minAmp,
    required double maxAmp,
    required double minVolt,
    required double maxVolt,
    required String errorMessage,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    await sessionBox.put('firebaseSyncPending', true);
    await sessionBox.put('pendingDeviceConfiguration', <String, dynamic>{
      'deviceName': deviceName,
      'wifiSsid': wifiSsid,
      'phase': phase,
      'minAmp': minAmp,
      'maxAmp': maxAmp,
      'minVolt': minVolt,
      'maxVolt': maxVolt,
      'configuredAt': DateTime.now().toIso8601String(),
      'lastSyncError': errorMessage,
    });
  }

  Future<void> saveConfigurationToFirebase({
    required String wifiSsid,
    required String deviceName,
    required int phase,
    required double minAmp,
    required double maxAmp,
    required double minVolt,
    required double maxVolt,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    final String? userKey = sessionBox.get('userKey')?.toString();

    if (userKey == null || userKey.trim().isEmpty) {
      throw Exception('User session was not found. Please log in again.');
    }

    final String cleanKey = userKey.trim().replaceAll(RegExp(r'[.#$\[\]/]'), '_');

    final DatabaseReference reference = FirebaseDatabase.instance.ref(
      'arisers/$cleanKey/deviceInfo',
    );

    await reference.update({
      'deviceName': deviceName,
      'wifiSsid': wifiSsid,
      'phase': phase,
      'minAmp': minAmp,
      'maxAmp': maxAmp,
      'minVolt': minVolt,
      'maxVolt': maxVolt,
      'bluetoothName': arisersBluetoothName,
      'bluetoothType': 'classic',
      'configured': true,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;

    final Completer<String>? completer = _responseCompleter;

    if (completer != null && !completer.isCompleted) {
      completer.completeError(Exception('Bluetooth disconnected.'));
    }

    _responseCompleter = null;

    await closeCurrentConnection();

    _receiveBuffer = '';

    updateState(
      const BluetoothSetupState(connectionMessage: 'Bluetooth disconnected'),
    );
  }

  Future<void> closeCurrentConnection() async {
    try {
      await _inputSubscription?.cancel();
    } catch (_) {}

    _inputSubscription = null;

    try {
      await _connection?.close();
    } catch (_) {
      try {
        _connection?.dispose();
      } catch (_) {}
    }

    _connection = null;
  }

  Future<void> _disposeBluetooth() async {
    _manualDisconnect = true;

    try {
      await _inputSubscription?.cancel();
    } catch (_) {}

    try {
      await _connection?.close();
    } catch (_) {
      try {
        _connection?.dispose();
      } catch (_) {}
    }

    _inputSubscription = null;
    _connection = null;
    _responseCompleter = null;
    _receiveBuffer = '';
  }
}
