import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';

class MotorSchedule {
  final String id;
  final String motorName; // 'Motor 1' or 'Motor 2'
  final TimeOfDay onTime;
  final TimeOfDay offTime;
  final bool isEnabled;
  final DateTime? date;

  MotorSchedule({
    required this.id,
    required this.motorName,
    required this.onTime,
    required this.offTime,
    this.isEnabled = true,
    this.date,
  });

  MotorSchedule copyWith({
    String? id,
    String? motorName,
    TimeOfDay? onTime,
    TimeOfDay? offTime,
    bool? isEnabled,
    DateTime? date,
  }) {
    return MotorSchedule(
      id: id ?? this.id,
      motorName: motorName ?? this.motorName,
      onTime: onTime ?? this.onTime,
      offTime: offTime ?? this.offTime,
      isEnabled: isEnabled ?? this.isEnabled,
      date: date ?? this.date,
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
        'date': date?.toIso8601String(),
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
        date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
      );
}

class SchedulerNotifier extends StateNotifier<List<MotorSchedule>> {
  static const String _boxName = 'sessionBox';
  static const String _key = 'schedulesList';

  Timer? _checkerTimer;
  StreamSubscription<DatabaseEvent>? _firebaseSubscription;
  final Ref _ref;
  Function(String motorName, bool turnOn)? onCommandTrigger;
  Function(String payload)? onMqttSync;

  final Set<String> _triggeredSchedulesThisMinute = {};
  String _lastTriggeredMinuteKey = '';

  SchedulerNotifier(this._ref) : super([]) {
    _loadSchedulesFromCache();
    _listenToFirebaseSchedules();
    _startTimer();
  }

  @override
  void dispose() {
    _checkerTimer?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }

  String _getUserKey() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return '';
      final box = Hive.box(_boxName);
      final rawKey = box.get('userKey', defaultValue: '').toString().trim();
      return rawKey.replaceAll(RegExp(r'[.#$\[\]/]'), '_');
    } catch (_) {
      return '';
    }
  }

  void refreshFirebaseListener() {
    _listenToFirebaseSchedules();
  }

  void _loadSchedulesFromCache() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box(_boxName);
      final rawList = box.get(_key, defaultValue: []);
      if (rawList is List) {
        final schedules = rawList
            .map((item) {
              if (item is String) {
                return MotorSchedule.fromJson(jsonDecode(item));
              } else if (item is Map) {
                return MotorSchedule.fromJson(Map<String, dynamic>.from(item));
              }
              return null;
            })
            .whereType<MotorSchedule>()
            .toList();
        state = schedules;
      }
    } catch (_) {}
  }

  void _listenToFirebaseSchedules() {
    final userKey = _getUserKey();
    if (userKey.isEmpty) return;

    final DatabaseReference ref = FirebaseDatabase.instance.ref('arisers/$userKey/schedules');
    _firebaseSubscription?.cancel();
    _firebaseSubscription = ref.onValue.listen((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        state = [];
        _saveToCacheAndMqtt([]);
        return;
      }

      final Object? value = event.snapshot.value;
      final List<MotorSchedule> loadedSchedules = [];

      if (value is Map) {
        final Map<dynamic, dynamic> map = Map<dynamic, dynamic>.from(value);
        for (final entry in map.entries) {
          if (entry.value is Map) {
            final Map<String, dynamic> schedJson = Map<String, dynamic>.from(entry.value as Map);
            loadedSchedules.add(MotorSchedule.fromJson(schedJson));
          }
        }
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final Map<String, dynamic> schedJson = Map<String, dynamic>.from(item);
            loadedSchedules.add(MotorSchedule.fromJson(schedJson));
          }
        }
      }

      state = loadedSchedules;
      _saveToCacheAndMqtt(loadedSchedules);
    }, onError: (error) {
      debugPrint('Firebase schedule listener error: $error');
    });
  }

  void _startTimer() {
    _checkerTimer?.cancel();
    _checkerTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _evaluateSchedules();
    });
  }

  void _evaluateSchedules() {
    if (_firebaseSubscription == null) {
      _listenToFirebaseSchedules();
    }

    final now = DateTime.now();
    final String currentMinuteKey = '${now.year}-${now.month}-${now.day}-${now.hour}:${now.minute}';

    if (_lastTriggeredMinuteKey != currentMinuteKey) {
      _lastTriggeredMinuteKey = currentMinuteKey;
      _triggeredSchedulesThisMinute.clear();
    }

    final List<String> toDeleteIds = [];

    for (final schedule in state) {
      if (schedule.date != null) {
        final schedDate = schedule.date!;
        final expirationDateTime = DateTime(
          schedDate.year,
          schedDate.month,
          schedDate.day,
          schedule.offTime.hour,
          schedule.offTime.minute,
        );

        if (now.isAfter(expirationDateTime.add(const Duration(seconds: 30)))) {
          toDeleteIds.add(schedule.id);
          continue;
        }

        final isSameDate = now.year == schedDate.year &&
            now.month == schedDate.month &&
            now.day == schedDate.day;

        if (!isSameDate) continue;
      }

      if (!schedule.isEnabled) continue;

      final isMatchON = now.hour == schedule.onTime.hour &&
          now.minute == schedule.onTime.minute &&
          now.second < 25;

      final isMatchOFF = now.hour == schedule.offTime.hour &&
          now.minute == schedule.offTime.minute &&
          now.second < 25;

      final onKey = '${schedule.id}_ON';
      final offKey = '${schedule.id}_OFF';

      if (isMatchON && !_triggeredSchedulesThisMinute.contains(onKey)) {
        _triggeredSchedulesThisMinute.add(onKey);
        onCommandTrigger?.call(schedule.motorName, true);
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: schedule.motorName,
              action: 'ON',
              trigger: 'Scheduler',
              details: 'Triggered at ${_formatTime(schedule.onTime)}',
            );
      } else if (isMatchOFF && !_triggeredSchedulesThisMinute.contains(offKey)) {
        _triggeredSchedulesThisMinute.add(offKey);
        onCommandTrigger?.call(schedule.motorName, false);
        _ref.read(dataLogProvider.notifier).addLog(
              motorName: schedule.motorName,
              action: 'OFF',
              trigger: 'Scheduler',
              details: 'Triggered at ${_formatTime(schedule.offTime)}',
            );
      }
    }

    for (final id in toDeleteIds) {
      deleteSchedule(id);
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
    DateTime? date,
  }) async {
    final newSchedule = MotorSchedule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      motorName: motorName,
      onTime: onTime,
      offTime: offTime,
      isEnabled: true,
      date: date,
    );

    state = [...state, newSchedule];
    await _syncScheduleToFirebase(newSchedule);
    _saveToCacheAndMqtt(state);
  }

  Future<void> toggleSchedule(String id) async {
    MotorSchedule? updated;
    state = state.map((s) {
      if (s.id == id) {
        updated = s.copyWith(isEnabled: !s.isEnabled);
        return updated!;
      }
      return s;
    }).toList();

    if (updated != null) {
      await _syncScheduleToFirebase(updated!);
    }
    _saveToCacheAndMqtt(state);
  }

  Future<void> deleteSchedule(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _deleteScheduleFromFirebase(id);
    _saveToCacheAndMqtt(state);
  }

  Future<void> _syncScheduleToFirebase(MotorSchedule schedule) async {
    final userKey = _getUserKey();
    if (userKey.isEmpty) return;

    if (_firebaseSubscription == null) {
      _listenToFirebaseSchedules();
    }

    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'arisers/$userKey/schedules/${schedule.id}',
      );
      await ref.set(schedule.toJson());
    } catch (e) {
      debugPrint('Error syncing schedule to Firebase: $e');
    }
  }

  Future<void> _deleteScheduleFromFirebase(String id) async {
    final userKey = _getUserKey();
    if (userKey.isEmpty) return;

    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref(
        'arisers/$userKey/schedules/$id',
      );
      await ref.remove();
    } catch (e) {
      debugPrint('Error deleting schedule from Firebase: $e');
    }
  }

  void setCommandHandler(Function(String motorName, bool turnOn) handler) {
    onCommandTrigger = handler;
  }

  void setMqttSyncHandler(Function(String payload) handler) {
    onMqttSync = handler;
  }

  void _saveToCacheAndMqtt(List<MotorSchedule> schedules) {
    try {
      final box = Hive.box(_boxName);
      final rawList = schedules.map((s) => jsonEncode(s.toJson())).toList();
      box.put(_key, rawList);

      final espList = schedules.map((s) => {
        'm': s.motorName == 'Motor 1' ? 1 : 2,
        'onH': s.onTime.hour,
        'onM': s.onTime.minute,
        'offH': s.offTime.hour,
        'offM': s.offTime.minute,
        'en': s.isEnabled,
        'yr': s.date?.year ?? 0,
        'mo': s.date?.month ?? 0,
        'dy': s.date?.day ?? 0,
      }).toList();

      onMqttSync?.call(jsonEncode(espList));
    } catch (_) {}
  }
}

final schedulerProvider =
    StateNotifierProvider<SchedulerNotifier, List<MotorSchedule>>((ref) {
  return SchedulerNotifier(ref);
});
