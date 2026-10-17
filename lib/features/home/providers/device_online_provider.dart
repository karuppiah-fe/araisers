import 'package:flutter_riverpod/flutter_riverpod.dart';

final deviceOnlineProvider = StateProvider<bool>((ref) => false);
final rVoltageProvider = StateProvider<double>((ref) => 0.0);
