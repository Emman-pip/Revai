import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF7868E9),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xFF14171D) : const Color(0xFFF6F7F3),
        surfaceContainerLow: dark ? const Color(0xFF20242C) : Colors.white,
        onSurface: dark ? const Color(0xFFEDF0F5) : const Color(0xFF142326),
        onSurfaceVariant: dark
            ? const Color(0xFFB7BFCC)
            : const Color(0xFF596969),
        outlineVariant: dark
            ? const Color(0xFF3D4350)
            : const Color(0xFFDDE4E1),
        secondaryContainer: dark
            ? const Color(0xFF193F35)
            : const Color(0xFFC6F0DC),
        onSecondaryContainer: dark
            ? const Color(0xFFD4F7E6)
            : const Color(0xFF143C2D),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}

extension ThemeColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}

class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.setDarkMode,
    required super.child,
  });

  final ValueChanged<bool> setDarkMode;

  static ThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!;

  @override
  bool updateShouldNotify(ThemeScope oldWidget) =>
      setDarkMode != oldWidget.setDarkMode;
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
      onPressed: () => ThemeScope.of(context).setDarkMode(!dark),
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
