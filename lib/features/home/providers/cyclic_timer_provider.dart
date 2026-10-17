import 'package:arisers/features/auth/providers/session_provider.dart';
import 'package:arisers/features/home/providers/device_online_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  final bool isPausedByPower; // True if paused due to power cut outage

  CyclicState({
    this.motorName = 'Motor 1',
    this.runMinutes = 15,
    this.pauseMinutes = 45,
    this.totalCycles = 5,
    this.currentCycle = 1,
    this.isRunningPhase = true,
    this.remainingSeconds = 0,
    this.status = CyclicStatus.idle,
    this.isPausedByPower = false,
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
    bool? isPausedByPower,
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
      isPausedByPower: isPausedByPower ?? this.isPausedByPower,
    );
  }
}

class CyclicTimerNotifier extends StateNotifier<CyclicState> {
  int _lastManualStopTimestamp = 0;
  Timer? _countdownTimer;
  final Ref _ref;
  Function(String motorName, bool turnOn)? onCommandTrigger;
  Function(String payload)? onMqttSync;

  CyclicTimerNotifier(this._ref) : super(CyclicState()) {
    restoreStateFromHive();
  }

  Box? _getBox() {
    try {
      if (Hive.isBoxOpen(SessionNotifier.boxName)) {
        return Hive.box(SessionNotifier.boxName);
      }
    } catch (_) {}
    return null;
  }

  void restoreStateFromHive() {
    final box = _getBox();
    final String motorName = box?.get('cyclic_motorName', defaultValue: 'Motor 1') ?? 'Motor 1';
    final int runM = box?.get('cyclic_runMinutes', defaultValue: 15) ?? 15;
    final int pauseM = box?.get('cyclic_pauseMinutes', defaultValue: 45) ?? 45;
    final int totalC = box?.get('cyclic_totalCycles', defaultValue: 5) ?? 5;
    final int savedRemSec = box?.get('cyclic_remainingSeconds', defaultValue: 0) ?? 0;
    final String savedStatusStr = box?.get('cyclic_status', defaultValue: 'idle') ?? 'idle';
    final bool savedIsPausedByPower = box?.get('cyclic_isPausedByPower', defaultValue: false) ?? false;
    final bool userActive = box?.get('cyclic_user_active', defaultValue: false) ?? false;

    // Restore paused remaining seconds ONLY if user had actively started a cycle AND it was paused by power cut
    CyclicStatus initialStatus = CyclicStatus.idle;
    int initialRemSec = 0;
    if (userActive && savedStatusStr == 'paused' && savedIsPausedByPower && savedRemSec > 0) {
      initialStatus = CyclicStatus.paused;
      initialRemSec = savedRemSec;
    } else {
      box?.put('cyclic_status', 'idle');
      box?.put('cyclic_isPausedByPower', false);
      if (!userActive) {
        box?.put('cyclic_user_active', false);
      }
    }

    state = CyclicState(
      motorName: motorName,
      runMinutes: runM,
      pauseMinutes: pauseM,
      totalCycles: totalC,
      currentCycle: box?.get('cyclic_currentCycle', defaultValue: 1) ?? 1,
      isRunningPhase: box?.get('cyclic_isRunningPhase', defaultValue: true) ?? true,
      remainingSeconds: initialRemSec,
      status: initialStatus,
      isPausedByPower: initialStatus == CyclicStatus.paused,
    );
    _countdownTimer?.cancel();
  }

  void _saveToHive() {
    final box = _getBox();
    if (box == null) return;

    box.put('cyclic_status', state.status.name);
    box.put('cyclic_motorName', state.motorName);
    box.put('cyclic_runMinutes', state.runMinutes);
    box.put('cyclic_pauseMinutes', state.pauseMinutes);
    box.put('cyclic_totalCycles', state.totalCycles);
    box.put('cyclic_currentCycle', state.currentCycle);
    box.put('cyclic_isRunningPhase', state.isRunningPhase);
    box.put('cyclic_remainingSeconds', state.remainingSeconds);
    box.put('cyclic_isPausedByPower', state.isPausedByPower);
    box.put('cyclic_user_active', state.status == CyclicStatus.running || (state.status == CyclicStatus.paused && state.isPausedByPower));
    box.put('cyclic_phase_start_timestamp', DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

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

  void syncFromHardwareMqtt(String jsonPayload) {
    try {
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_lastManualStopTimestamp > 0 && (nowMs - _lastManualStopTimestamp < 10000)) {
        // User manually stopped cycle within last 10s; ignore stale retained MQTT status
        return;
      }

      final box = _getBox();
      final bool userActive = box?.get('cyclic_user_active', defaultValue: false) ?? false;

      final Map<String, dynamic> data = jsonDecode(jsonPayload);
      final bool running = data['running'] == true;
      final bool paused = data['paused'] == true;
      final int remSec = (data['remSec'] as num?)?.toInt() ?? 0;
      final int currCycle = (data['currCycle'] as num?)?.toInt() ?? 1;
      final int totalCycles = (data['cycles'] as num?)?.toInt() ?? state.totalCycles;
      final bool isRun = data['isRun'] == true;
      final int m = (data['m'] as num?)?.toInt() ?? 1;

      final String motorName = 'Motor $m';

      // If user has NOT actively started a cycle in this session, keep app in IDLE state (00:00, Start Cycle button)
      if (!userActive) {
        _countdownTimer?.cancel();
        state = state.copyWith(
          motorName: motorName,
          totalCycles: totalCycles,
          remainingSeconds: 0,
          status: CyclicStatus.idle,
          isPausedByPower: false,
        );
        box?.put('cyclic_user_active', false);
        return;
      }

      // If hardware is NOT running or paused, display fresh idle state (00:00, Start Cycle button)
      if (!running && !paused) {
        _countdownTimer?.cancel();
        state = state.copyWith(
          motorName: motorName,
          totalCycles: totalCycles,
          remainingSeconds: 0,
          status: CyclicStatus.idle,
          isPausedByPower: false,
        );
        box?.put('cyclic_user_active', false);
        _saveToHive();
        return;
      }

      // If hardware IS running or paused, sync active countdown display with hardware
      final CyclicStatus newStatus = paused ? CyclicStatus.paused : CyclicStatus.running;

      state = state.copyWith(
        motorName: motorName,
        totalCycles: totalCycles,
        currentCycle: currCycle,
        isRunningPhase: isRun,
        remainingSeconds: remSec,
        status: newStatus,
        isPausedByPower: paused,
      );

      _saveToHive();

      if (newStatus == CyclicStatus.running) {
        _runTick();
      } else {
        _countdownTimer?.cancel();
      }
    } catch (_) {}
  }

  void _syncToMqtt({bool stop = false}) {
    final Map<String, dynamic> payload = {
      'm': state.motorName == 'Motor 1' ? 1 : 2,
      'runM': state.runMinutes,
      'pauseM': state.pauseMinutes,
      'cycles': state.totalCycles,
      'en': stop ? false : (state.status == CyclicStatus.running),
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
    _saveToHive();
  }

  void startCycle({bool isPowerCut = false}) {
    if (state.runMinutes <= 0 || state.pauseMinutes <= 0) return;

    _countdownTimer?.cancel();

    if (isPowerCut) {
      state = state.copyWith(
        currentCycle: 1,
        isRunningPhase: true,
        remainingSeconds: state.runMinutes * 60,
        status: CyclicStatus.paused,
        isPausedByPower: true,
      );
      _saveToHive();
      _syncToMqttQueue();
      _ref.read(dataLogProvider.notifier).addLog(
            motorName: state.motorName,
            action: 'QUEUED',
            trigger: 'Cyclic',
            details: 'Cycle 1 Queued during Power Cut; Waiting for Grid Power',
          );
      return;
    }

    state = state.copyWith(
      currentCycle: 1,
      isRunningPhase: true,
      remainingSeconds: state.runMinutes * 60,
      status: CyclicStatus.running,
      isPausedByPower: false,
    );

    _saveToHive();
    _syncToMqtt();

    _ref.read(dataLogProvider.notifier).addLog(
          motorName: state.motorName,
          action: 'ON',
          trigger: 'Cyclic',
          details: 'Started Cycle 1 of ${state.totalCycles}',
        );

    _runTick();
  }

  void _syncToMqttQueue() {
    final Map<String, dynamic> payload = {
      'm': state.motorName == 'Motor 1' ? 1 : 2,
      'runM': state.runMinutes,
      'pauseM': state.pauseMinutes,
      'cycles': state.totalCycles,
      'en': true,
    };
    onMqttSync?.call(jsonEncode(payload));
  }

  void pauseTimer({bool isPowerOutage = false}) {
    _countdownTimer?.cancel();
    state = state.copyWith(
      status: CyclicStatus.paused,
      isPausedByPower: isPowerOutage,
    );
    _saveToHive();
  }

  void resumeTimer() {
    if (state.remainingSeconds > 0) {
      state = state.copyWith(
        status: CyclicStatus.running,
        isPausedByPower: false,
      );
      _saveToHive();
      _runTick();
    }
  }

  void stopCycle() {
    _countdownTimer?.cancel();
    _lastManualStopTimestamp = DateTime.now().millisecondsSinceEpoch;

    if (state.status == CyclicStatus.running && state.isRunningPhase) {
      onCommandTrigger?.call(state.motorName, false);
      _ref.read(dataLogProvider.notifier).addLog(
            motorName: state.motorName,
            action: 'OFF',
            trigger: 'Cyclic',
            details: 'Cycle stopped manually',
          );
    }

    state = state.copyWith(
      currentCycle: 1,
      isRunningPhase: true,
      status: CyclicStatus.idle,
      remainingSeconds: 0,
      isPausedByPower: false,
    );
    _saveToHive();
    _syncToMqtt(stop: true);
  }

  void _runTick() {
    _countdownTimer?.cancel();
    if (state.status != CyclicStatus.running || state.isPausedByPower) {
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final isOnline = _ref.read(deviceOnlineProvider);
      if (!isOnline || state.status != CyclicStatus.running || state.isPausedByPower) {
        _countdownTimer?.cancel();
        if (!isOnline && state.status == CyclicStatus.running) {
          state = state.copyWith(
            status: CyclicStatus.paused,
            isPausedByPower: true,
          );
        }
        return;
      }
      if (state.remainingSeconds > 1) {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
        if (state.remainingSeconds % 5 == 0) {
          _saveToHive();
        }
      } else {
        _transitionPhase();
      }
    });
  }

  void _transitionPhase() {
    if (state.isRunningPhase) {
      // Motor finished running phase -> Switch to Pause phase
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
        status: CyclicStatus.running,
        isPausedByPower: false,
      );
      _saveToHive();
      _runTick();
    } else {
      // Pause phase finished -> Check if cycles remaining
      if (state.currentCycle < state.totalCycles) {
        final nextCycle = state.currentCycle + 1;
        state = state.copyWith(
          currentCycle: nextCycle,
          isRunningPhase: true,
          remainingSeconds: state.runMinutes * 60,
          status: CyclicStatus.running,
          isPausedByPower: false,
        );
        _saveToHive();

        _ref.read(dataLogProvider.notifier).addLog(
              motorName: state.motorName,
              action: 'ON',
              trigger: 'Cyclic',
              details: 'Started Cycle $nextCycle of ${state.totalCycles}',
            );
        _runTick();
      } else {
        // All cycles finished
        _countdownTimer?.cancel();
        state = state.copyWith(
          status: CyclicStatus.completed,
          remainingSeconds: 0,
          isPausedByPower: false,
        );
        _saveToHive();
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
