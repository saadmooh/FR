import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ai_proxy_response.dart';
import '../services/ai_proxy_service.dart';

class AiProxyDemoScreen extends StatefulWidget {
  const AiProxyDemoScreen({super.key});

  @override
  State<AiProxyDemoScreen> createState() => _AiProxyDemoScreenState();
}

class _AiProxyDemoScreenState extends State<AiProxyDemoScreen> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _strict = true;
  bool _loading = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _signedIn => Supabase.instance.client.auth.currentSession != null;

  Future<void> _signIn() async {
    setState(() => _error = null);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل تسجيل الدخول: $e');
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final service = AiProxyService.fromConfig(strictIntegrityCheck: _strict);
      final response = await service.sendPrompt(prompt: prompt);
      if (mounted) {
        setState(() {
          _result = response.text;
          _loading = false;
        });
      }
    } on AiProxyException catch (e) {
      if (mounted) {
        setState(() {
          _error = '${e.message}\n(code: ${e.code})';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Proxy Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Strict integrity check'),
            value: _strict,
            onChanged: (v) => setState(() => _strict = v),
          ),
          if (!_signedIn) ...[
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Supabase email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _signIn,
              child: const Text('Sign in'),
            ),
          ] else
            Row(
              children: [
                const Expanded(child: Text('Signed in')),
                TextButton(
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          const SizedBox(height: 24),
          TextField(
            controller: _promptController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'اكتب رسالتك هنا...',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: (_loading || !_signedIn) ? null : _send,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!),
          ],
        ],
      ),
    );
  }
}
