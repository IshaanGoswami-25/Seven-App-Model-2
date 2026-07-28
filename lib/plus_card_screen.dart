import 'package:flutter/material.dart';
import 'google_fonts_alias.dart';
import 'interactive_3d_card.dart';

class PlusCardScreen extends StatefulWidget {
  final String name;
  final String username;
  final String phoneNumber;

  const PlusCardScreen({
    super.key,
    required this.name,
    required this.username,
    required this.phoneNumber,
  });

  @override
  State<PlusCardScreen> createState() => _PlusCardScreenState();
}

class _PlusCardScreenState extends State<PlusCardScreen> with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.2), // Starts below the screen
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack, // Playful bounce transition
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F0E13) : const Color(0xFFF0EFEF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDarkMode ? Colors.white70 : Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Plus Card',
          style: GoogleFonts.firaSans(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : const Color(0xFF1E1E1E),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _slideController,
                builder: (context, child) {
                  return SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: Interactive3DCard(
                    name: widget.name,
                    username: widget.username,
                    phoneNumber: widget.phoneNumber,
                    autoRotate: true, // Enables slow 3D rotation automatically
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Center(
                child: Text(
                  'HX PLUS NFC CARD',
                  style: GoogleFonts.firaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: isDarkMode ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Tap your phone to share your Hexa profile instantly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.firaSans(
                    fontSize: 14,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
