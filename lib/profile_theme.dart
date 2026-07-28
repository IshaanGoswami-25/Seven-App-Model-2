import 'package:flutter/material.dart';

class ProfileThemeColors {
  final String id;
  final String name;
  final Color primary;
  final Color secondary;
  final Color cardGlow;

  const ProfileThemeColors({
    required this.id,
    required this.name,
    required this.primary,
    required this.secondary,
    required this.cardGlow,
  });

  static const List<ProfileThemeColors> themes = [
    ProfileThemeColors(
      id: 'default',
      name: 'Indigo Pulse',
      primary: Color(0xFF6366F1),
      secondary: Color(0xFF4F46E5),
      cardGlow: Color(0xFF6366F1),
    ),
    ProfileThemeColors(
      id: 'neon',
      name: 'Neon Cyber',
      primary: Color(0xFF00F2FE),
      secondary: Color(0xFF0DF2A3),
      cardGlow: Color(0xFF00F2FE),
    ),
    ProfileThemeColors(
      id: 'sunset',
      name: 'Sunset Rose',
      primary: Color(0xFFFF5E62),
      secondary: Color(0xFFFF9966),
      cardGlow: Color(0xFFFF5E62),
    ),
    ProfileThemeColors(
      id: 'carbon',
      name: 'Carbon Steel',
      primary: Color(0xFFE0E0E0),
      secondary: Color(0xFF757575),
      cardGlow: Color(0xFF757575),
    ),
  ];

  static ProfileThemeColors getTheme(String? id) {
    return themes.firstWhere(
      (theme) => theme.id == id,
      orElse: () => themes.first,
    );
  }
}
