class AppConstants {
  static const String appName = 'Smart Pocket';
  static const String premiumEntitlementId = 'pro';
  static const String aiProviderKey = 'ai_provider';
  static const String aiApiKeyKey = 'ai_api_key';
  static const String defaultProvider = 'google';

  static const Map<String, List<String>> availableModels = {
    'google': [
      'gemini-flash-latest',
      'gemini-2.0-flash',
      'gemini-2.5-flash',
      'gemini-2.5-pro',
    ],
    'openai': [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-3.5-turbo',
    ],
    'anthropic': [
      'claude-sonnet-4-20250514',
      'claude-opus-4-20250514',
      'claude-3-5-sonnet-20241022',
      'claude-3-haiku-20240307',
    ],
    'mistral': [
      'mistral-large-latest',
      'mistral-small-latest',
      'codestral-latest',
    ],
    'cohere': [
      'command-r-plus',
      'command-r',
      'command-light',
    ],
    'openrouter': [
      'google/gemma-4-31b-it:free',
      'google/gemma-4-31b-it',
      'google/gemini-2.5-flash',
      'meta-llama/llama-3.3-70b-instruct',
      'anthropic/claude-3.5-sonnet',
      'openai/gpt-4o',
      'mistralai/mistral-large',
    ],
  };

  static const List<String> availableProviders = [
    'google',
    'openai',
    'anthropic',
    'mistral',
    'cohere',
    'openrouter',
  ];

  static const Map<String, String> providerLabels = {
    'google': 'Google Gemini',
    'openai': 'OpenAI',
    'anthropic': 'Anthropic',
    'mistral': 'Mistral',
    'cohere': 'Cohere',
    'openrouter': 'OpenRouter',
  };

  static const Map<String, String> providerApiUrls = {
    'openrouter': 'https://openrouter.ai/api/v1/chat/completions',
    'openai': 'https://api.openai.com/v1/chat/completions',
    'anthropic': 'https://api.anthropic.com/v1/messages',
    'mistral': 'https://api.mistral.ai/v1/chat/completions',
    'cohere': 'https://api.cohere.ai/v1/chat',
  };

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
