import 'package:arisers/riverpod/bluetooth_setup_provider.dart';
import 'package:arisers/riverpod/words.dart';
import 'package:arisers/ui/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BluetoothPage extends ConsumerStatefulWidget {
  const BluetoothPage({super.key});

  @override
  ConsumerState<BluetoothPage> createState() {
    return _BluetoothPageState();
  }
}

class _BluetoothPageState extends ConsumerState<BluetoothPage> {
  final TextEditingController ssidController = TextEditingController();

  final TextEditingController wifiPasswordController = TextEditingController();

  final TextEditingController deviceNameController = TextEditingController();

  bool hideWifiPassword = true;
  bool autoConnectionStarted = false;

  int selectedPhase = 1;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || autoConnectionStarted) {
        return;
      }

      autoConnectionStarted = true;

      connectBluetooth(showSuccessMessage: false, showErrorMessage: false);
    });
  }

  Future<void> connectBluetooth({
    bool showSuccessMessage = true,
    bool showErrorMessage = true,
  }) async {
    FocusScope.of(context).unfocus();

    try {
      await ref.read(bluetoothSetupProvider.notifier).connectToArisers();

      if (!mounted) {
        return;
      }

      if (showSuccessMessage) {
        showMessage(message: 'Connected to arisers', color: Colors.green);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (showErrorMessage) {
        showMessage(message: cleanError(error), color: Colors.red);
      }
    }
  }

  Future<void> disconnectBluetooth() async {
    FocusScope.of(context).unfocus();

    try {
      await ref.read(bluetoothSetupProvider.notifier).disconnect();

      if (!mounted) {
        return;
      }

      showMessage(message: 'Bluetooth disconnected', color: Colors.orange);
    } catch (error) {
      if (!mounted) {
        return;
      }

      showMessage(message: cleanError(error), color: Colors.red);
    }
  }

  Future<void> submitConfiguration() async {
    FocusScope.of(context).unfocus();

    final String ssid = ssidController.text.trim();

    final String wifiPassword = wifiPasswordController.text;

    final String deviceName = deviceNameController.text.trim();

    if (ssid.isEmpty) {
      showMessage(message: 'Please enter Wi-Fi SSID', color: Colors.red);
      return;
    }

    if (wifiPassword.isEmpty) {
      showMessage(message: 'Please enter Wi-Fi password', color: Colors.red);
      return;
    }

    if (deviceName.isEmpty) {
      showMessage(message: 'Please enter device name', color: Colors.red);
      return;
    }

    try {
      await ref
          .read(bluetoothSetupProvider.notifier)
          .sendConfiguration(
            wifiSsid: ssid,
            wifiPassword: wifiPassword,
            deviceName: deviceName,
            phase: selectedPhase,
          );

      if (!mounted) {
        return;
      }

      final BluetoothSetupState completedState =
          ref.read(bluetoothSetupProvider).asData?.value ??
          const BluetoothSetupState();

      showMessage(
        message: completedState.connectionMessage,
        color:
            completedState.connectionMessage.toLowerCase().contains('pending')
            ? Colors.orange
            : Colors.green,
      );

      wifiPasswordController.clear();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const Home()),
        (Route<dynamic> route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      showMessage(message: cleanError(error), color: Colors.red);
    }
  }

  String cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('TimeoutException: ', '');
  }

  void showMessage({required String message, required Color color}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    ssidController.dispose();
    wifiPasswordController.dispose();
    deviceNameController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.sizeOf(context);

    final double width = screenSize.width;
    final double height = screenSize.height;

    final words = ref.watch(wordsProvider);

    final AsyncValue<BluetoothSetupState> setupAsync = ref.watch(
      bluetoothSetupProvider,
    );

    final BluetoothSetupState setupState =
        setupAsync.asData?.value ?? const BluetoothSetupState();

    final bool isLoading =
        setupAsync.isLoading || setupState.isScanning || setupState.isSending;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.lightGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        title: Text(
          words.english['arisers'] ?? 'ARISERS',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(
            horizontal: width * 0.05,
            vertical: height * 0.025,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildBluetoothStatusCard(
                setupState: setupState,
                isLoading: isLoading,
              ),

              SizedBox(height: height * 0.025),

              buildWifiSetupCard(
                width: width,
                height: height,
                isLoading: isLoading,
                wifiTitle: words.english['wifi setup'] ?? 'Wi-Fi Setup',
                ssidHint:
                    words.english['enter the wifi ssid'] ??
                    'Enter the Wi-Fi SSID',
                passwordHint:
                    words.english['enter the wifi password'] ??
                    'Enter the Wi-Fi Password',
              ),

              SizedBox(height: height * 0.025),

              buildDeviceDetailsCard(
                height: height,
                isLoading: isLoading,
                deviceNameHint:
                    words.english['enter the device name'] ??
                    'Enter the device name',
              ),

              SizedBox(height: height * 0.035),

              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : submitConfiguration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.lightGreen.shade200,
                    disabledForegroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    isLoading
                        ? setupState.connectionMessage
                        : words.english['submit'] ?? 'Submit',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              SizedBox(height: height * 0.02),

              Text(
                'Pair the ESP32 as "arisers" in your phone Bluetooth settings before connecting.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBluetoothStatusCard({
    required BluetoothSetupState setupState,
    required bool isLoading,
  }) {
    final bool isConnected = setupState.isConnected;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected ? Colors.green.shade200 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 28,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? 'Arisers connected'
                          : 'Bluetooth connection',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      setupState.connectionMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: isConnected
                            ? Colors.green.shade700
                            : Colors.grey.shade700,
                      ),
                    ),

                    if (setupState.connectedDeviceName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        setupState.connectedDeviceName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],

                    if (setupState.connectedDeviceAddress != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        setupState.connectedDeviceAddress!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: isConnected
                ? OutlinedButton.icon(
                    onPressed: isLoading ? null : disconnectBluetooth,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text(
                      'Disconnect Bluetooth',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () {
                            connectBluetooth();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.lightGreen.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: isLoading
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bluetooth_rounded),
                    label: Text(
                      isLoading ? 'Connecting...' : 'Connect to arisers',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildWifiSetupCard({
    required double width,
    required double height,
    required bool isLoading,
    required String wifiTitle,
    required String ssidHint,
    required String passwordHint,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: width * 0.05,
        vertical: height * 0.03,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.lightGreen, Color(0xFF7CB342)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.lightGreen.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_rounded, color: Colors.white, size: 38),

          const SizedBox(height: 8),

          Text(
            wifiTitle,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          SizedBox(height: height * 0.028),

          TextField(
            controller: ssidController,
            enabled: !isLoading,
            textInputAction: TextInputAction.next,
            decoration: inputDecoration(
              hintText: ssidHint,
              icon: Icons.wifi_rounded,
            ),
          ),

          SizedBox(height: height * 0.02),

          TextField(
            controller: wifiPasswordController,
            enabled: !isLoading,
            obscureText: hideWifiPassword,
            textInputAction: TextInputAction.next,
            decoration: inputDecoration(
              hintText: passwordHint,
              icon: Icons.lock_rounded,
              suffixIcon: IconButton(
                onPressed: isLoading
                    ? null
                    : () {
                        setState(() {
                          hideWifiPassword = !hideWifiPassword;
                        });
                      },
                icon: Icon(
                  hideWifiPassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDeviceDetailsCard({
    required double height,
    required bool isLoading,
    required String deviceNameHint,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.settings_input_component_rounded,
                color: Colors.lightGreen,
              ),
              SizedBox(width: 8),
              Text(
                'Device details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          SizedBox(height: height * 0.02),

          TextField(
            controller: deviceNameController,
            enabled: !isLoading,
            textInputAction: TextInputAction.done,
            decoration: inputDecoration(
              hintText: deviceNameHint,
              icon: Icons.devices_rounded,
            ),
          ),

          SizedBox(height: height * 0.025),

          Text(
            'Select phase type',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),

          SizedBox(height: height * 0.012),

          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: phaseButton(
                    title: '1 Phase',
                    phase: 1,
                    leftSide: true,
                    enabled: !isLoading,
                  ),
                ),
                Expanded(
                  child: phaseButton(
                    title: '3 Phase',
                    phase: 3,
                    leftSide: false,
                    enabled: !isLoading,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.lightGreen.shade700),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.green.shade300, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.green, width: 2.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget phaseButton({
    required String title,
    required int phase,
    required bool leftSide,
    required bool enabled,
  }) {
    final bool selected = selectedPhase == phase;

    return InkWell(
      onTap: enabled
          ? () {
              setState(() {
                selectedPhase = phase;
              });
            }
          : null,
      borderRadius: BorderRadius.horizontal(
        left: leftSide ? const Radius.circular(14) : Radius.zero,
        right: !leftSide ? const Radius.circular(14) : Radius.zero,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.lightGreen : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: leftSide ? const Radius.circular(14) : Radius.zero,
            right: !leftSide ? const Radius.circular(14) : Radius.zero,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 19,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
