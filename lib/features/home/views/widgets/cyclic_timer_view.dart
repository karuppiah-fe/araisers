import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/features/home/providers/cyclic_timer_provider.dart';
import 'package:arisers/features/home/providers/device_online_provider.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';

class CyclicTimerView extends ConsumerWidget {
  const CyclicTimerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cyclicState = ref.watch(cyclicTimerProvider);
    final activeLanguage = ref.watch(localeProvider);
    final isDeviceOnline = ref.watch(deviceOnlineProvider);
    final isRunningOrPaused =
        cyclicState.status == CyclicStatus.running ||
        cyclicState.status == CyclicStatus.paused;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: isRunningOrPaused
                        ? (cyclicState.isRunningPhase
                            ? [AppColors.primary, AppColors.primaryDark]
                            : [Colors.orange.shade700, Colors.orange.shade900])
                        : [Colors.grey.shade800, Colors.black87],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _getStatusTitle(cyclicState, activeLanguage, isDeviceOnline),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatSeconds(cyclicState.remainingSeconds),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isRunningOrPaused)
                      Text(
                        'Cycle ${cyclicState.currentCycle} of ${cyclicState.totalCycles} (${cyclicState.motorName})',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Configurations Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cyclic Configuration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Motor Selector
                    DropdownButtonFormField<String>(
                      value: cyclicState.motorName,
                      decoration: InputDecoration(
                        labelText: Words.get('select_motor', activeLanguage),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Motor 1',
                          child: Text('Motor 1'),
                        ),
                        DropdownMenuItem(
                          value: 'Motor 2',
                          child: Text('Motor 2'),
                        ),
                      ],
                      onChanged: isRunningOrPaused
                          ? null
                          : (val) {
                              if (val != null) {
                                ref
                                    .read(cyclicTimerProvider.notifier)
                                    .updateConfig(motorName: val);
                              }
                            },
                    ),
                    const SizedBox(height: 16),

                    // Run Time (Minutes)
                    _buildNumberSelector(
                      label: Words.get('run_time_min', activeLanguage),
                      value: cyclicState.runMinutes,
                      enabled: !isRunningOrPaused,
                      onChanged: (val) {
                        ref
                            .read(cyclicTimerProvider.notifier)
                            .updateConfig(runMinutes: val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Pause Time (Minutes)
                    _buildNumberSelector(
                      label: Words.get('pause_time_min', activeLanguage),
                      value: cyclicState.pauseMinutes,
                      enabled: !isRunningOrPaused,
                      onChanged: (val) {
                        ref
                            .read(cyclicTimerProvider.notifier)
                            .updateConfig(pauseMinutes: val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Total Cycles
                    _buildNumberSelector(
                      label: Words.get('total_cycles', activeLanguage),
                      value: cyclicState.totalCycles,
                      enabled: !isRunningOrPaused,
                      onChanged: (val) {
                        ref
                            .read(cyclicTimerProvider.notifier)
                            .updateConfig(totalCycles: val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Controls
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: isRunningOrPaused
                          ? AppColors.error
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(
                      isRunningOrPaused ? Icons.stop : Icons.play_arrow,
                    ),
                    label: Text(
                      isRunningOrPaused
                          ? Words.get('stop_cycle', activeLanguage)
                          : Words.get('start_cycle', activeLanguage),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      if (isRunningOrPaused) {
                        ref.read(cyclicTimerProvider.notifier).stopCycle();
                      } else {
                        final isDeviceOnline = ref.read(deviceOnlineProvider);
                        final rVolt = ref.read(rVoltageProvider);
                        final bool isPowerOff = rVolt < 150.0 || !isDeviceOnline;
                        ref.read(cyclicTimerProvider.notifier).startCycle(isPowerCut: isPowerOff);

                        if (isPowerOff) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚡ Device Offline / Power Cut: Cyclic Run Queued! Config sent via MQTT.'),
                              backgroundColor: Colors.amber,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberSelector({
    required String label,
    required int value,
    required bool enabled,
    required Function(int) onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$value',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: enabled ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  String _getStatusTitle(CyclicState state, AppLanguage activeLanguage, bool isDeviceOnline) {
    if (!isDeviceOnline && state.status == CyclicStatus.idle) {
      return '🔴 ESP32 Device Offline';
    }
    switch (state.status) {
      case CyclicStatus.running:
        return state.isRunningPhase
            ? '${Words.get('cycle_running', activeLanguage)} (${state.motorName} ON)'
            : 'Pause Phase (${state.motorName} OFF)';
      case CyclicStatus.paused:
        return state.isPausedByPower
            ? '⚠️ Device Offline / Power Cut (Timer Paused)'
            : Words.get('cycle_paused', activeLanguage);
      case CyclicStatus.completed:
        return Words.get('cycle_completed', activeLanguage);
      case CyclicStatus.idle:
        return 'Ready to Start Cycle';
    }
  }

  String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final minStr = m.toString().padLeft(2, '0');
    final secStr = s.toString().padLeft(2, '0');
    return '$minStr:$secStr';
  }
}
