import 'package:flutter/material.dart';

class AppTranslations {
  static const Map<String, Map<String, String>> _translations = {
    'en': _englishStrings,
    'ar': _arabicStrings,
    'fr': _frenchStrings,
  };

  static const Map<String, String> _englishStrings = {
    // App
    'appName': 'Flex Reminder',

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
    'unreadPosts': 'Unread',
    'readPosts': 'Read',

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
    'unreadPosts': 'غير مقروء',
    'readPosts': 'مقروء',

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
  };

  static const Map<String, String> _frenchStrings = {
    // App
    'appName': 'Flex Reminder',

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
    'unreadPosts': 'Non lu',
    'readPosts': 'Lu',

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
