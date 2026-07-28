import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';

class DevelopedByFooter extends StatelessWidget {
  const DevelopedByFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 32.0),
      child: Center(
        child: Opacity(
          opacity: 0.45,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'developed by Ishaan',
                style: GoogleFonts.firaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: isDarkMode ? Colors.white70 : const Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(width: 6),
              Text('✨💻❤️', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
