import 'package:flutter/material.dart';

class AppTranslations {
  static const Map<String, Map<String, String>> _translations = {
    'en': _englishStrings,
    'ar': _arabicStrings,
    'fr': _frenchStrings,
  };

  static const Map<String, String> _englishStrings = {
    // App
    'appName': 'Smart Pocket',

    // Navigation
    'navPosts': 'Posts',
    'navStats': 'Stats',
    'navFreeTime': 'Free Time',
    'navSettings': 'Settings',

    // Reminder Screen
    'noSavedPosts': 'No saved posts yet',
    'noSavedPostsSubtitle': 'Tap + to save your first post',
    'noResultsFound': 'No results found',
    'noResultsSubtitle': 'Try adjusting your filters',
    'noReadPosts': 'No read posts yet',
    'noUnopenedPosts': 'No unopened reminders',
    'noUnopenedSubtitle': 'New reminders will appear here.',
    'noOpenedPosts': 'No opened reminders',
    'noOpenedSubtitle': 'Posts you open will appear here.',
    'unreadPosts': 'Unread',
    'readPosts': 'Read',
    'unopened': 'Unopened',
    'openedTab': 'Opened',
    'markAsRead': 'Mark as read',
    'deleteSelected': 'Delete selected',
    'selectAll': 'Select all',
    'markAllAsRead': 'Mark all as read',
    'selectedCount': '{count} selected',
    'retry': 'Retry',
    'loadError': 'Failed to load',
    'clearSearch': 'Clear search',
    'sortBy': 'Sort by',
    'sortDateNewest': 'Newest first',
    'sortDateOldest': 'Oldest first',
    'sortCategory': 'By category',
    'sortImportance': 'By importance',

    // Search & Filter
    'searchPosts': 'Search posts...',
    'filters': 'Filters',
    'clearAll': 'Clear All',
    'applyFilters': 'Apply Filters',
    'category': 'Category',
    'complexity': 'Complexity',
    'importance': 'Importance',
    'domain': 'Domain',
    'all': 'All',

    // Importance Levels
    'importanceDay': 'Day',
    'importanceWeek': 'Week',
    'importanceMonth': 'Month',
    'importanceDayDesc': 'Complete within today (within 24 hours)',
    'importanceWeekDesc': 'Complete within this week (within 7 days)',
    'importanceMonthDesc': 'Complete within this month (within 30 days)',

    // Complexity Levels
    'complexityLow': 'Low',
    'complexityMedium': 'Medium',
    'complexityHigh': 'High',

    // Settings Screen
    'settings': 'Settings',
    'aiProvider': 'AI Provider',
    'selectProvider': 'Select provider',
    'apiKey': 'API Key',
    'enterApiKey': 'Enter API key...',
    'testKey': 'Test Key',
    'save': 'Save',
    'settingsSaved': 'Settings saved',
    'apiStatus': 'API Status',
    'apiConnected': 'Connected',
    'apiNotConfigured': 'Not configured',
    'language': 'Language',
    'selectLanguage': 'Select Language',

    // Statistics Screen
    'statistics': 'Statistics',
    'total': 'Total',
    'opened': 'Opened',
    'pending': 'Pending',
    'missed': 'Missed',
    'aiInsights': 'AI Insights',
    'categoryBreakdown': 'Category Breakdown',
    'noDataYet': 'No data yet',
    'analysis': 'Analysis',
    'preferredTimes': 'Preferred Times',
    'confidence': 'Confidence',
    'insights': 'Insights',

    // Post Detail Screen
    'postNotFound': 'Post not found',
    'openPost': 'Open Post',
    'reschedule': 'Reschedule',
    'delete': 'Delete',
    'deletePost': 'Delete Post?',
    'deleteWarning': 'This action cannot be undone.',
    'cancel': 'Cancel',
    'aiAnalysis': 'AI Analysis',
    'categoryLabel': 'Category',
    'complexityLabel': 'Complexity',
    'scheduledLabel': 'Scheduled',
    'statusLabel': 'Status',
    'read': 'Read',
    'unread': 'Unread',
    'scheduledFor': 'Scheduled for',

    // Edit Reminder Screen
    'editReminder': 'Edit Reminder',
    'reminder': 'Reminder',
    'schedule': 'Schedule',
    'selectDate': 'Select Date',
    'selectTime': 'Select Time',
    'aiReschedule': 'AI Reschedule',
    'aiRescheduling': 'AI Rescheduling...',
    'aiRescheduleHint':
        'AI will find the optimal time based on your free times and the selected importance.',
    'reminderUpdated': 'Reminder updated successfully',
    'scheduledTimeMustBeFuture': 'Scheduled time must be in the future',

    // Save Post Sheet
    'savePost': 'Save a Post',
    'enterUrl': 'Enter URL...',
    'whenToRemind': 'When to remind',
    'today': 'Today',
    'thisWeek': 'This Week',
    'thisMonth': 'This Month',
    'fetchingPostInfo': 'Fetching post info...',
    'classifyingContent': 'Classifying content...',
    'findingBestTime': 'Finding best time...',
    'reminderSaved': 'Reminder saved!',
    'reminderScheduledFor': 'Reminder scheduled for',

    // Free Times Screen
    'freeTimes': 'Free Times',
    'addFreeTime': 'Add Free Time',
    'timeSlotDeleted': 'Time slot deleted',
    'timeSlotAdded': 'Time slot added',
    'noFreeTimesSet': 'No free times set',
    'day': 'Day',
    'startTime': 'Start Time',
    'endTime': 'End Time',
    'endTimeMustBeAfter': 'End time must be after start time',

    // Days of Week
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',

    // Common Actions
    'edit': 'Edit',
    'deleteAction': 'Delete',
    'saveAction': 'Save',
    'cancelAction': 'Cancel',
    'clear': 'Clear',
    'rescheduleAction': 'Reschedule',
    'confirm': 'Confirm',
    'close': 'Close',
    'ok': 'OK',

// Error Messages
    'error': 'Error',
    'errorSavingPost': 'Error saving post',
    'refreshingSession': 'Refreshing session...',
    'pleaseSignInAgain': 'Please sign in again to continue',
    'errorOccurred': 'An error occurred',
    'pleaseEnterUrl': 'Please enter a URL',
    'pleaseEnterValidUrl': 'Please enter a valid URL',
    'pleaseConfigureApiKey': 'Please configure AI API key in settings',
    'aiRescheduleFailed': 'AI reschedule failed',
    'analysisFailed': 'Analysis failed',

    // Success Messages
    'success': 'Success',
    'postSaved': 'Post saved successfully',
    'reminderScheduled': 'Reminder scheduled successfully',
    'settingsSavedSuccessfully': 'Settings saved successfully',
    'analysisComplete': 'Analysis complete',

    // Context Menu
    'reschedulePost': 'Reschedule',
    'deletePostAction': 'Delete',

    // Providers
    'providerGoogle': 'Google Gemini',
    'providerOpenAI': 'OpenAI',
    'providerAnthropic': 'Anthropic',
    'providerMistral': 'Mistral',
    'providerCohere': 'Cohere',

    // Date/Time Formats
    'dateFormat': 'MMM d, yyyy',
    'timeFormat': 'h:mm a',
    'dateTimeFormat': 'EEEE, MMMM d, yyyy · h:mm a',

    // Time Display (for cards)
    'cardToday': 'Today',
    'cardTomorrow': 'Tomorrow',
    'cardOverdue': 'Overdue',
    'cardInDays': 'In {days} days',
    'cardInWeeks': 'In {weeks} weeks',
    'cardInMonths': 'In {months} months',
    'cardDaysAgo': '{days} days ago',

    // Auth / Login
    'signInTitle': 'Welcome to Smart Pocket',
    'signInSubtitle': 'Sign in to sync your reminders across devices',
    'signInWithGoogle': 'Continue with Google',
    'signInTerms': 'By continuing, you agree to our Terms of Service and Privacy Policy',
    'signInFailed': 'Sign-in failed. Please try again.',
    'signOut': 'Sign Out',
    'account': 'Account',

    // RevenueCat / Paywall
    'upgradeToPremium': 'Upgrade to Premium',
    'premiumTitle': 'Unlock All Features',
    'premiumSubtitle': 'Get unlimited access to all premium features',
    'subscribeNow': 'Subscribe Now',
    'restorePurchases': 'Restore Purchases',
    'purchaseFailed': 'Purchase failed. Please try again.',
    'premiumActivated': 'Premium activated! Enjoy!',

    // Paywall
    'choosePlan': 'Choose your plan',
    'noPackagesAvailable': 'No packages available',
    'popular': 'POPULAR',
    'premiumFeatureUnlimited': 'Unlimited reminders',
    'premiumFeatureCloudSync': 'Cloud sync across devices',
    'premiumFeaturePriorityAI': 'Priority AI scheduling',
    'premiumFeatureExcelExport': 'Export to Excel & JSON',
    'premiumFeatureAdvancedStats': 'Advanced statistics',
    'premiumFeatureNoAds': 'No ads',

    // Settings - Backup/Restore
    'exportFormat': 'Export Format',
    'json': 'JSON',
    'jsonFormatDesc': 'Plain text format, easy to edit',
    'excel': 'Excel',
    'excelFormatDesc': 'Spreadsheet format',
    'exportFailed': 'Export failed',
    'exportedSuccessfully': 'Exported successfully',
    'remindersImported': 'reminders and',
    'freeTimesImported': 'free times imported',
    'importFailed': 'Import failed',
    'signOutConfirm': 'Are you sure you want to sign out?',
    'model': 'Model',
    'backupRestore': 'Backup & Restore',
    'exportData': 'Export Data',
    'exportDataSubtitle': 'Save reminders to JSON or Excel',
    'importData': 'Import Data',
    'importDataSubtitle': 'Restore from backup file',
    'active': 'Active',
    'inactive': 'Inactive',
    'openedRate': '{count}% opened',
  };

  static const Map<String, String> _arabicStrings = {
    // App
    'appName': 'مذكرات فليكس',

    // Navigation
    'navPosts': 'المنشورات',
    'navStats': 'الإحصائيات',
    'navFreeTime': 'الوقت الحر',
    'navSettings': 'الإعدادات',

    // Reminder Screen
    'noSavedPosts': 'لا توجد منشورات محفوظة',
    'noSavedPostsSubtitle': 'اضغط على + لحفظ أول منشور',
    'noResultsFound': 'لم يتم العثور على نتائج',
    'noResultsSubtitle': 'جرب تعديل الفلاتر',
    'noReadPosts': 'لا توجد منشورات مقروءة',
    'noUnopenedPosts': 'لا توجد تذكيرات غير مفتوحة',
    'noUnopenedSubtitle': 'ستظهر التذكيرات الجديدة هنا.',
    'noOpenedPosts': 'لا توجد تذكيرات مفتوحة',
    'noOpenedSubtitle': 'ستظهر المنشورات التي تفتحها هنا.',
    'unreadPosts': 'غير مقروء',
    'readPosts': 'مقروء',
    'unopened': 'غير مفتوحة',
    'openedTab': 'مفتوحة',
    'markAsRead': 'تحديد كمقروءة',
    'deleteSelected': 'حذف المحدد',
    'selectAll': 'تحديد الكل',
    'markAllAsRead': 'تحديد الكل كمقروء',
    'selectedCount': '{count} محددة',
    'retry': 'إعادة المحاولة',
    'loadError': 'فشل تحميل البيانات',
    'clearSearch': 'مسح البحث',
    'sortBy': 'ترتيب حسب',
    'sortDateNewest': 'الأحدث أولاً',
    'sortDateOldest': 'الأقدم أولاً',
    'sortCategory': 'حسب الفئة',
    'sortImportance': 'حسب الأهمية',

    // Search & Filter
    'searchPosts': 'البحث في المنشورات...',
    'filters': 'الفلاتر',
    'clearAll': 'مسح الكل',
    'applyFilters': 'تطبيق الفلاتر',
    'category': 'الفئة',
    'complexity': 'التعقيد',
    'importance': 'الأهمية',
    'domain': 'النطاق',
    'all': 'الكل',

    // Importance Levels
    'importanceDay': 'يوم',
    'importanceWeek': 'أسبوع',
    'importanceMonth': 'شهر',
    'importanceDayDesc': 'أكمل خلال اليوم (خلال 24 ساعة)',
    'importanceWeekDesc': 'أكمل خلال هذا الأسبوع (خلال 7 أيام)',
    'importanceMonthDesc': 'أكمل خلال هذا الشهر (خلال 30 يومًا)',

    // Complexity Levels
    'complexityLow': 'بسيط',
    'complexityMedium': 'متوسط',
    'complexityHigh': 'معقد',

    // Settings Screen
    'settings': 'الإعدادات',
    'aiProvider': 'مزود الذكاء الاصطناعي',
    'selectProvider': 'اختر المزود',
    'apiKey': 'مفتاح API',
    'enterApiKey': 'أدخل مفتاح API...',
    'testKey': 'اختبار المفتاح',
    'save': 'حفظ',
    'settingsSaved': 'تم حفظ الإعدادات',
    'apiStatus': 'حالة API',
    'apiConnected': 'متصل',
    'apiNotConfigured': 'غير مكون',
    'language': 'اللغة',
    'selectLanguage': 'اختر اللغة',

    // Statistics Screen
    'statistics': 'الإحصائيات',
    'total': 'الإجمالي',
    'opened': 'مفتوح',
    'pending': 'معلق',
    'missed': 'فائت',
    'aiInsights': 'رؤى الذكاء الاصطناعي',
    'categoryBreakdown': 'تفصيل الفئات',
    'noDataYet': 'لا توجد بيانات بعد',
    'analysis': 'التحليل',
    'preferredTimes': 'الأوقات المفضلة',
    'confidence': 'الثقة',
    'insights': 'الرؤى',

    // Post Detail Screen
    'postNotFound': 'المنشور غير موجود',
    'openPost': 'فتح المنشور',
    'reschedule': 'إعادة الجدولة',
    'delete': 'حذف',
    'deletePost': 'حذف المنشور؟',
    'deleteWarning': 'لا يمكن التراجع عن هذا الإجراء.',
    'cancel': 'إلغاء',
    'aiAnalysis': 'تحليل الذكاء الاصطناعي',
    'categoryLabel': 'الفئة',
    'complexityLabel': 'التعقيد',
    'scheduledLabel': 'مجدول',
    'statusLabel': 'الحالة',
    'read': 'مقروء',
    'unread': 'غير مقروء',
    'scheduledFor': 'مجدول في',

    // Edit Reminder Screen
    'editReminder': 'تعديل التذكير',
    'reminder': 'التذكير',
    'schedule': 'الجدول',
    'selectDate': 'اختر التاريخ',
    'selectTime': 'اختر الوقت',
    'aiReschedule': 'إعادة الذكاء الاصطناعي',
    'aiRescheduling': 'جاري إعادة الجدولة...',
    'aiRescheduleHint':
        'سيجد الذكاء الاصطناعي الوقت الأمثل بناءً على أوقات فراغك والأهمية المحددة.',
    'reminderUpdated': 'تم تحديث التذكير بنجاح',
    'scheduledTimeMustBeFuture': 'يجب أن يكون وقت التذكير في المستقبل',

    // Save Post Sheet
    'savePost': 'حفظ منشور',
    'enterUrl': 'أدخل الرابط...',
    'whenToRemind': 'متى تريد التذكير',
    'today': 'اليوم',
    'thisWeek': 'هذا الأسبوع',
    'thisMonth': 'هذا الشهر',
    'fetchingPostInfo': 'جاري جلب معلومات المنشور...',
    'classifyingContent': 'جاري تصنيف المحتوى...',
    'findingBestTime': 'جاري إيجاد أفضل وقت...',
    'reminderSaved': 'تم حفظ التذكير!',
    'reminderScheduledFor': 'التذكير مجدول في',

    // Free Times Screen
    'freeTimes': 'الأوقات الحرة',
    'addFreeTime': 'إضافة وقت حر',
    'timeSlotDeleted': 'تم حذف الفترة الزمنية',
    'timeSlotAdded': 'تمت إضافة الفترة الزمنية',
    'noFreeTimesSet': 'لم يتم تعيين أوقات حرة',
    'day': 'اليوم',
    'startTime': 'وقت البدء',
    'endTime': 'وقت الانتهاء',
    'endTimeMustBeAfter': 'يجب أن يكون وقت الانتهاء بعد وقت البدء',

    // Days of Week
    'monday': 'الإثنين',
    'tuesday': 'الثلاثاء',
    'wednesday': 'الأربعاء',
    'thursday': 'الخميس',
    'friday': 'الجمعة',
    'saturday': 'السبت',
    'sunday': 'الأحد',

    // Common Actions
    'edit': 'تعديل',
    'deleteAction': 'حذف',
    'saveAction': 'حفظ',
    'cancelAction': 'إلغاء',
    'clear': 'مسح',
    'rescheduleAction': 'إعادة الجدولة',
    'confirm': 'تأكيد',
    'close': 'إغلاق',
    'ok': 'موافق',

    // Error Messages
    'error': 'خطأ',
    'errorSavingPost': 'خطأ في حفظ المنشور',
    'refreshingSession': 'جاري تحديث الجلسة...',
    'pleaseSignInAgain': 'الرجاء تسجيل الدخول مرة أخرى للمتابعة',
    'errorOccurred': 'حدث خطأ',
    'pleaseEnterUrl': 'الرجاء إدخال الرابط',
    'pleaseEnterValidUrl': 'الرجاء إدخال رابط صالح',
    'pleaseConfigureApiKey': 'الرجاء تكوين مفتاح API في الإعدادات',
    'aiRescheduleFailed': 'فشلت إعادة جدولة الذكاء الاصطناعي',
    'analysisFailed': 'فشل التحليل',

    // Success Messages
    'success': 'نجاح',
    'postSaved': 'تم حفظ المنشور بنجاح',
    'reminderScheduled': 'تم جدولة التذكير بنجاح',
    'settingsSavedSuccessfully': 'تم حفظ الإعدادات بنجاح',
    'analysisComplete': 'اكتمل التحليل',

    // Context Menu
    'reschedulePost': 'إعادة الجدولة',
    'deletePostAction': 'حذف',

    // Providers
    'providerGoogle': 'Google Gemini',
    'providerOpenAI': 'OpenAI',
    'providerAnthropic': 'Anthropic',
    'providerMistral': 'Mistral',
    'providerCohere': 'Cohere',

    // Date/Time Formats
    'dateFormat': 'd MMM, yyyy',
    'timeFormat': 'h:mm a',
    'dateTimeFormat': 'EEEE، d MMMM yyyy · h:mm a',

    // Time Display (for cards)
    'cardToday': 'اليوم',
    'cardTomorrow': 'غدًا',
    'cardOverdue': 'متأخر',
    'cardInDays': 'خلال {days} يوم',
    'cardInWeeks': 'خلال {weeks} أسبوع',
    'cardInMonths': 'خلال {months} شهر',
    'cardDaysAgo': 'منذ {days} يوم',

    // Auth / Login
    'signInTitle': 'مرحبًا بك في Smart Pocket',
    'signInSubtitle': 'سجّل الدخول لمزامنة تذكيراتك عبر الأجهزة',
    'signInWithGoogle': 'المتابعة مع Google',
    'signInTerms': 'بالمتابعة، أنت توافق على شروط الخدمة و سياسة الخصوصية',
    'signInFailed': 'فشل تسجيل الدخول. حاول مرة أخرى.',
    'signOut': 'تسجيل الخروج',
    'account': 'الحساب',

    // RevenueCat / Paywall
    'upgradeToPremium': 'الترقية إلى Premium',
    'premiumTitle': 'فتح جميع الميزات',
    'premiumSubtitle': 'احصل على وصول غير محدود لجميع الميزات المميزة',
    'subscribeNow': 'اشترك الآن',
    'restorePurchases': 'استعادة المشتريات',
    'purchaseFailed': 'فشل الشراء. حاول مرة أخرى.',
    'premiumActivated': 'تم تفعيل Premium! استمتع!',

    // Paywall
    'choosePlan': 'اختر خطتك',
    'noPackagesAvailable': 'لا حزم متاحة',
    'popular': 'شعبي',
    'premiumFeatureUnlimited': 'تذكيرات غير محدودة',
    'premiumFeatureCloudSync': 'مزامنة سحابية عبر الأجهزة',
    'premiumFeaturePriorityAI': 'جدولة ذكاء اصطناعي أولوية',
    'premiumFeatureExcelExport': 'تصدير إلى Excel و JSON',
    'premiumFeatureAdvancedStats': 'إحصائيات متقدمة',
    'premiumFeatureNoAds': 'بدون إعلانات',

    // Settings - Backup/Restore
    'exportFormat': 'تنسيق التصدير',
    'json': 'JSON',
    'jsonFormatDesc': 'تنسيق نص عادي، سهل التحرير',
    'excel': 'Excel',
    'excelFormatDesc': 'تنسيق جدول بيانات',
    'exportFailed': 'فشل التصدير',
    'exportedSuccessfully': 'تم التصدير بنجاح',
    'remindersImported': 'تذكير تم استيرادها و',
    'freeTimesImported': 'أوقات حرة تم استيرادها',
    'importFailed': 'فشل الاستيراد',
    'signOutConfirm': 'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
    'model': 'النموذج',
    'backupRestore': 'النسخ الاحتياطي واستعادته',
    'exportData': 'تصدير البيانات',
    'exportDataSubtitle': 'حفظ التذكيرات في JSON أو Excel',
    'importData': 'استيراد البيانات',
    'importDataSubtitle': 'استعادة من ملف النسخ الاحتياطي',
    'active': 'نشط',
    'inactive': 'غير نشط',
    'openedRate': '{count}% مفتوح',
  };

  static const Map<String, String> _frenchStrings = {
    // App
    'appName': 'Smart Pocket',

    // Navigation
    'navPosts': 'Publications',
    'navStats': 'Statistiques',
    'navFreeTime': 'Temps libre',
    'navSettings': 'Paramètres',

    // Reminder Screen
    'noSavedPosts': 'Aucune publication enregistrée',
    'noSavedPostsSubtitle':
        'Appuyez sur + pour enregistrer votre première publication',
    'noResultsFound': 'Aucun résultat trouvé',
    'noResultsSubtitle': 'Essayez d\'ajuster vos filtres',
    'noReadPosts': 'Aucune publication lue',
    'noUnopenedPosts': 'Aucun rappel non ouvert',
    'noUnopenedSubtitle': 'Les nouveaux rappels apparaîtront ici.',
    'noOpenedPosts': 'Aucun rappel ouvert',
    'noOpenedSubtitle': 'Les publications que vous ouvrez apparaîtront ici.',
    'unreadPosts': 'Non lu',
    'readPosts': 'Lu',
    'unopened': 'Non ouvertes',
    'openedTab': 'Ouvertes',
    'markAsRead': 'Marquer comme lu',
    'deleteSelected': 'Supprimer la sélection',
    'selectAll': 'Tout sélectionner',
    'markAllAsRead': 'Tout marquer comme lu',
    'selectedCount': '{count} sélectionnés',
    'retry': 'Réessayer',
    'loadError': 'Échec du chargement',
    'clearSearch': 'Effacer la recherche',
    'sortBy': 'Trier par',
    'sortDateNewest': 'Plus récent',
    'sortDateOldest': 'Plus ancien',
    'sortCategory': 'Par catégorie',
    'sortImportance': 'Par importance',

    // Search & Filter
    'searchPosts': 'Rechercher des publications...',
    'filters': 'Filtres',
    'clearAll': 'Tout effacer',
    'applyFilters': 'Appliquer les filtres',
    'category': 'Catégorie',
    'complexity': 'Complexité',
    'importance': 'Importance',
    'domain': 'Domaine',
    'all': 'Tous',

    // Importance Levels
    'importanceDay': 'Jour',
    'importanceWeek': 'Semaine',
    'importanceMonth': 'Mois',
    'importanceDayDesc': 'À compléter aujourd\'hui (dans les 24 heures)',
    'importanceWeekDesc': 'À compléter cette semaine (dans les 7 jours)',
    'importanceMonthDesc': 'À compléter ce mois-ci (dans les 30 jours)',

    // Complexity Levels
    'complexityLow': 'Faible',
    'complexityMedium': 'Moyen',
    'complexityHigh': 'Élevé',

    // Settings Screen
    'settings': 'Paramètres',
    'aiProvider': 'Fournisseur IA',
    'selectProvider': 'Sélectionner le fournisseur',
    'apiKey': 'Clé API',
    'enterApiKey': 'Entrer la clé API...',
    'testKey': 'Tester la clé',
    'save': 'Enregistrer',
    'settingsSaved': 'Paramètres enregistrés',
    'apiStatus': 'État de l\'API',
    'apiConnected': 'Connecté',
    'apiNotConfigured': 'Non configuré',
    'language': 'Langue',
    'selectLanguage': 'Sélectionner la langue',

    // Statistics Screen
    'statistics': 'Statistiques',
    'total': 'Total',
    'opened': 'Ouvert',
    'pending': 'En attente',
    'missed': 'Manqué',
    'aiInsights': 'Aperçus IA',
    'categoryBreakdown': 'Répartition par catégorie',
    'noDataYet': 'Pas encore de données',
    'analysis': 'Analyse',
    'preferredTimes': 'Horaires préférés',
    'confidence': 'Confiance',
    'insights': 'Aperçus',

    // Post Detail Screen
    'postNotFound': 'Publication non trouvée',
    'openPost': 'Ouvrir la publication',
    'reschedule': 'Reprogrammer',
    'delete': 'Supprimer',
    'deletePost': 'Supprimer la publication?',
    'deleteWarning': 'Cette action ne peut pas être annulée.',
    'cancel': 'Annuler',
    'aiAnalysis': 'Analyse IA',
    'categoryLabel': 'Catégorie',
    'complexityLabel': 'Complexité',
    'scheduledLabel': 'Programmé',
    'statusLabel': 'Statut',
    'read': 'Lu',
    'unread': 'Non lu',
    'scheduledFor': 'Programmé pour',

    // Edit Reminder Screen
    'editReminder': 'Modifier le rappel',
    'reminder': 'Rappel',
    'schedule': 'Programmation',
    'selectDate': 'Sélectionner la date',
    'selectTime': 'Sélectionner l\'heure',
    'aiReschedule': 'Reprogrammer avec IA',
    'aiRescheduling': 'Reprogrammation en cours...',
    'aiRescheduleHint':
        'L\'IA trouvera le moment optimal basé sur vos temps libres et l\'importance sélectionnée.',
    'reminderUpdated': 'Rappel mis à jour avec succès',
    'scheduledTimeMustBeFuture': 'L\'heure programmée doit être dans le futur',

    // Save Post Sheet
    'savePost': 'Enregistrer une publication',
    'enterUrl': 'Entrer l\'URL...',
    'whenToRemind': 'Quand rappeler',
    'today': 'Aujourd\'hui',
    'thisWeek': 'Cette semaine',
    'thisMonth': 'Ce mois',
    'fetchingPostInfo': 'Récupération des infos...',
    'classifyingContent': 'Classification du contenu...',
    'findingBestTime': 'Recherche du meilleur moment...',
    'reminderSaved': 'Rappel enregistré!',
    'reminderScheduledFor': 'Rappel programmé pour',

    // Free Times Screen
    'freeTimes': 'Temps libres',
    'addFreeTime': 'Ajouter un temps libre',
    'timeSlotDeleted': 'Créneau supprimé',
    'timeSlotAdded': 'Créneau ajouté',
    'noFreeTimesSet': 'Aucun temps libre défini',
    'day': 'Jour',
    'startTime': 'Heure de début',
    'endTime': 'Heure de fin',
    'endTimeMustBeAfter': 'L\'heure de fin doit être après l\'heure de début',

    // Days of Week
    'monday': 'Lundi',
    'tuesday': 'Mardi',
    'wednesday': 'Mercredi',
    'thursday': 'Jeudi',
    'friday': 'Vendredi',
    'saturday': 'Samedi',
    'sunday': 'Dimanche',

    // Common Actions
    'edit': 'Modifier',
    'deleteAction': 'Supprimer',
    'saveAction': 'Enregistrer',
    'cancelAction': 'Annuler',
    'clear': 'Effacer',
    'rescheduleAction': 'Reprogrammer',
    'confirm': 'Confirmer',
    'close': 'Fermer',
    'ok': 'OK',

    // Error Messages
    'error': 'Erreur',
    'errorSavingPost': 'Erreur lors de l\'enregistrement',
    'refreshingSession': 'Actualisation de la session...',
    'pleaseSignInAgain': 'Veuillez vous connecter à nouveau pour continuer',
    'errorOccurred': 'Une erreur s\'est produite',
    'pleaseEnterUrl': 'Veuillez entrer une URL',
    'pleaseEnterValidUrl': 'Veuillez entrer une URL valide',
    'pleaseConfigureApiKey':
        'Veuillez configurer la clé API dans les paramètres',
    'aiRescheduleFailed': 'La reprogrammation IA a échoué',
    'analysisFailed': 'L\'analyse a échoué',

    // Success Messages
    'success': 'Succès',
    'postSaved': 'Publication enregistrée avec succès',
    'reminderScheduled': 'Rappel programmé avec succès',
    'settingsSavedSuccessfully': 'Paramètres enregistrés avec succès',
    'analysisComplete': 'Analyse terminée',

    // Context Menu
    'reschedulePost': 'Reprogrammer',
    'deletePostAction': 'Supprimer',

    // Providers
    'providerGoogle': 'Google Gemini',
    'providerOpenAI': 'OpenAI',
    'providerAnthropic': 'Anthropic',
    'providerMistral': 'Mistral',
    'providerCohere': 'Cohere',

    // Date/Time Formats
    'dateFormat': 'd MMM yyyy',
    'timeFormat': 'HH:mm',
    'dateTimeFormat': 'EEEE d MMMM yyyy · HH:mm',

    // Time Display (for cards)
    'cardToday': 'Aujourd\'hui',
    'cardTomorrow': 'Demain',
    'cardOverdue': 'En retard',
    'cardInDays': 'Dans {days} jours',
    'cardInWeeks': 'Dans {weeks} semaines',
    'cardInMonths': 'Dans {months} mois',
    'cardDaysAgo': 'Il y a {days} jours',

    // Auth / Login
    'signInTitle': 'Bienvenue sur Smart Pocket',
    'signInSubtitle': 'Connectez-vous pour synchroniser vos rappels sur tous vos appareils',
    'signInWithGoogle': 'Continuer avec Google',
    'signInTerms': "En continuant, vous acceptez nos Conditions d'utilisation et notre Politique de confidentialité",
    'signInFailed': "Échec de la connexion. Veuillez réessayer.",
    'signOut': 'Se déconnecter',
    'account': 'Compte',

    // RevenueCat / Paywall
    'upgradeToPremium': 'Passer à Premium',
    'premiumTitle': 'Débloquez toutes les fonctionnalités',
    'premiumSubtitle': 'Accédez à toutes les fonctionnalités premium',
    'subscribeNow': "S'abonner maintenant",
    'restorePurchases': 'Restaurer les achats',
    'purchaseFailed': "L'achat a échoué. Veuillez réessayer.",
    'premiumActivated': 'Premium activé! Profitez!',

    // Paywall
    'choosePlan': 'Choisissez votre plan',
    'noPackagesAvailable': 'Aucun forfait disponible',
    'popular': 'POPULAIRE',
    'premiumFeatureUnlimited': 'Rappels illimités',
    'premiumFeatureCloudSync': 'Synchronisation cloud entre appareils',
    'premiumFeaturePriorityAI': 'Planification IA prioritaire',
    'premiumFeatureExcelExport': 'Exporter vers Excel & JSON',
    'premiumFeatureAdvancedStats': 'Statistiques avancées',
    'premiumFeatureNoAds': 'Sans publicités',

    // Settings - Backup/Restore
    'exportFormat': 'Format d\'exportation',
    'json': 'JSON',
    'jsonFormatDesc': 'Format texte brut, facile à modifier',
    'excel': 'Excel',
    'excelFormatDesc': 'Format de feuille de calcul',
    'exportFailed': 'Échec de l\'exportation',
    'exportedSuccessfully': 'Exporté avec succès',
    'remindersImported': 'rappels et',
    'freeTimesImported': 'temps libres importés',
    'importFailed': 'Échec de l\'importation',
    'signOutConfirm': 'Êtes-vous sûr de vouloir vous déconnecter?',
    'model': 'Modèle',
    'backupRestore': 'Sauvegarde et restauration',
    'exportData': 'Exporter les données',
    'exportDataSubtitle': 'Enregistrer les rappels en JSON ou Excel',
    'importData': 'Importer les données',
    'importDataSubtitle': 'Restaurer depuis un fichier de sauvegarde',
    'active': 'Actif',
    'inactive': 'Inactif',
    'openedRate': '{count}% ouvert',
  };

  static String getString(String key, {String? locale}) {
    final currentLocale = locale ?? 'en';
    final translations = _translations[currentLocale] ?? _translations['en']!;
    return translations[key] ?? _englishStrings[key] ?? key;
  }

  static Locale getLocale(String localeCode) {
    switch (localeCode) {
      case 'ar':
        return const Locale('ar');
      case 'fr':
        return const Locale('fr');
      default:
        return const Locale('en');
    }
  }

  static String getLocaleCode(Locale locale) {
    return locale.languageCode;
  }

  static List<String> get supportedLocaleCodes => ['en', 'ar', 'fr'];

  static String getLanguageName(String localeCode) {
    switch (localeCode) {
      case 'ar':
        return 'العربية';
      case 'fr':
        return 'Français';
      default:
        return 'English';
    }
  }
}
