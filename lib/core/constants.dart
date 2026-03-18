class AppConstants {
  static const String appName = 'Flex Reminder';
  static const String aiProviderKey = 'ai_provider';
  static const String aiApiKeyKey = 'ai_api_key';
  static const String defaultProvider = 'google';

  static const List<String> availableCategories = [
    'Productivity',
    'Technology',
    'Business',
    'Finance',
    'Health',
    'Fitness',
    'Science',
    'Education',
    'Entertainment',
    'News',
    'Sports',
    'Lifestyle',
    'Travel',
    'Food',
    'Art',
    'Music',
    'Books',
    'Gaming',
    'Social',
    'Other',
  ];

  static const Map<String, String> categoryTranslations = {
    'Productivity': 'إنتاجية',
    'Technology': 'تكنولوجيا',
    'Business': 'أعمال',
    'Finance': 'مالية',
    'Health': 'صحة',
    'Fitness': 'لياقة',
    'Science': 'علم',
    'Education': 'تعليم',
    'Entertainment': 'ترفيه',
    'News': 'أخبار',
    'Sports': 'رياضة',
    'Lifestyle': 'أسلوب حياة',
    'Travel': 'سفر',
    'Food': 'طعام',
    'Art': 'فن',
    'Music': 'موسيقى',
    'Books': 'كتب',
    'Gaming': 'ألعاب',
    'Social': 'اجتماعي',
    'Other': 'أخرى',
  };

  static const Map<String, String> complexityTranslations = {
    'Low': 'بسيط',
    'Medium': 'متوسط',
    'High': 'معقد',
  };
}
