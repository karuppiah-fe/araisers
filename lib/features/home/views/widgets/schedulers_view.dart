import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/features/home/providers/scheduler_provider.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';

class SchedulersView extends ConsumerWidget {
  const SchedulersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulerProvider);
    final activeLanguage = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: schedules.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.alarm_off,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No motor schedules configured',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                final schedule = schedules[index];
                return _buildScheduleCard(context, ref, schedule, activeLanguage);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _showAddScheduleDialog(context, ref, activeLanguage),
        icon: const Icon(Icons.add_alarm),
        label: Text(Words.get('add_schedule', activeLanguage)),
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context,
    WidgetRef ref,
    MotorSchedule schedule,
    AppLanguage activeLanguage,
  ) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: schedule.isEnabled
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.access_time_filled,
                color: schedule.isEnabled
                    ? AppColors.primary
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        schedule.motorName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: schedule.date != null ? Colors.blue.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: schedule.date != null ? Colors.blue.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 11,
                              color: schedule.date != null ? Colors.blue.shade800 : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              schedule.date != null
                                  ? '${schedule.date!.day.toString().padLeft(2, '0')}/${schedule.date!.month.toString().padLeft(2, '0')}/${schedule.date!.year}'
                                  : 'Everyday',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: schedule.date != null ? Colors.blue.shade900 : Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${Words.get('on_time', activeLanguage)}: ',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatTime(schedule.onTime),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '${Words.get('off_time', activeLanguage)}: ',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        _formatTime(schedule.offTime),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: schedule.isEnabled,
              activeColor: AppColors.primary,
              onChanged: (_) {
                ref
                    .read(schedulerProvider.notifier)
                    .toggleSchedule(schedule.id);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () {
                ref
                    .read(schedulerProvider.notifier)
                    .deleteSchedule(schedule.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddScheduleDialog(
    BuildContext context,
    WidgetRef ref,
    AppLanguage activeLanguage,
  ) {
    String selectedMotor = 'Motor 1';
    TimeOfDay selectedOnTime = const TimeOfDay(hour: 6, minute: 0);
    TimeOfDay selectedOffTime = const TimeOfDay(hour: 7, minute: 30);
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(Words.get('add_schedule', activeLanguage)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedMotor,
                decoration: InputDecoration(
                  labelText: Words.get('select_motor', activeLanguage),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'Motor 1', child: Text('Motor 1')),
                  DropdownMenuItem(value: 'Motor 2', child: Text('Motor 2')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => selectedMotor = val);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule Date'),
                subtitle: Text(
                  selectedDate == null
                      ? 'Everyday (Daily Recurring)'
                      : '${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}',
                  style: TextStyle(
                    color: selectedDate != null ? AppColors.primary : Colors.grey.shade600,
                    fontWeight: selectedDate != null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 20),
                        tooltip: 'Clear Date (Make Daily)',
                        onPressed: () => setState(() => selectedDate = null),
                      ),
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.primary,
                    ),
                  ],
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => selectedDate = picked);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(Words.get('on_time', activeLanguage)),
                trailing: Chip(
                  label: Text(_formatTime(selectedOnTime)),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedOnTime,
                  );
                  if (time != null) {
                    setState(() => selectedOnTime = time);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(Words.get('off_time', activeLanguage)),
                trailing: Chip(
                  label: Text(_formatTime(selectedOffTime)),
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedOffTime,
                  );
                  if (time != null) {
                    setState(() => selectedOffTime = time);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Words.get('cancel', activeLanguage)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                ref.read(schedulerProvider.notifier).addSchedule(
                      motorName: selectedMotor,
                      onTime: selectedOnTime,
                      offTime: selectedOffTime,
                      date: selectedDate,
                    );
                Navigator.pop(dialogContext);
              },
              child: Text(Words.get('confirm', activeLanguage)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }
}
