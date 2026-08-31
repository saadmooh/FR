# Reminders Screen - Tabbed Interface Implementation Plan

## Goal
Transform the current single-list `RemindersScreen` into a tabbed interface with two swipeable tabs:
- **Opened** (المفتوحة) - reminders with `isOpened == true`
- **Unopened** (التي لم تفتح) - reminders with `isOpened == false`

Using `TabBar` + `TabBarView` with all advanced features.

## Current Architecture Analysis
- `RemindersScreen` loads all reminders (`_allReminders = [...unread, ...read]`)
- Filters applied via `_filteredReminders` getter
- Single `ListView` with `ModernReminderCard`
- Search, category, complexity, importance, domain filters
- Context menu for reschedule/delete

## Implementation Plan

### 1. State Structure Changes
**New state variables:**
```dart
// Tab controller
late TabController _tabController;

// Per-tab data
List<Reminder> _openedReminders = [];
List<Reminder> _unopenedReminders = [];

// Per-tab filters
String _openedSearchQuery = '';
String _unopenedSearchQuery = '';
String? _openedSelectedCategory;
String? _unopenedSelectedCategory;
// ... similarly for complexity, importance, domain

// Per-tab sort
enum SortOption { dateNewest, dateOldest, category, importance }
SortOption _openedSort = SortOption.dateNewest;
SortOption _unopenedSort = SortOption.dateNewest;

// Batch selection
Set<int> _openedSelectedIds = {};
Set<int> _unopenedSelectedIds = {};
bool _isSelectionMode = false;

// Persistence
static const String _prefsTabIndex = 'reminders_tab_index';
```

### 2. TabController Setup
```dart
@override
void initState() {
  super.initState();
  _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: _getSavedTabIndex(),
  );
  _tabController.addListener(_onTabChanged);
  _loadReminders();
}

int _getSavedTabIndex() {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_prefsTabIndex) ?? 0; // 0 = Unopened, 1 = Opened
}

void _onTabChanged() {
  if (!_tabController.indexIsChanging) {
    _saveTabIndex(_tabController.index);
    _clearSelection();
  }
}
```

### 3. Data Loading - Split by Status
```dart
void _loadReminders() {
  final unread = widget.reminderRepository.getUnread();
  final read = widget.reminderRepository.getRead();
  
  setState(() {
    _unopenedReminders = unread;
    _openedReminders = read;
    _isLoading = false;
  });
  _loadFilterOptions();
}
```

### 4. Filter Options - Global (from all reminders)
```dart
void _loadFilterOptions() {
  final allReminders = widget.reminderRepository.getAll();
  // ... existing logic for categories, complexities, domains
}
```

### 5. Per-Tab Filtered & Sorted Lists
```dart
List<Reminder> get _filteredOpenedReminders => 
    _applyFiltersAndSort(_openedReminders, _openedSearchQuery, 
        _openedSelectedCategory, _openedSelectedComplexity, 
        _openedSelectedImportance, _openedSelectedDomain, _openedSort);

List<Reminder> get _filteredUnopenedReminders => 
    _applyFiltersAndSort(_unopenedReminders, _unopenedSearchQuery, 
        _unopenedSelectedCategory, _unopenedSelectedComplexity, 
        _unopenedSelectedImportance, _unopenedSelectedDomain, _unopenedSort);

List<Reminder> _applyFiltersAndSort(
  List<Reminder> source,
  String searchQuery,
  String? category,
  String? complexity,
  String? importance,
  String? domain,
  SortOption sort,
) {
  var result = source.where((r) {
    // ... existing filter logic
  }).toList();
  
  // Apply sort
  switch (sort) {
    case SortOption.dateNewest:
      result.sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      break;
    case SortOption.dateOldest:
      result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      break;
    case SortOption.category:
      result.sort((a, b) => (a.categoryEn ?? '').compareTo(b.categoryEn ?? ''));
      break;
    case SortOption.importance:
      const order = {'Day': 0, 'Week': 1, 'Month': 2};
      result.sort((a, b) => (order[a.importance] ?? 99).compareTo(order[b.importance] ?? 99));
      break;
  }
  return result;
}
```

### 6. Build Method - TabBar + TabBarView
```dart
@override
Widget build(BuildContext context) {
  return DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        // ... existing appBar
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Translations.unopened(_locale)),
                  const SizedBox(width: 8),
                  _buildCountBadge(_filteredUnopenedReminders.length),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Translations.opened(_locale)),
                  const SizedBox(width: 8),
                  _buildCountBadge(_filteredOpenedReminders.length),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabContent(isOpened: false),
          _buildTabContent(isOpened: true),
        ],
      ),
    ),
  );
}
```

### 7. Per-Tab Content with Pull-to-Refresh
```dart
Widget _buildTabContent({required bool isOpened}) {
  final reminders = isOpened ? _filteredOpenedReminders : _filteredUnopenedReminders;
  final searchQuery = isOpened ? _openedSearchQuery : _unopenedSearchQuery;
  final onSearchChanged = isOpened 
      ? (v) => setState(() => _openedSearchQuery = v)
      : (v) => setState(() => _unopenedSearchQuery = v);
  // ... similarly for other filters
  
  return RefreshIndicator(
    onRefresh: () async => _loadReminders(),
    color: AppColors.whiteAccent,
    child: CustomScrollView(
      slivers: [
        // Search bar
        SliverToBoxAdapter(child: _buildSearchField(searchQuery, onSearchChanged)),
        // Sort dropdown
        SliverToBoxAdapter(child: _buildSortDropdown(isOpened)),
        // Filter chips
        SliverToBoxAdapter(child: _buildQuickFilterChips(isOpened)),
        // List or Empty State
        reminders.isEmpty
            ? SliverFillRemaining(child: _buildEmptyState(isOpened))
            : _buildReminderList(reminders, isOpened),
      ],
    ),
  );
}
```

### 8. Batch Actions
```dart
void _toggleSelectionMode() {
  setState(() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) _clearSelection();
  });
}

void _clearSelection() {
  setState(() {
    _openedSelectedIds.clear();
    _unopenedSelectedIds.clear();
  });
}

void _toggleReminderSelection(int id, bool isOpened) {
  setState(() {
    if (isOpened) {
      _openedSelectedIds.contains(id) 
          ? _openedSelectedIds.remove(id) 
          : _openedSelectedIds.add(id);
    } else {
      _unopenedSelectedIds.contains(id) 
          ? _unopenedSelectedIds.remove(id) 
          : _unopenedSelectedIds.add(id);
    }
  });
}

Future<void> _markSelectedAsRead() async {
  final ids = _tabController.index == 0 ? _unopenedSelectedIds : _openedSelectedIds;
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
  _loadReminders();
}

Future<void> _deleteSelected() async {
  final ids = _tabController.index == 0 ? _unopenedSelectedIds : _openedSelectedIds;
  for (final id in ids) {
    await widget.notificationService.cancelReminder(id);
    widget.reminderRepository.delete(id);
  }
  _clearSelection();
  _loadReminders();
}
```

### 9. Updated Reminder List with Selection
```dart
Widget _buildReminderList(List<Reminder> reminders, bool isOpened) {
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final reminder = reminders[index];
        final isSelected = isOpened 
            ? _openedSelectedIds.contains(reminder.id)
            : _unopenedSelectedIds.contains(reminder.id);
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: GestureDetector(
            onLongPress: () => _isSelectionMode 
                ? null 
                : _showContextMenu(reminder),
            onTap: _isSelectionMode 
                ? () => _toggleReminderSelection(reminder.id, isOpened)
                : () => context.push('/post/${reminder.id}'),
            child: Hero(
              tag: 'reminder-${reminder.id}',
              child: ModernReminderCard(
                reminder: reminder,
                onTap: () {},
                isSelected: isSelected, // NEW: pass selection state
              ),
            ),
          ),
        );
      },
      childCount: reminders.length,
    ),
  );
}
```

### 10. ModernReminderCard - Add Selection Support
```dart
// Add to ModernReminderCard
final bool isSelected;
final VoidCallback? onSelectionToggle;

// In build, show checkbox when in selection mode
if (widget.isSelected) {
  // Show checkmark overlay or change border
}
```

### 11. AppBar Actions - Dynamic Based on Mode
```dart
actions: [
  if (_isSelectionMode) ...[
    IconButton(
      icon: const Icon(Icons.check_circle),
      onPressed: _markSelectedAsRead,
    ),
    IconButton(
      icon: const Icon(Icons.delete),
      onPressed: _deleteSelected,
    ),
    IconButton(
      icon: const Icon(Icons.close),
      onPressed: _toggleSelectionMode,
    ),
  ] else ...[
    // Existing: search, filter, settings
  ],
],
```

### 12. Translation Keys Needed
Add to `app_translations.dart`:
- `unopened`: "غير مفتوحة" / "Unopened" / "Non ouvertes"
- `opened`: "مفتوحة" / "Opened" / "Ouvertes"
- `markAsRead`: "تحديد كمقروءة" / "Mark as read" / "Marquer comme lu"
- `deleteSelected`: "حذف المحدد" / "Delete selected" / "Supprimer la sélection"
- `selectAll`: "تحديد الكل" / "Select all" / "Tout sélectionner"
- `sortBy`: "ترتيب حسب" / "Sort by" / "Trier par"
- `sortDateNewest`: "الأحدث أولاً" / "Newest first" / "Plus récent"
- `sortDateOldest`: "الأقدم أولاً" / "Oldest first" / "Plus ancien"
- `sortCategory`: "حسب الفئة" / "By category" / "Par catégorie"
- `sortImportance`: "حسب الأهمية" / "By importance" / "Par importance"

## Files to Modify
1. `lib/screens/reminders_screen.dart` - Major rewrite
2. `lib/widgets/modern_reminder_card.dart` - Add selection support
3. `lib/core/translations.dart` - Add new keys
4. `lib/core/app_translations.dart` - Add translations for all locales

## Validation
- `flutter analyze` - no errors
- Test tab switching preserves scroll position
- Test search/filter/sort work independently per tab
- Test batch select → mark read → move to opened tab
- Test batch select → delete
- Test tab persistence across app restart
- Test empty states show correct message per tab
- Test pull-to-refresh works on each tab

## Risks
- `TabController` needs `TickerProviderStateMixin` - add `with SingleTickerProviderStateMixin`
- `Hero` animations may conflict between tabs - use unique tags per tab
- Large lists: consider `ListView.builder` with `AutomaticKeepAliveClientMixin`
- Filter state reset when switching tabs - maintain separate filter state per tab