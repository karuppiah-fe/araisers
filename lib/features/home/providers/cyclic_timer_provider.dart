import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';

enum CyclicStatus { idle, running, paused, completed }

class CyclicState {
  final String motorName; // 'Motor 1' or 'Motor 2'
  final int runMinutes;
  final int pauseMinutes;
  final int totalCycles;
  final int currentCycle;
  final bool isRunningPhase; // true if running phase, false if pause phase
  final int remainingSeconds;
  final CyclicStatus status;

  CyclicState({
    this.motorName = 'Motor 1',
    this.runMinutes = 15,
    this.pauseMinutes = 45,
    this.totalCycles = 5,
    this.currentCycle = 1,
    this.isRunningPhase = true,
    this.remainingSeconds = 0,
    this.status = CyclicStatus.idle,
  });

  CyclicState copyWith({
    String? motorName,
    int? runMinutes,
    int? pauseMinutes,
    int? totalCycles,
    int? currentCycle,
    bool? isRunningPhase,
    int? remainingSeconds,
    CyclicStatus? status,
  }) {
    return CyclicState(
      motorName: motorName ?? this.motorName,
      runMinutes: runMinutes ?? this.runMinutes,
      pauseMinutes: pauseMinutes ?? this.pauseMinutes,
      totalCycles: totalCycles ?? this.totalCycles,
      currentCycle: currentCycle ?? this.currentCycle,
      isRunningPhase: isRunningPhase ?? this.isRunningPhase,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      status: status ?? this.status,
    );
  }
}

class CyclicTimerNotifier extends StateNotifier<CyclicState> {
  Timer? _countdownTimer;
  final Ref _ref;
  Function(String motorName, bool turnOn)? onCommandTrigger;
  Function(String payload)? onMqttSync;

  CyclicTimerNotifier(this._ref) : super(CyclicState());

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void setCommandHandler(Function(String motorName, bool turnOn) handler) {
    onCommandTrigger = handler;
  }

  void setMqttSyncHandler(Function(String payload) handler) {
    onMqttSync = handler;
  }

  void _syncToMqtt() {
    final Map<String, dynamic> payload = {
      'm': state.motorName == 'Motor 1' ? 1 : 2,
      'runM': state.runMinutes,
      'pauseM': state.pauseMinutes,
      'cycles': state.totalCycles,
      'en': state.status == CyclicStatus.running,
    };
    onMqttSync?.call(jsonEncode(payload));
  }

  void updateConfig({
    String? motorName,
    int? runMinutes,
    int? pauseMinutes,
    int? totalCycles,
  }) {
    if (state.status == CyclicStatus.running ||
        state.status == CyclicStatus.paused) {
      return;
    }

    state = state.copyWith(
      motorName: motorName ?? state.motorName,
      runMinutes: runMinutes ?? state.runMinutes,
      pauseMinutes: pauseMinutes ?? state.pauseMinutes,
      totalCycles: totalCycles ?? state.totalCycles,
    );
    _syncToMqtt();
  }

  void startCycle() {
    if (state.runMinutes <= 0 || state.pauseMinutes <= 0) return;

    _countdownTimer?.cancel();

    state = state.copyWith(
      currentCycle: 1,
      isRunningPhase: true,
      remainingSeconds: state.runMinutes * 60,
      status: CyclicStatus.running,
    );

    _syncToMqtt();

    // Turn motor ON
    onCommandTrigger?.call(state.motorName, true);
    _ref.read(dataLogProvider.notifier).addLog(
          motorName: state.motorName,
          action: 'ON',
          trigger: 'Cyclic',
          details: 'Started Cycle 1 of ${state.totalCycles}',
        );

    _runTick();
  }

  void stopCycle() {
    _countdownTimer?.cancel();

    if (state.status == CyclicStatus.running && state.isRunningPhase) {
      // Turn motor OFF
      onCommandTrigger?.call(state.motorName, false);
      _ref.read(dataLogProvider.notifier).addLog(
            motorName: state.motorName,
            action: 'OFF',
            trigger: 'Cyclic',
            details: 'Cycle stopped manually',
          );
    }

    state = state.copyWith(
      status: CyclicStatus.idle,
      remainingSeconds: 0,
    );
    _syncToMqtt();
  }

  void _runTick() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.remainingSeconds > 1) {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      } else {
        _transitionPhase();
      }
    });
  }

  void _transitionPhase() {
    if (state.isRunningPhase) {
      // Motor finished running phase -> Turn OFF, switch to Pause phase
      onCommandTrigger?.call(state.motorName, false);
      _ref.read(dataLogProvider.notifier).addLog(
            motorName: state.motorName,
            action: 'OFF',
            trigger: 'Cyclic',
            details:
                'Completed Run phase for Cycle ${state.currentCycle} of ${state.totalCycles}',
          );

      state = state.copyWith(
        isRunningPhase: false,
        remainingSeconds: state.pauseMinutes * 60,
        status: CyclicStatus.paused,
      );
    } else {
      // Pause phase finished -> Check if cycles remaining
      if (state.currentCycle < state.totalCycles) {
        final nextCycle = state.currentCycle + 1;
        state = state.copyWith(
          currentCycle: nextCycle,
          isRunningPhase: true,
          remainingSeconds: state.runMinutes * 60,
          status: CyclicStatus.running,
        );

        // Turn motor ON for next cycle
        onCommandTrigger?.call(state.motorName, true);
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: state.motorName,
              action: 'ON',
              trigger: 'Cyclic',
              details: 'Started Cycle $nextCycle of ${state.totalCycles}',
            );
      } else {
        // All cycles finished
        _countdownTimer?.cancel();
        state = state.copyWith(
          status: CyclicStatus.completed,
          remainingSeconds: 0,
        );
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: state.motorName,
              action: 'OFF',
              trigger: 'Cyclic',
              details: 'All ${state.totalCycles} cycles completed',
            );
      }
    }
  }
}

final cyclicTimerProvider =
    StateNotifierProvider<CyclicTimerNotifier, CyclicState>((ref) {
  return CyclicTimerNotifier(ref);
});
