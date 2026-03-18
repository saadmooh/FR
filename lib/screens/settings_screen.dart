import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../repositories/app_settings_repository.dart';
import '../core/app_theme.dart';

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
    _showResult(result['success'] == true, result['message'] ?? 'Unknown error');
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // AI Provider
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.smart_toy, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'AI Provider',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedProvider,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Select provider',
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
          const SizedBox(height: 16),

          // API Key
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.key, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'API Key',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureText,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Enter API key...',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility : Icons.visibility_off,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscureText = !_obscureText),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isTesting ? null : _testKey,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent),
                        ),
                        child: _isTesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Test Key'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.background,
                        ),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'API Status: ${widget.aiService.hasApiKey() ? '✅ Connected' : '⚠️ Not configured'}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
