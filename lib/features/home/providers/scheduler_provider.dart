import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';

class MotorSchedule {
  final String id;
  final String motorName; // 'Motor 1' or 'Motor 2'
  final TimeOfDay onTime;
  final TimeOfDay offTime;
  final bool isEnabled;

  MotorSchedule({
    required this.id,
    required this.motorName,
    required this.onTime,
    required this.offTime,
    this.isEnabled = true,
  });

  MotorSchedule copyWith({
    String? id,
    String? motorName,
    TimeOfDay? onTime,
    TimeOfDay? offTime,
    bool? isEnabled,
  }) {
    return MotorSchedule(
      id: id ?? this.id,
      motorName: motorName ?? this.motorName,
      onTime: onTime ?? this.onTime,
      offTime: offTime ?? this.offTime,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'motorName': motorName,
        'onHour': onTime.hour,
        'onMinute': onTime.minute,
        'offHour': offTime.hour,
        'offMinute': offTime.minute,
        'isEnabled': isEnabled,
      };

  factory MotorSchedule.fromJson(Map<String, dynamic> json) => MotorSchedule(
        id: json['id'] ?? '',
        motorName: json['motorName'] ?? 'Motor 1',
        onTime: TimeOfDay(
          hour: json['onHour'] ?? 6,
          minute: json['onMinute'] ?? 0,
        ),
        offTime: TimeOfDay(
          hour: json['offHour'] ?? 7,
          minute: json['offMinute'] ?? 0,
        ),
        isEnabled: json['isEnabled'] ?? true,
      );
}

class SchedulerNotifier extends StateNotifier<List<MotorSchedule>> {
  static const String _boxName = 'sessionBox';
  static const String _key = 'schedulesList';

  Timer? _checkerTimer;
  final Ref _ref;
  Function(String motorName, bool turnOn)? onCommandTrigger;

  SchedulerNotifier(this._ref) : super([]) {
    _loadSchedules();
    _startTimer();
  }

  @override
  void dispose() {
    _checkerTimer?.cancel();
    super.dispose();
  }

  void setCommandHandler(Function(String motorName, bool turnOn) handler) {
    onCommandTrigger = handler;
  }

  void _loadSchedules() {
    try {
      final box = Hive.box(_boxName);
      final rawList = box.get(_key, defaultValue: []);
      if (rawList is List) {
        final schedules = rawList
            .map((item) {
              if (item is String) {
                return MotorSchedule.fromJson(jsonDecode(item));
              }
              return null;
            })
            .whereType<MotorSchedule>()
            .toList();
        state = schedules;
      }
    } catch (_) {}
  }

  void _startTimer() {
    _checkerTimer?.cancel();
    _checkerTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _evaluateSchedules();
    });
  }

  void _evaluateSchedules() {
    final now = DateTime.now();
    for (final schedule in state) {
      if (!schedule.isEnabled) continue;

      final isMatchON = now.hour == schedule.onTime.hour &&
          now.minute == schedule.onTime.minute &&
          now.second < 25;

      final isMatchOFF = now.hour == schedule.offTime.hour &&
          now.minute == schedule.offTime.minute &&
          now.second < 25;

      if (isMatchON) {
        onCommandTrigger?.call(schedule.motorName, true);
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: schedule.motorName,
              action: 'ON',
              trigger: 'Scheduler',
              details: 'Triggered at ${_formatTime(schedule.onTime)}',
            );
      } else if (isMatchOFF) {
        onCommandTrigger?.call(schedule.motorName, false);
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: schedule.motorName,
              action: 'OFF',
              trigger: 'Scheduler',
              details: 'Triggered at ${_formatTime(schedule.offTime)}',
            );
      }
    }
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  Future<void> addSchedule({
    required String motorName,
    required TimeOfDay onTime,
    required TimeOfDay offTime,
  }) async {
    final newSchedule = MotorSchedule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      motorName: motorName,
      onTime: onTime,
      offTime: offTime,
      isEnabled: true,
    );

    state = [...state, newSchedule];
    _saveSchedules();
  }

  Future<void> toggleSchedule(String id) async {
    state = state.map((s) {
      if (s.id == id) {
        return s.copyWith(isEnabled: !s.isEnabled);
      }
      return s;
    }).toList();

    _saveSchedules();
  }

  Future<void> deleteSchedule(String id) async {
    state = state.where((s) => s.id != id).toList();
    _saveSchedules();
  }

  void _saveSchedules() {
    try {
      final box = Hive.box(_boxName);
      final rawList = state.map((s) => jsonEncode(s.toJson())).toList();
      box.put(_key, rawList);
    } catch (_) {}
  }
}

final schedulerProvider =
    StateNotifierProvider<SchedulerNotifier, List<MotorSchedule>>((ref) {
  return SchedulerNotifier(ref);
});
