import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

enum SortOption { dateNewest, dateOldest, category, importance }

class _TabFilterState {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';
  String? selectedCategory;
  String? selectedComplexity;
  String? selectedImportance;
  String? selectedDomain;
  SortOption sort = SortOption.dateNewest;
  final Set<int> selectedIds = {};

  bool get hasActiveFilters =>
      searchQuery.isNotEmpty ||
      selectedCategory != null ||
      selectedComplexity != null ||
      selectedImportance != null ||
      selectedDomain != null;

  bool get hasSelection => selectedIds.isNotEmpty;

  void clearFilters() {
    searchQuery = '';
    searchController.clear();
    selectedCategory = null;
    selectedComplexity = null;
    selectedImportance = null;
    selectedDomain = null;
  }

  void dispose() {
    searchController.dispose();
  }
}

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

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _unopenedTab = _TabFilterState();
  final _openedTab = _TabFilterState();

  List<String> _availableCategories = [];
  List<String> _availableComplexities = [];
  List<String> _availableDomains = [];

  List<Reminder> _openedReminders = [];
  List<Reminder> _unopenedReminders = [];

  bool _isReady = false;
  int _initialTabIndex = 0;

  bool _isSearchVisible = false;
  bool _isSelectionMode = false;

  bool _refreshingUnopened = false;
  bool _refreshingOpened = false;
  String? _unopenedError;
  String? _openedError;

  static const String _prefsTabIndex = 'reminders_tab_index';
  static const int _tabCount = 2;

  String get _locale => LocaleManager.instance.getLocale();

  _TabFilterState get _currentTab =>
      _tabController.index == 0 ? _unopenedTab : _openedTab;

  List<Reminder> get _currentSource =>
      _tabController.index == 0 ? _unopenedReminders : _openedReminders;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: 0,
    );
    _tabController.addListener(_onTabChanged);
    widget.pendingSharedUrl.addListener(_onPendingSharedUrlChanged);
    LocaleManager.instance.localeNotifier.addListener(_onLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAiRescheduleErrorIfNeeded();
    });
    _initialize();
  }

  Future<void> _initialize() async {
    int saved = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getInt(_prefsTabIndex) ?? 0;
    } catch (_) {
      saved = 0;
    }
    if (saved < 0 || saved >= _tabCount) saved = 0;
    _initialTabIndex = saved;
    if (mounted && _tabController.index != _initialTabIndex) {
      _tabController.index = _initialTabIndex;
    }
    _loadInitialData();
    if (mounted) setState(() => _isReady = true);
  }

  @override
  void dispose() {
    widget.pendingSharedUrl.removeListener(_onPendingSharedUrlChanged);
    LocaleManager.instance.localeNotifier.removeListener(_onLocaleChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _unopenedTab.dispose();
    _openedTab.dispose();
    super.dispose();
  }

  Future<void> _saveTabIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsTabIndex, index);
    } catch (_) {
      // Ignore persistence failures; non-critical.
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final index = _tabController.index;
      _saveTabIndex(index);
      _clearSelection();
      if (mounted) setState(() {});
    }
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

  List<Reminder> _applyFiltersAndSort(
    List<Reminder> source,
    _TabFilterState tab,
  ) {
    final query = tab.searchQuery.toLowerCase();
    final result = source.where((reminder) {
      if (tab.searchQuery.isNotEmpty) {
        final titleMatch = reminder.title.toLowerCase().contains(query);
        final descMatch =
            reminder.description?.toLowerCase().contains(query) ?? false;
        if (!titleMatch && !descMatch) return false;
      }
      if (tab.selectedCategory != null &&
          reminder.categoryEn != tab.selectedCategory) {
        return false;
      }
      if (tab.selectedComplexity != null &&
          reminder.complexityEn != tab.selectedComplexity) {
        return false;
      }
      if (tab.selectedImportance != null &&
          reminder.importance != tab.selectedImportance) {
        return false;
      }
      if (tab.selectedDomain != null &&
          _extractDomain(reminder.url) != tab.selectedDomain) {
        return false;
      }
      return true;
    }).toList();

    switch (tab.sort) {
      case SortOption.dateNewest:
        result.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
        break;
      case SortOption.dateOldest:
        result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        break;
      case SortOption.category:
        result.sort(
          (a, b) => (a.categoryEn ?? '').compareTo(b.categoryEn ?? ''),
        );
        break;
      case SortOption.importance:
        const order = {'Day': 0, 'Week': 1, 'Month': 2};
        result.sort(
          (a, b) =>
              (order[a.importance] ?? 99).compareTo(order[b.importance] ?? 99),
        );
        break;
    }
    return result;
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

  void _loadInitialData() {
    try {
      _unopenedReminders = widget.reminderRepository.getUnread();
      _openedReminders = widget.reminderRepository.getRead();
      _unopenedError = null;
      _openedError = null;
      _loadFilterOptions();
    } catch (e) {
      _unopenedError = e.toString();
      _openedError = e.toString();
    }
  }

  Future<void> _refreshTab(bool isOpened) async {
    final refreshing =
        isOpened ? _refreshingOpened : _refreshingUnopened;
    if (refreshing) return;
    if (isOpened) {
      _refreshingOpened = true;
    } else {
      _refreshingUnopened = true;
    }
    if (mounted) setState(() {});
    try {
      if (isOpened) {
        _openedReminders = widget.reminderRepository.getRead();
        _openedError = null;
      } else {
        _unopenedReminders = widget.reminderRepository.getUnread();
        _unopenedError = null;
      }
      _loadFilterOptions();
    } catch (e) {
      if (isOpened) {
        _openedError = e.toString();
      } else {
        _unopenedError = e.toString();
      }
    } finally {
      if (isOpened) {
        _refreshingOpened = false;
      } else {
        _refreshingUnopened = false;
      }
      if (mounted) setState(() {});
    }
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
        onSaved: () => _loadRemindersAndSync(),
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
          _loadRemindersAndSync();
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
      _loadRemindersAndSync();
    }
  }

  void _loadRemindersAndSync() {
    _loadInitialData();
    if (mounted) setState(() {});
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _clearSelection();
    });
  }

  void _enterSelection(Reminder reminder, bool isOpened) {
    setState(() {
      _isSelectionMode = true;
      final selectedIds =
          isOpened ? _openedTab.selectedIds : _unopenedTab.selectedIds;
      selectedIds.add(reminder.id);
    });
  }

  void _clearSelection() {
    setState(() {
      _unopenedTab.selectedIds.clear();
      _openedTab.selectedIds.clear();
    });
  }

  void _toggleReminderSelection(int id, bool isOpened) {
    setState(() {
      final selectedIds =
          isOpened ? _openedTab.selectedIds : _unopenedTab.selectedIds;
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    final tab = _currentTab;
    final source = _applyFiltersAndSort(_currentSource, tab);
    setState(() {
      tab.selectedIds
        ..clear()
        ..addAll(source.map((r) => r.id));
    });
  }

  Future<void> _markSelectedAsRead() async {
    final ids = List<int>.from(_currentTab.selectedIds);
    if (ids.isEmpty) return;
    try {
      for (final id in ids) {
        final reminder = widget.reminderRepository.getById(id);
        if (reminder != null && !reminder.isOpened) {
          reminder.isOpened = true;
          reminder.openedAt = DateTime.now();
          widget.reminderRepository.save(reminder);
          widget.categoryStatRepository.recordOpened(reminder);
        }
      }
      _clearSelection();
      _loadRemindersAndSync();
      if (mounted) _showResult(true, Translations.markAsRead(_locale));
    } catch (e) {
      if (mounted) _showResult(false, 'Error: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      for (final reminder in _currentSource) {
        if (!reminder.isOpened) {
          reminder.isOpened = true;
          reminder.openedAt = DateTime.now();
          widget.reminderRepository.save(reminder);
          widget.categoryStatRepository.recordOpened(reminder);
        }
      }
      _clearSelection();
      _loadRemindersAndSync();
      if (mounted) _showResult(true, Translations.markAllAsRead(_locale));
    } catch (e) {
      if (mounted) _showResult(false, 'Error: $e');
    }
  }

  Future<void> _deleteSelected() async {
    final ids = List<int>.from(_currentTab.selectedIds);
    if (ids.isEmpty) return;
    try {
      for (final id in ids) {
        await widget.notificationService.cancelReminder(id);
        widget.reminderRepository.delete(id);
      }
      _clearSelection();
      _loadRemindersAndSync();
      if (mounted) _showResult(true, Translations.deleteSelected(_locale));
    } catch (e) {
      if (mounted) _showResult(false, 'Error: $e');
    }
  }

  void _showFilterBottomSheet() {
    final tab = _currentTab;
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
                    if (tab.hasActiveFilters)
                      TextButton(
                        onPressed: () {
                          setState(() => tab.clearFilters());
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
                      isSelected: tab.selectedCategory == null,
                      onSelected: () {
                        setModalState(() => tab.selectedCategory = null);
                        setState(() {});
                      },
                    ),
                    ..._availableCategories.map(
                      (cat) => _buildFilterChip(
                        label: cat,
                        isSelected: tab.selectedCategory == cat,
                        onSelected: () {
                          setModalState(() => tab.selectedCategory = cat);
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
                      isSelected: tab.selectedComplexity == null,
                      onSelected: () {
                        setModalState(() => tab.selectedComplexity = null);
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
                        isSelected: tab.selectedComplexity == comp,
                        onSelected: () {
                          setModalState(() => tab.selectedComplexity = comp);
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
                      isSelected: tab.selectedImportance == null,
                      onSelected: () {
                        setModalState(() => tab.selectedImportance = null);
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceDay(_locale),
                      isSelected: tab.selectedImportance == 'Day',
                      onSelected: () {
                        setModalState(() => tab.selectedImportance = 'Day');
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceWeek(_locale),
                      isSelected: tab.selectedImportance == 'Week',
                      onSelected: () {
                        setModalState(() => tab.selectedImportance = 'Week');
                        setState(() {});
                      },
                    ),
                    _buildFilterChip(
                      label: Translations.importanceMonth(_locale),
                      isSelected: tab.selectedImportance == 'Month',
                      onSelected: () {
                        setModalState(() => tab.selectedImportance = 'Month');
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: AppColors.whiteBackground,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.whiteAccent),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _isSearchVisible
            ? _buildAnimatedSearchField()
            : _isSelectionMode
                ? Text(
                    Translations.selectedCount(
                      _locale,
                      _currentTab.selectedIds.length,
                    ),
                    style: Theme.of(context).appBarTheme.titleTextStyle,
                  )
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
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.whiteTextSecondary),
              onPressed: _toggleSelectionMode,
              tooltip: Translations.cancel(_locale),
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                color: _currentTab.hasActiveFilters
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
                color: _currentTab.hasActiveFilters
                    ? AppColors.whiteAccent
                    : AppColors.whiteTextSecondary,
              ),
              onPressed: _showFilterBottomSheet,
            ),
            IconButton(
              icon: const Icon(
                Icons.checklist_rounded,
                color: AppColors.whiteTextSecondary,
              ),
              onPressed: _toggleSelectionMode,
              tooltip: Translations.selectAll(_locale),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.whiteAccent,
          labelColor: AppColors.whiteTextPrimary,
          unselectedLabelColor: AppColors.whiteTextSecondary,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      Translations.unopened(_locale),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildCountBadge(_unopenedReminders.length),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      Translations.openedTab(_locale),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildCountBadge(_openedReminders.length),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(isOpened: false),
                _buildTabContent(isOpened: true),
              ],
            ),
          ),
          if (_isSelectionMode) _buildBatchActionBar(),
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

  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.whiteTextSecondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.zero,
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: AppColors.whiteTextSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBatchActionBar() {
    final tab = _currentTab;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.whiteSurface,
        border: Border(
          top: BorderSide(color: AppColors.whiteBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.whiteShadow,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                Translations.selectedCount(_locale, tab.selectedIds.length),
                style: TextStyle(
                  color: AppColors.whiteTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.select_all, color: AppColors.whiteAccent),
              onPressed: _selectAll,
              tooltip: Translations.selectAll(_locale),
            ),
            IconButton(
              icon: const Icon(Icons.check_circle, color: AppColors.accent),
              onPressed: tab.hasSelection ? _markSelectedAsRead : null,
              tooltip: Translations.markAsRead(_locale),
            ),
            IconButton(
              icon: const Icon(Icons.done_all, color: AppColors.accent),
              onPressed: _markAllAsRead,
              tooltip: Translations.markAllAsRead(_locale),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: tab.hasSelection ? _deleteSelected : null,
              tooltip: Translations.deleteSelected(_locale),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedSearchField() {
    final tab = _currentTab;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _isSearchVisible ? null : 0,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.whiteSurface,
          borderRadius: BorderRadius.zero,
        ),
        child: TextField(
          controller: tab.searchController,
          autofocus: true,
          onChanged: (value) {
            setState(() => tab.searchQuery = value);
          },
          style: TextStyle(color: AppColors.whiteTextPrimary),
          decoration: InputDecoration(
            hintText: Translations.searchPosts(_locale),
            hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.whiteTextSecondary,
            ),
            suffixIcon: tab.searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: AppColors.whiteTextSecondary,
                    ),
                    onPressed: () {
                      tab.clearFilters();
                      setState(() {});
                    },
                  )
                : IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.whiteTextSecondary,
                    ),
                    onPressed: () {
                      tab.clearFilters();
                      setState(() => _isSearchVisible = false);
                    },
                  ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent({required bool isOpened}) {
    final tab = isOpened ? _openedTab : _unopenedTab;
    final source = isOpened ? _openedReminders : _unopenedReminders;
    final error = isOpened ? _openedError : _unopenedError;
    final reminders = _applyFiltersAndSort(source, tab);

    return RefreshIndicator(
      onRefresh: () => _refreshTab(isOpened),
      color: AppColors.whiteAccent,
      child: error != null
          ? _buildTabErrorState(error, isOpened)
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildTabFilterChips(tab, isOpened)),
                SliverToBoxAdapter(child: _buildSortControl(tab, isOpened)),
                if (reminders.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(isOpened, tab),
                  )
                else
                  _buildReminderList(reminders, isOpened, tab),
              ],
            ),
    );
  }

  Widget _buildTabErrorState(String error, bool isOpened) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Translations.loadError(_locale),
                    style: TextStyle(
                      color: AppColors.whiteTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: AppColors.whiteTextSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _refreshTab(isOpened),
                    icon: const Icon(Icons.refresh),
                    label: Text(Translations.retry(_locale)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.whiteAccent,
                      foregroundColor: AppColors.whiteBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabFilterChips(_TabFilterState tab, bool isOpened) {
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
            if (tab.hasActiveFilters)
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
                      onTap: () {
                        setState(() => tab.clearFilters());
                      },
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
              label: tab.selectedCategory ?? Translations.category(_locale),
              isActive: tab.selectedCategory != null,
              onTap: () => _showQuickFilterDialog('category', tab),
            ),
            const SizedBox(width: 10),
            _buildQuickFilterChip(
              label: tab.selectedComplexity ?? Translations.complexity(_locale),
              isActive: tab.selectedComplexity != null,
              onTap: () => _showQuickFilterDialog('complexity', tab),
            ),
            const SizedBox(width: 10),
            _buildQuickFilterChip(
              label: tab.selectedImportance ?? Translations.importance(_locale),
              isActive: tab.selectedImportance != null,
              onTap: () => _showQuickFilterDialog('importance', tab),
            ),
            if (_availableDomains.isNotEmpty) ...[
              const SizedBox(width: 10),
              _buildQuickFilterChip(
                label: tab.selectedDomain ?? Translations.domain(_locale),
                isActive: tab.selectedDomain != null,
                onTap: () => _showQuickFilterDialog('domain', tab),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSortControl(_TabFilterState tab, bool isOpened) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.sort,
            size: 18,
            color: AppColors.whiteTextSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            Translations.sortBy(_locale),
            style: TextStyle(
              color: AppColors.whiteTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<SortOption>(
            value: tab.sort,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.whiteSurface,
            iconEnabledColor: AppColors.whiteTextSecondary,
            style: TextStyle(
              color: AppColors.whiteTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: [
              DropdownMenuItem(
                value: SortOption.dateNewest,
                child: Text(Translations.sortDateNewest(_locale)),
              ),
              DropdownMenuItem(
                value: SortOption.dateOldest,
                child: Text(Translations.sortDateOldest(_locale)),
              ),
              DropdownMenuItem(
                value: SortOption.category,
                child: Text(Translations.sortCategory(_locale)),
              ),
              DropdownMenuItem(
                value: SortOption.importance,
                child: Text(Translations.sortImportance(_locale)),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => tab.sort = value);
            },
          ),
        ],
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
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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

  void _showQuickFilterDialog(String type, _TabFilterState tab) {
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
                          groupValue: tab.selectedCategory,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => tab.selectedCategory = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => tab.selectedCategory = null);
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
                                groupValue: tab.selectedCategory,
                                activeColor: AppColors.whiteAccent,
                                onChanged: (v) {
                                  setState(() => tab.selectedCategory = v);
                                  Navigator.pop(context);
                                },
                              ),
                              onTap: () {
                                setState(() => tab.selectedCategory = cat);
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
                          groupValue: tab.selectedComplexity,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => tab.selectedComplexity = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => tab.selectedComplexity = null);
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
                                groupValue: tab.selectedComplexity,
                                activeColor: AppColors.whiteAccent,
                                onChanged: (v) {
                                  setState(() => tab.selectedComplexity = v);
                                  Navigator.pop(context);
                                },
                              ),
                              onTap: () {
                                setState(() => tab.selectedComplexity = comp);
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
                          groupValue: tab.selectedDomain,
                          activeColor: AppColors.whiteAccent,
                          onChanged: (v) {
                            setState(() => tab.selectedDomain = v);
                            Navigator.pop(context);
                          },
                        ),
                        onTap: () {
                          setState(() => tab.selectedDomain = null);
                          Navigator.pop(context);
                        },
                      ),
                      ..._availableDomains.map(
                        (domain) => ListTile(
                          title: Text(domain),
                          leading: Radio<String?>(
                            value: domain,
                            groupValue: tab.selectedDomain,
                            activeColor: AppColors.whiteAccent,
                            onChanged: (v) {
                              setState(() => tab.selectedDomain = v);
                              Navigator.pop(context);
                            },
                          ),
                          onTap: () {
                            setState(() => tab.selectedDomain = domain);
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
                        groupValue: tab.selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => tab.selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => tab.selectedImportance = null);
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceDay(_locale)),
                      leading: Radio<String?>(
                        value: 'Day',
                        groupValue: tab.selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => tab.selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => tab.selectedImportance = 'Day');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceWeek(_locale)),
                      leading: Radio<String?>(
                        value: 'Week',
                        groupValue: tab.selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => tab.selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => tab.selectedImportance = 'Week');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: Text(Translations.importanceMonth(_locale)),
                      leading: Radio<String?>(
                        value: 'Month',
                        groupValue: tab.selectedImportance,
                        activeColor: AppColors.whiteAccent,
                        onChanged: (v) {
                          setState(() => tab.selectedImportance = v);
                          Navigator.pop(context);
                        },
                      ),
                      onTap: () {
                        setState(() => tab.selectedImportance = 'Month');
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

  Widget _buildEmptyState(bool isOpened, _TabFilterState tab) {
    if (tab.hasActiveFilters) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: Translations.noResultsFound(_locale),
        subtitle: Translations.noResultsSubtitle(_locale),
        onAction: () => setState(() => tab.clearFilters()),
        actionLabel: Translations.clearSearch(_locale),
      );
    }
    if (isOpened) {
      return EmptyState(
        icon: Icons.visibility_outlined,
        title: Translations.noOpenedPosts(_locale),
        subtitle: Translations.noOpenedSubtitle(_locale),
      );
    }
    return EmptyState(
      icon: Icons.bookmark_add_outlined,
      title: Translations.noUnopenedPosts(_locale),
      subtitle: Translations.noUnopenedSubtitle(_locale),
      onAction: () => _openSaveSheet(),
      actionLabel: Translations.savePost(_locale),
    );
  }

  Widget _buildReminderList(
    List<Reminder> reminders,
    bool isOpened,
    _TabFilterState tab,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final reminder = reminders[index];
          final isSelected = tab.selectedIds.contains(reminder.id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ModernReminderCard(
              reminder: reminder,
              inSelectionMode: _isSelectionMode,
              isSelected: isSelected,
              onSelectionToggle: () =>
                  _toggleReminderSelection(reminder.id, isOpened),
              onTap: _isSelectionMode
                  ? null
                  : () => context.push('/post/${reminder.id}'),
              onLongPress: _isSelectionMode
                  ? null
                  : () => _enterSelection(reminder, isOpened),
            ),
          );
        },
        childCount: reminders.length,
      ),
    );
  }
}
