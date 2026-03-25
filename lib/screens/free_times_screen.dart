import 'package:flutter/material.dart';
import '../repositories/free_time_repository.dart';
import '../models/free_time_slot.dart';
import '../widgets/free_time_tile.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';

class FreeTimesScreen extends StatefulWidget {
  final FreeTimeRepository freeTimeRepository;

  const FreeTimesScreen({super.key, required this.freeTimeRepository});

  @override
  State<FreeTimesScreen> createState() => _FreeTimesScreenState();
}

class _FreeTimesScreenState extends State<FreeTimesScreen> {
  Map<int, List<FreeTimeSlot>> _groupedSlots = {};
  final Map<int, bool> _expandedDays = {};
  bool _isLoading = true;

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _loadSlots();
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
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

  IconData _getDayIcon(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1:
        return Icons.looks_one;
      case 2:
        return Icons.looks_two;
      case 3:
        return Icons.looks_3;
      case 4:
        return Icons.looks_4;
      case 5:
        return Icons.looks_5;
      case 6:
        return Icons.looks_6;
      case 7:
        return Icons.looks_one;
      default:
        return Icons.calendar_today;
    }
  }

  String _getDayName(int dayOfWeek) {
    const days = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[dayOfWeek];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        title: Text(
          Translations.freeTimes(_locale),
          style: const TextStyle(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 7,
              itemBuilder: (context, index) {
                final dayOfWeek = index + 1;
                final slots = _groupedSlots[dayOfWeek] ?? [];
                final isExpanded = _expandedDays[dayOfWeek] ?? true;

                return Card(
                  color: AppColors.whiteSurface,
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedDays[dayOfWeek] = !isExpanded;
                          });
                        },
                        borderRadius: BorderRadius.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withOpacity(0.1),
                                  borderRadius: BorderRadius.zero,
                                ),
                                child: Icon(
                                  _getDayIcon(dayOfWeek),
                                  color: AppColors.accent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                Translations.getDayName(dayOfWeek, _locale),
                                style: const TextStyle(
                                  color: AppColors.whiteTextPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_right,
                                color: AppColors.whiteTextSecondary,
                              ),
                              if (slots.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.zero,
                                  ),
                                  child: Text(
                                    '${slots.length}',
                                    style: const TextStyle(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
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
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 68,
                            right: 16,
                            bottom: 16,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.event_available,
                                size: 16,
                                color: AppColors.whiteTextSecondary.withOpacity(
                                  0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Translations.noFreeTimesSet(_locale),
                                style: TextStyle(
                                  color: AppColors.whiteTextSecondary
                                      .withOpacity(0.7),
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
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

  String get _locale => LocaleManager.instance.getLocale();

  Future<void> _selectStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
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
        SnackBar(
          content: Text(Translations.endTimeMustBeAfter(_locale)),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final slot = FreeTimeSlot(
      dayOfWeek: _selectedDay,
      startTime:
          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
      endTime:
          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
    );

    widget.freeTimeRepository.save(slot);
    Navigator.of(context).pop();
    widget.onSave();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Translations.timeSlotAdded(_locale)),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.whiteSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Icon(
                    Icons.schedule,
                    color: AppColors.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  Translations.addFreeTime(_locale),
                  style: const TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: _selectedDay,
              dropdownColor: AppColors.whiteSurface,
              style: const TextStyle(color: AppColors.whiteTextPrimary),
              decoration: InputDecoration(
                labelText: Translations.day(_locale),
                labelStyle: const TextStyle(
                  color: AppColors.whiteTextSecondary,
                ),
                filled: true,
                fillColor: AppColors.whiteBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: AppColors.whiteTextSecondary.withOpacity(0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: AppColors.whiteTextSecondary.withOpacity(0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.accent,
                    width: 2,
                  ),
                ),
              ),
              items: List.generate(7, (index) {
                final day = index + 1;
                return DropdownMenuItem(
                  value: day,
                  child: Text(Translations.getDayName(day, _locale)),
                );
              }),
              onChanged: (value) {
                if (value != null) setState(() => _selectedDay = value);
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectStartTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: Translations.startTime(_locale),
                  labelStyle: const TextStyle(
                    color: AppColors.whiteTextSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.whiteBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withOpacity(0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withOpacity(0.3),
                    ),
                  ),
                  suffixIcon: const Icon(
                    Icons.access_time,
                    color: AppColors.accent,
                  ),
                ),
                child: Text(
                  _startTime.format(context),
                  style: const TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectEndTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: Translations.endTime(_locale),
                  labelStyle: const TextStyle(
                    color: AppColors.whiteTextSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.whiteBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withOpacity(0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withOpacity(0.3),
                    ),
                  ),
                  suffixIcon: const Icon(
                    Icons.access_time,
                    color: AppColors.accent,
                  ),
                ),
                child: Text(
                  _endTime.format(context),
                  style: const TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.whiteTextSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(Translations.cancel(_locale)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(Translations.save(_locale)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
