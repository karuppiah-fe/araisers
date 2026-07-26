import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arisers/riverpod/session_provider.dart';
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
    final PermissionStatus permissionStatus = await Permission.bluetoothConnect
        .request();

    if (permissionStatus.isPermanentlyDenied) {
      throw Exception(
        'Bluetooth permission is permanently denied. '
        'Open app settings and enable Nearby devices.',
      );
    }

    if (permissionStatus.isDenied) {
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

  Future<BluetoothDevice> findPairedArisersDevice() async {
    final List<BluetoothDevice> bondedDevices = await _bluetooth
        .getBondedDevices();

    if (bondedDevices.isEmpty) {
      throw Exception(
        'No paired Bluetooth device found. '
        'Pair with "arisers" in phone Bluetooth settings first.',
      );
    }

    for (final BluetoothDevice device in bondedDevices) {
      final String deviceName = device.name?.trim().toLowerCase() ?? '';

      if (deviceName == arisersBluetoothName.toLowerCase()) {
        return device;
      }
    }

    final String bondedDeviceNames = bondedDevices
        .map((BluetoothDevice device) => device.name ?? 'Unknown device')
        .join(', ');

    throw Exception(
      'Paired device "$arisersBluetoothName" was not found. '
      'Available paired devices: $bondedDeviceNames',
    );
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
        connectionMessage: 'Connecting to arisers...',
      ),
    );

    try {
      await requestBluetoothPermission();
      await ensureBluetoothEnabled();

      final BluetoothDevice device = await findPairedArisersDevice();

      await closeCurrentConnection();

      updateState(
        currentState.copyWith(
          isScanning: true,
          isConnected: false,
          connectedDeviceName: device.name ?? arisersBluetoothName,
          connectedDeviceAddress: device.address,
          connectionMessage: 'Opening Bluetooth connection...',
        ),
      );

      final BluetoothConnection connection =
          await BluetoothConnection.toAddress(device.address).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Bluetooth connection timed out.');
            },
          );

      if (!connection.isConnected) {
        throw Exception('Could not connect to arisers.');
      }

      _connection = connection;
      _receiveBuffer = '';

      listenForIncomingData(connection);

      await saveBluetoothDevice(
        deviceName: device.name ?? arisersBluetoothName,
        deviceAddress: device.address,
      );

      updateState(
        currentState.copyWith(
          isScanning: false,
          isConnected: true,
          isSending: false,
          connectedDeviceName: device.name ?? arisersBluetoothName,
          connectedDeviceAddress: device.address,
          connectionMessage: 'Bluetooth connected',
        ),
      );
    } catch (error) {
      await closeCurrentConnection();

      updateState(
        currentState.copyWith(
          isScanning: false,
          isConnected: false,
          isSending: false,
          connectionMessage: 'Bluetooth connection failed',
          clearDeviceName: true,
          clearDeviceAddress: true,
        ),
      );

      rethrow;
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

    // Backward compatibility for simple text messages.
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

    // Current ESP32 firmware sends one JSON object per line.
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

      // Complete configuration on the immediate ACK or final result.
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

  Future<void> sendConfiguration({
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
    required int phase,
  }) async {
    final String cleanSsid = wifiSsid.trim();
    final String cleanDeviceName = deviceName.trim();

    if (cleanSsid.isEmpty) {
      throw Exception('Please enter Wi-Fi SSID.');
    }

    if (wifiPassword.isEmpty) {
      throw Exception('Please enter Wi-Fi password.');
    }

    if (cleanDeviceName.isEmpty) {
      throw Exception('Please enter device name.');
    }

    if (phase != 1 && phase != 3) {
      throw Exception('Please select 1 Phase or 3 Phase.');
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

      // Always save locally first. Firebase failure must not erase a
      // successful ESP32 configuration.
      await saveConfigurationLocally(
        wifiSsid: cleanSsid,
        deviceName: cleanDeviceName,
        phase: phase,
      );

      String completionMessage = 'Configured and saved locally';

      try {
        await saveConfigurationToFirebase(
          wifiSsid: cleanSsid,
          deviceName: cleanDeviceName,
          phase: phase,
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
          connectionMessage: 'Configuration failed',
        ),
      );

      rethrow;
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
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    await sessionBox.put('deviceName', deviceName);

    await sessionBox.put('wifiSsid', wifiSsid);

    await sessionBox.put('phase', phase);

    await sessionBox.put('deviceConfigured', true);

    await sessionBox.put('configuredAt', DateTime.now().toIso8601String());
  }

  Future<void> savePendingFirebaseSync({
    required String wifiSsid,
    required String deviceName,
    required int phase,
    required String errorMessage,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    await sessionBox.put('firebaseSyncPending', true);
    await sessionBox.put('pendingDeviceConfiguration', <String, dynamic>{
      'deviceName': deviceName,
      'wifiSsid': wifiSsid,
      'phase': phase,
      'configuredAt': DateTime.now().toIso8601String(),
      'lastSyncError': errorMessage,
    });
  }

  Future<void> saveConfigurationToFirebase({
    required String wifiSsid,
    required String deviceName,
    required int phase,
  }) async {
    final Box<dynamic> sessionBox = Hive.box(SessionNotifier.boxName);

    final String? userKey = sessionBox.get('userKey')?.toString();

    if (userKey == null || userKey.trim().isEmpty) {
      throw Exception('User session was not found. Please log in again.');
    }

    final DatabaseReference reference = FirebaseDatabase.instance.ref(
      'arisers/$userKey/deviceInfo',
    );

    await reference.update({
      'deviceName': deviceName,
      'wifiSsid': wifiSsid,
      'phase': phase,
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
      await _connection?.cancel();
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
      await _connection?.cancel();
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
