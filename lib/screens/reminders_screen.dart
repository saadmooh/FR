import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/free_time_repository.dart';
import '../repositories/category_statistic_repository.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
import '../models/reminder.dart';
import '../widgets/modern_reminder_card.dart';
import '../widgets/save_post_sheet.dart';
import '../widgets/empty_state.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/locale_manager.dart';
import '../core/translations.dart';

class RemindersScreen extends StatefulWidget {
  final ReminderRepository reminderRepository;
  final FreeTimeRepository freeTimeRepository;
  final CategoryStatisticRepository categoryStatRepository;
  final NotificationService notificationService;
  final AIService aiService;
  final ValueNotifier<String?> pendingSharedUrl;
  final ValueNotifier<String?> aiRescheduleError;

  const RemindersScreen({
    super.key,
    required this.reminderRepository,
    required this.freeTimeRepository,
    required this.categoryStatRepository,
    required this.notificationService,
    required this.aiService,
    required this.pendingSharedUrl,
    required this.aiRescheduleError,
  });

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedComplexity;
  String? _selectedImportance;
  String? _selectedDomain;
  List<String> _availableCategories = [];
  List<String> _availableComplexities = [];
  List<String> _availableDomains = [];
  List<Reminder> _allReminders = [];
  bool _isLoading = true;
  bool _isSearchVisible = false;

  String get _locale => LocaleManager.instance.getLocale();

  @override
  void initState() {
    super.initState();
    _loadReminders();
    widget.pendingSharedUrl.addListener(_onPendingSharedUrlChanged);
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAiRescheduleErrorIfNeeded();
    });
  }

  @override
  void dispose() {
    widget.pendingSharedUrl.removeListener(_onPendingSharedUrlChanged);
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _showAiRescheduleErrorIfNeeded() {
    final error = widget.aiRescheduleError.value;
    if (error != null && error.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI reschedule failed: $error'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          duration: const Duration(seconds: 5),
        ),
      );
      widget.aiRescheduleError.value = null;
    }
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedCategory != null ||
      _selectedComplexity != null ||
      _selectedImportance != null ||
      _selectedDomain != null;

  List<Reminder> get _filteredReminders {
    return _allReminders.where((reminder) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final titleMatch =
            reminder.title.toLowerCase().contains(query);
        final descMatch =
            reminder.description?.toLowerCase().contains(query) ?? false;
        if (!titleMatch && !descMatch) return false;
      }
      if (_selectedCategory != null &&
          reminder.categoryEn != _selectedCategory) {
        return false;
      }
      if (_selectedComplexity != null &&
          reminder.complexityEn != _selectedComplexity) {
        return false;
      }
      if (_selectedImportance != null &&
          reminder.importance != _selectedImportance) {
        return false;
      }
      if (_selectedDomain != null &&
          _extractDomain(reminder.url) != _selectedDomain) {
        return false;
      }
      return true;
    }).toList();
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.accent : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  void _onPendingSharedUrlChanged() {
    final url = widget.pendingSharedUrl.value;
    if (url != null && url.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSaveSheet(initialUrl: url);
        widget.pendingSharedUrl.value = null;
      });
    }
  }

  void _loadReminders() {
    final unread = widget.reminderRepository.getUnread();
    final read = widget.reminderRepository.getRead();
    setState(() {
      _allReminders = [...unread, ...read];
      _isLoading = false;
    });
    _loadFilterOptions();
  }

  void _loadFilterOptions() {
    final allReminders = widget.reminderRepository.getAll();

    final categories = allReminders
        .map((r) => r.categoryEn)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    categories.sort();

    final complexities = allReminders
        .map((r) => r.complexityEn)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    complexities.sort();

    final domains = allReminders
        .map((r) => _extractDomain(r.url))
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();
    domains.sort();

    setState(() {
      _availableCategories = categories;
      _availableComplexities = complexities;
      _availableDomains = domains;
    });
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return '';
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedCategory = null;
      _selectedComplexity = null;
      _selectedImportance = null;
      _selectedDomain = null;
      _searchController.clear();
    });
  }

  void _openSaveSheet({String? initialUrl}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SavePostSheet(
        initialUrl: initialUrl,
        reminderRepository: widget.reminderRepository,
        freeTimeRepository: widget.freeTimeRepository,
        categoryStatRepository: widget.categoryStatRepository,
        notificationService: widget.notificationService,
        aiService: widget.aiService,
        onSaved: _loadReminders,
      ),
    );
  }

  void _showContextMenu(Reminder reminder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.whiteTextSecondary.withAlpha(128),
                borderRadius: BorderRadius.zero,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.schedule, color: AppColors.accent),
              ),
              title: Text(
                Translations.reschedule(_locale),
                style: TextStyle(
                  color: AppColors.whiteTextPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _rescheduleReminder(reminder);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.delete, color: AppColors.error),
              ),
              title: Text(
                Translations.delete(_locale),
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteReminder(reminder);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _rescheduleReminder(Reminder reminder) async {
    try {
      final freeTimes = widget.freeTimeRepository.getAllAsJson();
      final result = await widget.aiService.reschedulePost(
        previousAttemptsJson: '[]',
        category: reminder.categoryEn ?? 'Other',
        complexity: reminder.complexityEn ?? 'Medium',
        importance: reminder.importance,
        userFreeTimesJson: freeTimes.isNotEmpty
            ? '{"free_times": $freeTimes}'
            : null,
      );
      _showResult(true, 'Rescheduled: ${result['newTime']}');

      if (result['newTime'] != null) {
        reminder.scheduledAt = result['newTime'];
        widget.reminderRepository.save(reminder);

        await widget.notificationService.cancelReminder(reminder.id);
        await widget.notificationService.scheduleReminder(reminder);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Rescheduled to ${reminder.scheduledAt}'),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          );
          _loadReminders();
        }
      }
    } catch (e) {
      if (mounted) {
        _showResult(false, 'Error: $e');
      }
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.whiteSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          Translations.deletePost(_locale),
          style: TextStyle(color: AppColors.whiteTextPrimary),
        ),
        content: Text(
          Translations.deleteWarning(_locale),
          style: TextStyle(color: AppColors.whiteTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              Translations.cancel(_locale),
              style: TextStyle(color: AppColors.whiteTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Translations.delete(_locale),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.notificationService.cancelReminder(reminder.id);
      widget.reminderRepository.delete(reminder.id);
      _loadReminders();
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Translations.filters(_locale),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.whiteTextPrimary,
                          ),
                    ),
                    if (_hasActiveFilters)
                      TextButton(
                        onPressed: () {
                          _clearFilters();
                          Navigator.pop(context);
                        },
                        child: Text(
                          Translations.clearAll(_locale),
                          style: TextStyle(color: AppColors.whiteAccent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  Translations.category(_locale),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.whiteTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: Translations.all(_locale),
                      isSelected: _selectedCategory == null,
                      onSelected: () {
                        setModalState(() => _selectedCategory = null);
                        setState(() {});
                      },
                    ),
                    ..._availableCategories.map(
                      (cat) => _buildFilterChip(
                        label: cat,
                        isSelected: _selectedCategory == cat,
                        onSelected: () {
                          setModalState(() => _selectedCategory = cat);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  Translations.complexity(_locale),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.whiteTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: Translations.all(_locale),
                      isSelected: _selectedComplexity == null,
                      onSelected: () {
                        setModalState(() => _selectedComplexity = null);
                        setState(() {});
                      },
                    ),
                    ..._availableComplexities.map(
                      (comp) => _buildFilterChip(
                        label: LocaleManager.instance.getComplexity(
                          comp,
                          null,
                          null,
                        ),
                        isSelected: _selectedComplexity == comp,
                        onSelected: () {
                          setModalState(() => _selectedComplexity = comp);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  Translations.importance(_locale),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.whiteTextSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: Translations.all(_locale),
                      isSelected: _selectedImportance == null,
                      onSelected: () {
                        setModalState(() => _selectedImportance = null);
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceDay(_locale),
                      isSelected: _selectedImportance == 'Day',
                      onSelected: () {
                        setModalState(() => _selectedImportance = 'Day');
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceWeek(_locale),
                      isSelected: _selectedImportance == 'Week',
                      onSelected: () {
                        setModalState(() => _selectedImportance = 'Week');
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceMonth(_locale),
                      isSelected: _selectedImportance == 'Month',
                      onSelected: () {
                        setModalState(() => _selectedImportance = 'Month');
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.whiteAccent,
                      foregroundColor: AppColors.whiteBackground,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      Translations.applyFilters(_locale),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.accent.withValues(alpha: 0.2),
      checkmarkColor: AppColors.accent,
      labelStyle: TextStyle(
        color: isSelected
            ? AppColors.accent
            : AppColors.whiteTextSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      backgroundColor: AppColors.whiteSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(
          color: isSelected
              ? AppColors.whiteAccent
              : AppColors.whiteBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _isSearchVisible
            ? _buildAnimatedSearchField()
            : Row(
                children: [
                  Image.asset(
                    'assets/images/app_icon.png',
                    width: 32,
                    height: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    Translations.appName(_locale),
                    style: Theme.of(context).appBarTheme.titleTextStyle,
                  ),
                ],
              ),
        actions: [
          if (!_isSearchVisible) ...[
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                color: _hasActiveFilters
                    ? AppColors.whiteAccent
                    : AppColors.whiteTextSecondary,
              ),
              onPressed: () {
                setState(() => _isSearchVisible = true);
              },
            ),
            IconButton(
              icon: Icon(
                Icons.tune_rounded,
                color: _hasActiveFilters
                    ? AppColors.whiteAccent
                    : AppColors.whiteTextSecondary,
              ),
              onPressed: _showFilterBottomSheet,
            ),
            IconButton(
              icon: const Icon(
                Icons.settings_rounded,
                color: AppColors.whiteTextSecondary,
              ),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.whiteAccent),
              ),
            )
          : Column(
              children: [
                _buildFilterChips(),
                Expanded(child: _buildReminderList()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSaveSheet(),
        backgroundColor: AppColors.whiteAccent,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAnimatedSearchField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isSearchVisible ? null : 0,
      child: _isSearchVisible
          ? Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.whiteSurface,
                borderRadius: BorderRadius.zero,
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                style: TextStyle(color: AppColors.whiteTextPrimary),
                decoration: InputDecoration(
                  hintText: Translations.searchPosts(_locale),
                  hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.whiteTextSecondary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.whiteTextSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.whiteTextSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _isSearchVisible = false;
                            });
                          },
                        ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.whiteBackground,
        boxShadow: [
          BoxShadow(
            color: AppColors.whiteShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (_hasActiveFilters)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.zero,
                      onTap: _clearFilters,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.clear,
                              size: 16,
                              color: AppColors.error,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Translations.clearAll(_locale),
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _buildQuickFilterChip(
              label:
                  _selectedCategory ?? Translations.category(_locale),
              isActive: _selectedCategory != null,
              onTap: () => _showQuickFilterDialog('category'),
            ),
            const SizedBox(width: 10),
            _buildQuickFilterChip(
              label: _selectedComplexity ?? Translations.complexity(_locale),
              isActive: _selectedComplexity != null,
              onTap: () => _showQuickFilterDialog('complexity'),
            ),
            const SizedBox(width: 10),
            _buildQuickFilterChip(
              label: _selectedImportance ?? Translations.importance(_locale),
              isActive: _selectedImportance != null,
              onTap: () => _showQuickFilterDialog('importance'),
            ),
            if (_availableDomains.isNotEmpty) ...[
              const SizedBox(width: 10),
              _buildQuickFilterChip(
                label: _selectedDomain ?? Translations.domain(_locale),
                isActive: _selectedDomain != null,
                onTap: () => _showQuickFilterDialog('domain'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.whiteSurface,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isActive ? AppColors.whiteAccent : AppColors.whiteBorder,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? AppColors.accent
                        : AppColors.whiteTextSecondary,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: isActive
                      ? AppColors.accent
                      : AppColors.whiteTextSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickFilterDialog(String type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.whiteBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type == 'category'
                    ? Translations.category(_locale)
                    : type == 'complexity'
                        ? Translations.complexity(_locale)
                        : type == 'domain'
                            ? Translations.domain(_locale)
                            : Translations.importance(_locale),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.whiteTextPrimary,
                    ),
              ),
              const SizedBox(height: 16),
              if (type == 'category')
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      ListTile(
                        title: Text(Translations.all(_locale)),
                        leading: Radio<String?>(
                          value: null,
                          groupValue: _selectedCategory,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => _selectedCategory = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => _selectedCategory = null);
                          Navigator.pop(context);
                        },
                      ),
                      ...(_availableCategories.isNotEmpty
                              ? _availableCategories
                              : AppConstants.availableCategories)
                          .map(
                            (cat) => ListTile(
                              title: Text(cat),
                              leading: Radio<String?>(
                                value: cat,
                                groupValue: _selectedCategory,
                                activeColor: AppColors.whiteAccent,
                                onChanged: (v) {
                                  setState(() => _selectedCategory = v);
                                  Navigator.pop(context);
                                },
                              ),
                              onTap: () {
                                setState(() => _selectedCategory = cat);
                                Navigator.pop(context);
                              },
                            ),
                          ),
                    ],
                  ),
                )
              else if (type == 'complexity')
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      ListTile(
                        title: Text(Translations.all(_locale)),
                        leading: Radio<String?>(
                          value: null,
                          groupValue: _selectedComplexity,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => _selectedComplexity = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => _selectedComplexity = null);
                          Navigator.pop(context);
                        },
                      ),
                      ...(_availableComplexities.isNotEmpty
                              ? _availableComplexities
                              : ['Low', 'Medium', 'High'])
                          .map(
                            (comp) => ListTile(
                              title: Text(
                                LocaleManager.instance.getComplexity(
                                  comp,
                                  null,
                                  null,
                                ),
                              ),
                              leading: Radio<String?>(
                                value: comp,
                                groupValue: _selectedComplexity,
                                activeColor: AppColors.whiteAccent,
                                onChanged: (v) {
                                  setState(() => _selectedComplexity = v);
                                  Navigator.pop(context);
                                },
                              ),
                              onTap: () {
                                setState(() => _selectedComplexity = comp);
                                Navigator.pop(context);
                              },
                            ),
                          ),
                    ],
                  ),
                )
              else if (type == 'domain')
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      ListTile(
                        title: Text(Translations.all(_locale)),
                        leading: Radio<String?>(
                          value: null,
                          groupValue: _selectedDomain,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => _selectedDomain = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => _selectedDomain = null);
                          Navigator.pop(context);
                        },
                      ),
                      ..._availableDomains.map(
                        (domain) => ListTile(
                          title: Text(domain),
                          leading: Radio<String?>(
                            value: domain,
                            groupValue: _selectedDomain,
                            activeColor: AppColors.whiteAccent,
                            onChanged: (v) {
                              setState(() => _selectedDomain = v);
                              Navigator.pop(context);
                            },
                          ),
                          onTap: () {
                            setState(() => _selectedDomain = domain);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    ListTile(
                      title: Text(Translations.all(_locale)),
                      leading: Radio<String?>(
                        value: null,
                        groupValue: _selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => _selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => _selectedImportance = null);
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceDay(_locale)),
                      leading: Radio<String?>(
                        value: 'Day',
                        groupValue: _selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => _selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => _selectedImportance = 'Day');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceWeek(_locale)),
                      leading: Radio<String?>(
                        value: 'Week',
                        groupValue: _selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => _selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => _selectedImportance = 'Week');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceMonth(_locale)),
                      leading: Radio<String?>(
                        value: 'Month',
                        groupValue: _selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => _selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => _selectedImportance = 'Month');
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderList() {
    final reminders = _filteredReminders;

    if (reminders.isEmpty) {
      if (_hasActiveFilters) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: Translations.noResultsFound(_locale),
          subtitle: Translations.noResultsSubtitle(_locale),
        );
      }
      return EmptyState(
        icon: Icons.bookmark_add_outlined,
        title: Translations.noSavedPosts(_locale),
        subtitle: Translations.noSavedPostsSubtitle(_locale),
        onAction: () => _openSaveSheet(),
        actionLabel: Translations.savePost(_locale),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadReminders(),
      color: AppColors.whiteAccent,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 80),
        itemCount: reminders.length,
        itemBuilder: (context, index) {
          final reminder = reminders[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: GestureDetector(
              onLongPress: () => _showContextMenu(reminder),
              child: Hero(
                tag: 'reminder-${reminder.id}',
                child: ModernReminderCard(
                  reminder: reminder,
                  onTap: () => context.push('/post/${reminder.id}'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
