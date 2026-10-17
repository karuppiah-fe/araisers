import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/core/utils/ui_helpers.dart';
import 'package:arisers/core/widgets/custom_button.dart';
import 'package:arisers/core/widgets/custom_text_field.dart';
import 'package:arisers/features/bluetooth_setup/providers/bluetooth_setup_provider.dart';
import 'package:arisers/features/home/views/home_page.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  final TextEditingController minAmpereController = TextEditingController();
  final TextEditingController maxAmpereController = TextEditingController();
  final TextEditingController minVoltageController = TextEditingController();
  final TextEditingController maxVoltageController = TextEditingController();

  bool hideWifiPassword = true;
  bool autoConnectionStarted = false;
  int selectedPhase = 1;

  @override
  void initState() {
    super.initState();

    final box = Hive.box('sessionBox');
    minAmpereController.text = box.get('minAmp', defaultValue: '0.5').toString();
    maxAmpereController.text = box.get('maxAmp', defaultValue: '20.0').toString();
    minVoltageController.text = box.get('minVolt', defaultValue: '160.0').toString();
    maxVoltageController.text = box.get('maxVolt', defaultValue: '270.0').toString();

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

      if (!mounted) return;

      if (showSuccessMessage) {
        UIHelpers.showSnackBar(
          context,
          message: 'Connected to arisers',
          color: AppColors.success,
        );
      }
    } catch (error) {
      if (!mounted) return;

      if (showErrorMessage) {
        UIHelpers.showSnackBar(
          context,
          message: UIHelpers.cleanError(error),
          color: AppColors.error,
        );
      }
    }
  }

  Future<void> disconnectBluetooth() async {
    FocusScope.of(context).unfocus();

    try {
      await ref.read(bluetoothSetupProvider.notifier).disconnect();

      if (!mounted) return;

      UIHelpers.showSnackBar(
        context,
        message: 'Bluetooth disconnected',
        color: AppColors.warning,
      );
    } catch (error) {
      if (!mounted) return;

      UIHelpers.showSnackBar(
        context,
        message: UIHelpers.cleanError(error),
        color: AppColors.error,
      );
    }
  }

  Future<void> submitConfiguration() async {
    FocusScope.of(context).unfocus();

    final String ssid = ssidController.text.trim();
    final String wifiPassword = wifiPasswordController.text;
    final String deviceName = deviceNameController.text.trim();
    final double? minAmp = double.tryParse(minAmpereController.text.trim());
    final double? maxAmp = double.tryParse(maxAmpereController.text.trim());
    final double? minVolt = double.tryParse(minVoltageController.text.trim());
    final double? maxVolt = double.tryParse(maxVoltageController.text.trim());

    if (ssid.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter Wi-Fi SSID',
        color: AppColors.error,
      );
      return;
    }

    if (wifiPassword.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter Wi-Fi password',
        color: AppColors.error,
      );
      return;
    }

    if (deviceName.isEmpty) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter device name',
        color: AppColors.error,
      );
      return;
    }

    if (minAmp == null || maxAmp == null || minAmp < 0 || maxAmp <= 0 || minAmp >= maxAmp) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter valid Min and Max Ampere values (Min < Max)',
        color: AppColors.error,
      );
      return;
    }

    if (minVolt == null || maxVolt == null || minVolt < 0 || maxVolt <= 0 || minVolt >= maxVolt) {
      UIHelpers.showSnackBar(
        context,
        message: 'Please enter valid Min and Max Voltage values (Min < Max)',
        color: AppColors.error,
      );
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
            minAmp: minAmp,
            maxAmp: maxAmp,
            minVolt: minVolt,
            maxVolt: maxVolt,
          );

      if (!mounted) return;

      final BluetoothSetupState completedState =
          ref.read(bluetoothSetupProvider).asData?.value ??
          const BluetoothSetupState();

      UIHelpers.showSnackBar(
        context,
        message: completedState.connectionMessage,
        color:
            completedState.connectionMessage.toLowerCase().contains('pending')
            ? AppColors.warning
            : AppColors.success,
      );

      wifiPasswordController.clear();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
        (Route<dynamic> route) => false,
      );
    } catch (error) {
      if (!mounted) return;

      UIHelpers.showSnackBar(
        context,
        message: UIHelpers.cleanError(error),
        color: AppColors.error,
      );
    }
  }

  @override
  void dispose() {
    ssidController.dispose();
    wifiPasswordController.dispose();
    deviceNameController.dispose();
    minAmpereController.dispose();
    maxAmpereController.dispose();
    minVoltageController.dispose();
    maxVoltageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final activeLanguage = ref.watch(localeProvider);
    final AsyncValue<BluetoothSetupState> setupAsync = ref.watch(
      bluetoothSetupProvider,
    );
    final BluetoothSetupState setupState =
        setupAsync.asData?.value ?? const BluetoothSetupState();

    final bool isLoading =
        setupAsync.isLoading || setupState.isScanning || setupState.isSending;

    return Scaffold(
      appBar: AppBar(
        title: Text(Words.get('arisers', activeLanguage)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.05,
            vertical: size.height * 0.025,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildBluetoothStatusCard(
                setupState: setupState,
                isLoading: isLoading,
              ),
              SizedBox(height: size.height * 0.025),
              buildWifiSetupCard(
                size: size,
                isLoading: isLoading,
                wifiTitle: Words.get('wifi_setup', activeLanguage),
                ssidHint: Words.get('enter_wifi_ssid', activeLanguage),
                passwordHint: Words.get('enter_wifi_password', activeLanguage),
              ),
              SizedBox(height: size.height * 0.025),
              buildDeviceDetailsCard(
                size: size,
                isLoading: isLoading,
                activeLanguage: activeLanguage,
                deviceNameHint: Words.get('enter_device_name', activeLanguage),
              ),
              SizedBox(height: size.height * 0.025),
              buildLimitsCard(
                size: size,
                isLoading: isLoading,
                activeLanguage: activeLanguage,
              ),
              SizedBox(height: size.height * 0.035),
              CustomButton(
                text: isLoading
                    ? setupState.connectionMessage
                    : Words.get('submit', activeLanguage),
                isLoading: isLoading,
                backgroundColor: AppColors.primary,
                textColor: Colors.white,
                icon: Icons.send_rounded,
                onPressed: submitConfiguration,
              ),
              SizedBox(height: size.height * 0.02),
              Text(
                Words.get('pair_esp32_hint', activeLanguage),
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
          color: isConnected ? AppColors.primaryLight : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                      ? AppColors.primaryLight.withValues(alpha: 0.2)
                      : Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: isConnected ? AppColors.primaryDark : AppColors.error,
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
                          ? 'Arisers Connected'
                          : 'Bluetooth Connection',
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
                            ? AppColors.primaryDark
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
                      foregroundColor: AppColors.error,
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
                    onPressed: isLoading ? null : () => connectBluetooth(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primaryLight,
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
    required Size size,
    required bool isLoading,
    required String wifiTitle,
    required String ssidHint,
    required String passwordHint,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_rounded, color: Colors.white, size: 36),
          const SizedBox(height: 8),
          Text(
            wifiTitle,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: size.height * 0.02),
          CustomTextField(
            controller: ssidController,
            hintText: ssidHint,
            prefixIcon: Icons.wifi_rounded,
            enabled: !isLoading,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          CustomTextField(
            controller: wifiPasswordController,
            hintText: passwordHint,
            prefixIcon: Icons.lock_rounded,
            enabled: !isLoading,
            obscureText: hideWifiPassword,
            textInputAction: TextInputAction.next,
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
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDeviceDetailsCard({
    required Size size,
    required bool isLoading,
    required AppLanguage activeLanguage,
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
          Row(
            children: [
              const Icon(
                Icons.settings_input_component_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                Words.get('device_details', activeLanguage),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: deviceNameController,
            hintText: deviceNameHint,
            prefixIcon: Icons.devices_rounded,
            enabled: !isLoading,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),
          Text(
            Words.get('select_phase_type', activeLanguage),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Container(
            height: 54,
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
                    rightSide: false,
                    enabled: !isLoading,
                  ),
                ),
                Expanded(
                  child: phaseButton(
                    title: '2 Phase',
                    phase: 2,
                    leftSide: false,
                    rightSide: false,
                    enabled: !isLoading,
                  ),
                ),
                Expanded(
                  child: phaseButton(
                    title: '3 Phase',
                    phase: 3,
                    leftSide: false,
                    rightSide: true,
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

  Widget buildLimitsCard({
    required Size size,
    required bool isLoading,
    required AppLanguage activeLanguage,
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
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                Words.get('ampere_voltage_limits', activeLanguage),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: minAmpereController,
                  hintText: Words.get('enter_min_ampere', activeLanguage),
                  prefixIcon: Icons.speed_rounded,
                  enabled: !isLoading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: maxAmpereController,
                  hintText: Words.get('enter_max_ampere', activeLanguage),
                  prefixIcon: Icons.speed_rounded,
                  enabled: !isLoading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: minVoltageController,
                  hintText: Words.get('enter_min_voltage', activeLanguage),
                  prefixIcon: Icons.electric_meter_rounded,
                  enabled: !isLoading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomTextField(
                  controller: maxVoltageController,
                  hintText: Words.get('enter_max_voltage', activeLanguage),
                  prefixIcon: Icons.electric_meter_rounded,
                  enabled: !isLoading,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget phaseButton({
    required String title,
    required int phase,
    required bool leftSide,
    required bool rightSide,
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
        right: rightSide ? const Radius.circular(14) : Radius.zero,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: leftSide ? const Radius.circular(14) : Radius.zero,
            right: rightSide ? const Radius.circular(14) : Radius.zero,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 17,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
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
