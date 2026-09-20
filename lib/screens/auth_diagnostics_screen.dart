import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_fonts/google_fonts.dart';
import '../core/app_theme.dart';

class AuthDiagnosticsScreen extends StatelessWidget {
  final List<String> entries;

  const AuthDiagnosticsScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final logText = entries.map((e) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        final ts = map['timestamp'] ?? '';
        final ev = map['event'] ?? '';
        final det = map['details'] ?? {};
        return '$ts | $ev | $det';
      } catch (_) {
        return e;
      }
    }).join('\n');

    return Scaffold(
      backgroundColor: AppColors.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppColors.whiteBackground,
        elevation: 0,
        title: Text(
          'Auth Diagnostics',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.whiteTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.whiteSurface,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.whiteBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Firebase User',
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.whiteTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currentUser == null
                      ? 'null'
                      : 'uid: ${currentUser.uid}\nemail: ${currentUser.email ?? 'null'}',
                  style: const TextStyle(
                    color: AppColors.whiteTextSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Log copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy log'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.whiteAccent,
              foregroundColor: AppColors.whiteBackground,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Auth Diag Log (${entries.length} entries)',
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.whiteTextPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map((e) {
            try {
              final map = jsonDecode(e) as Map<String, dynamic>;
              final ts = map['timestamp'] ?? '';
              final ev = map['event'] ?? '';
              final det = map['details'] ?? {};
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '$ts\n$ev | $det',
                  style: const TextStyle(
                    color: AppColors.whiteTextSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            } catch (_) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  e,
                  style: const TextStyle(
                    color: AppColors.whiteTextSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            }
          }),
        ],
      ),
    );
  }
}
