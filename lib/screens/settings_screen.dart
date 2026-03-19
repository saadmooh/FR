import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../repositories/app_settings_repository.dart';
import '../core/app_theme.dart';
import '../core/locale_manager.dart';

class SettingsScreen extends StatefulWidget {
  final AIService aiService;
  final AppSettingsRepository settingsRepository;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.settingsRepository,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  String _selectedProvider = 'google';
  String _selectedLanguage = 'en';
  bool _isTesting = false;
  bool _obscureText = true;

  final List<Map<String, String>> _providers = [
    {'value': 'google', 'label': 'Google Gemini'},
    {'value': 'openai', 'label': 'OpenAI'},
    {'value': 'anthropic', 'label': 'Anthropic'},
    {'value': 'mistral', 'label': 'Mistral'},
    {'value': 'cohere', 'label': 'Cohere'},
  ];

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.aiService.getProvider();
    _selectedLanguage = LocaleManager.instance.getLocale();
    final existingKey = widget.aiService.getApiKey();
    if (existingKey != null) {
      _apiKeyController.text = existingKey;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testKey() async {
    setState(() => _isTesting = true);

    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _isTesting = false);
      _showResult(false, 'Please enter an API key');
      return;
    }

    widget.aiService.setApiKey(key);
    final result = await widget.aiService.testApiKey();

    setState(() => _isTesting = false);
    _showResult(
      result['success'] == true,
      result['message'] ?? 'Unknown error',
    );
  }

  void _saveSettings() {
    final key = _apiKeyController.text.trim();
    if (key.isNotEmpty) {
      widget.aiService.setApiKey(key);
    }
    widget.settingsRepository.setProvider(_selectedProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _showResult(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ $message' : '❌ $message'),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteSurface,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 24,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),

          // AI Provider Section
          _buildSectionHeader('AI Configuration', Icons.smart_toy_outlined),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Provider',
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedProvider,
                  dropdownColor: AppColors.whiteSurface,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'Select provider',
                    hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  items: _providers.map((p) {
                    return DropdownMenuItem(
                      value: p['value'],
                      child: Text(p['label']!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedProvider = value);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Language Section
          _buildSectionHeader('Language', Icons.language_outlined),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Language / اللغة / Langue',
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedLanguage,
                  dropdownColor: AppColors.whiteSurface,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'Select language',
                    hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'fr', child: Text('Français')),
                  ],
                  onChanged: (value) async {
                    if (value != null) {
                      await LocaleManager.instance.setLocale(value);
                      // The listener in main.dart will trigger a rebuild
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // API Key Section
          _buildSectionHeader('API Key', Icons.key_outlined),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API Key',
                  style: TextStyle(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureText,
                  style: TextStyle(color: AppColors.whiteTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter API key...',
                    hintStyle: TextStyle(color: AppColors.whiteTextSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.whiteTextSecondary,
                      ),
                      onPressed: () =>
                          setState(() => _obscureText = !_obscureText),
                    ),
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
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isTesting ? null : _testKey,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_outlined),
                        label: _isTesting
                            ? const Text('Testing...')
                            : const Text('Test Key'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(
                            color: AppColors.accent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 2,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Status Section
          _buildSectionHeader('Status', Icons.info_outline),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  widget.aiService.hasApiKey()
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: widget.aiService.hasApiKey()
                      ? AppColors.success
                      : AppColors.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.aiService.hasApiKey()
                        ? 'API Connected'
                        : 'API Not Configured',
                    style: TextStyle(
                      color: AppColors.whiteTextPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.aiService.hasApiKey()
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    widget.aiService.hasApiKey() ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: widget.aiService.hasApiKey()
                          ? AppColors.success
                          : AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppColors.whiteTextSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
