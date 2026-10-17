import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DataLogEntry {
  final String id;
  final DateTime timestamp;
  final String motorName; // 'Motor 1' or 'Motor 2'
  final String action; // 'ON' or 'OFF'
  final String trigger; // 'Manual', 'Scheduler', 'Cyclic', 'Trip'
  final String userName; // User who performed the action
  final String details;

  DataLogEntry({
    required this.id,
    required this.timestamp,
    required this.motorName,
    required this.action,
    required this.trigger,
    this.userName = 'System',
    this.details = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'motorName': motorName,
        'action': action,
        'trigger': trigger,
        'userName': userName,
        'details': details,
      };

  factory DataLogEntry.fromJson(Map<String, dynamic> json) => DataLogEntry(
        id: json['id'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
        motorName: json['motorName'] ?? '',
        action: json['action'] ?? '',
        trigger: json['trigger'] ?? '',
        userName: json['userName'] ?? 'System',
        details: json['details'] ?? '',
      );
}

class DataLogNotifier extends StateNotifier<List<DataLogEntry>> {
  static const String _boxName = 'sessionBox';
  static const String _key = 'dataLogsList';

  DataLogNotifier() : super([]) {
    _loadLogs();
  }

  void _loadLogs() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box(_boxName);
      final rawList = box.get(_key, defaultValue: []);
      if (rawList is List) {
        final logs = rawList
            .map((item) {
              if (item is String) {
                return DataLogEntry.fromJson(jsonDecode(item));
              }
              return null;
            })
            .whereType<DataLogEntry>()
            .toList();

        // Sort descending by timestamp
        logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        state = logs;
      }
    } catch (_) {}
  }

  String _resolveUserName(String providedUserName) {
    if (providedUserName != 'System' && providedUserName.isNotEmpty) {
      return providedUserName;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          return user.displayName!;
        }
        if (user.email != null && user.email!.isNotEmpty) {
          return user.email!;
        }
      }
      if (Hive.isBoxOpen(_boxName)) {
        final String? sessionUser = Hive.box(_boxName).get('userKey');
        if (sessionUser != null && sessionUser.isNotEmpty) {
          return sessionUser;
        }
      }
    } catch (_) {}
    return providedUserName;
  }

  Future<void> addLog({
    required String motorName,
    required String action,
    required String trigger,
    String userName = 'System',
    String details = '',
  }) async {
    final String resolvedUser = _resolveUserName(userName);

    final newEntry = DataLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      motorName: motorName,
      action: action,
      trigger: trigger,
      userName: resolvedUser,
      details: details,
    );

    final updated = [newEntry, ...state];
    state = updated;
    _saveLogs();
  }

  Future<void> clearLogs() async {
    state = [];
    _saveLogs();
  }

  void _saveLogs() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box(_boxName);
      final rawList = state.map((log) => jsonEncode(log.toJson())).toList();
      box.put(_key, rawList);
    } catch (_) {}
  }
}

final dataLogProvider =
    StateNotifierProvider<DataLogNotifier, List<DataLogEntry>>((ref) {
  return DataLogNotifier();
});
