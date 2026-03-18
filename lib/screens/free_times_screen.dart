import 'package:flutter/material.dart';
import '../repositories/free_time_repository.dart';
import '../models/free_time_slot.dart';
import '../widgets/free_time_tile.dart';
import '../core/app_theme.dart';

class FreeTimesScreen extends StatefulWidget {
  final FreeTimeRepository freeTimeRepository;

  const FreeTimesScreen({
    super.key,
    required this.freeTimeRepository,
  });

  @override
  State<FreeTimesScreen> createState() => _FreeTimesScreenState();
}

class _FreeTimesScreenState extends State<FreeTimesScreen> {
  Map<int, List<FreeTimeSlot>> _groupedSlots = {};
  final Map<int, bool> _expandedDays = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  void _loadSlots() {
    final grouped = widget.freeTimeRepository.getGroupedByDay();
    setState(() {
      _groupedSlots = grouped;
      for (int i = 1; i <= 7; i++) {
        _expandedDays[i] = true;
      }
      _isLoading = false;
    });
  }

  Future<void> _deleteSlot(FreeTimeSlot slot) async {
    widget.freeTimeRepository.delete(slot.id);
    _loadSlots();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Time slot deleted'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AddFreeTimeDialog(
        freeTimeRepository: widget.freeTimeRepository,
        onSave: _loadSlots,
      ),
    );
  }

  String _getDayName(int dayOfWeek) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[dayOfWeek];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Free Times',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 7,
              itemBuilder: (context, index) {
                final dayOfWeek = index + 1;
                final slots = _groupedSlots[dayOfWeek] ?? [];
                final isExpanded = _expandedDays[dayOfWeek] ?? true;

                return Card(
                  color: AppColors.surface,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedDays[dayOfWeek] = !isExpanded;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.accentDim,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _getDayName(dayOfWeek),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              if (slots.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentDim,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${slots.length}',
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded && slots.isNotEmpty)
                        Column(
                          children: slots.map((slot) {
                            return FreeTimeTile(
                              slot: slot,
                              onDelete: () => _deleteSlot(slot),
                            );
                          }).toList(),
                        ),
                      if (isExpanded && slots.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 68, right: 16, bottom: 16),
                          child: Text(
                            'No free times set',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddFreeTimeDialog extends StatefulWidget {
  final FreeTimeRepository freeTimeRepository;
  final Function onSave;

  const AddFreeTimeDialog({
    super.key,
    required this.freeTimeRepository,
    required this.onSave,
  });

  @override
  State<AddFreeTimeDialog> createState() => _AddFreeTimeDialogState();
}

class _AddFreeTimeDialogState extends State<AddFreeTimeDialog> {
  int _selectedDay = 1;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 0);

  String _getDayName(int dayOfWeek) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[dayOfWeek];
  }

  Future<void> _selectStartTime() async {
    final time = await showTimePicker(context: context, initialTime: _startTime);
    if (time != null) setState(() => _startTime = time);
  }

  Future<void> _selectEndTime() async {
    final time = await showTimePicker(context: context, initialTime: _endTime);
    if (time != null) setState(() => _endTime = time);
  }

  bool _validateTimes() {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    return endMinutes > startMinutes;
  }

  void _save() {
    if (!_validateTimes()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time'), backgroundColor: AppColors.error),
      );
      return;
    }

    final slot = FreeTimeSlot(
      dayOfWeek: _selectedDay,
      startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
      endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
    );

    widget.freeTimeRepository.save(slot);
    Navigator.of(context).pop();
    widget.onSave();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Time slot added'), backgroundColor: AppColors.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Add Free Time', style: TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              value: _selectedDay,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Day'),
              items: List.generate(7, (index) {
                final day = index + 1;
                return DropdownMenuItem(value: day, child: Text(_getDayName(day)));
              }),
              onChanged: (value) {
                if (value != null) setState(() => _selectedDay = value);
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectStartTime,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Start Time'),
                child: Text(_startTime.format(context), style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectEndTime,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'End Time'),
                child: Text(_endTime.format(context), style: const TextStyle(color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.background,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
