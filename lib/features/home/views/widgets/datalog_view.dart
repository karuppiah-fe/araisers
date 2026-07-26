import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arisers/core/theme/app_colors.dart';
import 'package:arisers/features/home/providers/datalog_provider.dart';
import 'package:arisers/features/localization/providers/words_provider.dart';

class DataLogView extends ConsumerStatefulWidget {
  const DataLogView({super.key});

  @override
  ConsumerState<DataLogView> createState() => _DataLogViewState();
}

class _DataLogViewState extends ConsumerState<DataLogView> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(dataLogProvider);
    final activeLanguage = ref.watch(localeProvider);

    final filteredLogs = logs.where((log) {
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Motor 1') return log.motorName == 'Motor 1';
      if (_selectedFilter == 'Motor 2') return log.motorName == 'Motor 2';
      if (_selectedFilter == 'Trips') return log.trigger == 'Safety Trip';
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Filter Chips & Clear Action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Motor 1'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Motor 2'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Trips'),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: AppColors.error),
                  tooltip: Words.get('clear_logs', activeLanguage),
                  onPressed: () {
                    ref.read(dataLogProvider.notifier).clearLogs();
                  },
                ),
              ],
            ),
          ),

          // Log List
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          Words.get('no_logs', activeLanguage),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = filteredLogs[index];
                      return _buildLogCard(log, activeLanguage);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) {
        setState(() => _selectedFilter = label);
      },
    );
  }

  Widget _buildLogCard(DataLogEntry log, AppLanguage activeLanguage) {
    final isON = log.action == 'ON';
    final isTrip = log.trigger == 'Safety Trip';

    final Color badgeColor = isTrip
        ? AppColors.error
        : (isON ? AppColors.primary : Colors.grey.shade600);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isTrip
                    ? Icons.warning_amber_rounded
                    : (isON ? Icons.power_outlined : Icons.power_off_outlined),
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${log.motorName} - ${log.action}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                      Text(
                        _formatTimestamp(log.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          log.trigger,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (log.details.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            log.details,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }
}
