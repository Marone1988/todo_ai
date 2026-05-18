import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Notifier global pour le thème (clair / sombre) — défaut : dark
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);

/// Notifier global pour les vibrations (haptic feedback)
final ValueNotifier<bool> hapticsEnabled = ValueNotifier(true);

/// Signal de refresh global — incrémenté à chaque ajout/suppression de tâche.
/// AlertsScreen écoute ce notifier pour se recharger sans redémarrer l'app.
final ValueNotifier<int> taskVersion = ValueNotifier(0);

/// Déclenche une courte vibration si l'option est activée.
/// Combine HapticFeedback (Flutter natif) + Vibration package pour max fiabilité.
void haptic() {
  if (!hapticsEnabled.value) return;
  HapticFeedback.heavyImpact();
  Vibration.vibrate(duration: 80);
}

bool get isDarkMode => appThemeMode.value == ThemeMode.dark;

// ── Thème Clair ────────────────────────────────────────────────
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFF2F2F7),
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF6366F1),
    secondary: Color(0xFF6366F1),
    surface: Colors.white,
    onSurface: Color(0xFF111827),
  ),
  cardColor: Colors.white,
  dividerColor: const Color(0xFFF2F2F7),
  useMaterial3: true,
);

// ── Thème Sombre ───────────────────────────────────────────────
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF000000),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF818CF8),
    secondary: Color(0xFF818CF8),
    surface: Color(0xFF1C1C1E),
    onSurface: Color(0xFFFFFFFF),
    surfaceContainerHighest: Color(0xFF2C2C2E),
  ),
  cardColor: const Color(0xFF1C1C1E),
  dividerColor: const Color(0xFF38383A),
  useMaterial3: true,
);

// ── Extension couleurs contextuelles ──────────────────────────
extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bgColor =>
      isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  Color get cardColor =>
      isDark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get cardColor2 =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9FAFB);
  Color get textPrimary =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xFF111827);
  Color get textSecondary =>
      isDark ? const Color(0xFF8E8E93) : const Color(0xFF6B7280);
  Color get textMuted =>
      isDark ? const Color(0xFF636366) : const Color(0xFF9CA3AF);
  Color get dividerColor =>
      isDark ? const Color(0xFF38383A) : const Color(0xFFF2F2F7);
  Color get inputFill =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF9FAFB);
  Color get sectionBg =>
      isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

  Color get primaryColor => const Color(0xFF6366F1);
  Color get primaryLight =>
      isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);

  Color catBg(String cat) {
    return isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF3F4F6);
  }

  Color catColor(String cat) {
    return isDark ? const Color(0xFFE5E7EB) : const Color(0xFF374151);
  }
}
