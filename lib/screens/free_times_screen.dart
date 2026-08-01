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
        SnackBar(
          content: Text(Translations.timeSlotDeleted(_locale)),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        title: Text(
          Translations.freeTimes(_locale),
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.whiteAccent),
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
                  shadowColor: AppColors.whiteShadow,
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
                                  color: AppColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.zero,
                                ),
                                child: const Icon(
                                  Icons.calendar_today,
                                  color: AppColors.accent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                Translations.getDayName(dayOfWeek, _locale),
                                style: TextStyle(
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
                                    color: AppColors.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.zero,
                                  ),
                                  child: Text(
                                    '${slots.length}',
                                    style: TextStyle(
                                      color: AppColors.whiteAccent,
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
                                color: AppColors.whiteTextSecondary
                                    .withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Translations.noFreeTimesSet(_locale),
                                style: TextStyle(
                                  color: AppColors.whiteTextSecondary
                                      .withValues(alpha: 0.7),
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
        backgroundColor: AppColors.whiteAccent,
        foregroundColor: AppColors.whiteBackground,
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
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.whiteAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
              surface: Colors.white,
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.black),
              bodyMedium: TextStyle(color: Colors.black),
            ),
          ),
          child: child!,
        );
      },
    );
    if (time != null) setState(() => _startTime = time);
  }

  Future<void> _selectEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.whiteAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
              surface: Colors.white,
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(color: Colors.black),
              bodyMedium: TextStyle(color: Colors.black),
            ),
          ),
          child: child!,
        );
      },
    );
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
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: AppColors.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  Translations.addFreeTime(_locale),
                  style: TextStyle(
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
              style: TextStyle(color: AppColors.whiteTextPrimary),
              decoration: InputDecoration(
                labelText: Translations.day(_locale),
                labelStyle: TextStyle(color: AppColors.whiteTextSecondary),
                filled: true,
                fillColor: AppColors.whiteBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: const BorderSide(
                    color: AppColors.whiteAccent,
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
                  labelStyle: TextStyle(color: AppColors.whiteTextSecondary),
                  filled: true,
                  fillColor: AppColors.whiteBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  suffixIcon: const Icon(
                    Icons.access_time,
                    color: AppColors.whiteAccent,
                  ),
                ),
                child: Text(
                  _startTime.format(context),
                  style: TextStyle(
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
                  labelStyle: TextStyle(color: AppColors.whiteTextSecondary),
                  filled: true,
                  fillColor: AppColors.whiteBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: AppColors.whiteTextSecondary.withValues(alpha: 0.3),
                    ),
                  ),
                  suffixIcon: const Icon(
                    Icons.access_time,
                    color: AppColors.whiteAccent,
                  ),
                ),
                child: Text(
                  _endTime.format(context),
                  style: TextStyle(
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(Translations.cancel(_locale)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.whiteAccent,
                    foregroundColor: AppColors.whiteBackground,
                    elevation: 2,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
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
