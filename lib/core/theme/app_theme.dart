import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF1989fa);
  static const Color upColor = Color(0xFFe4393c); // A股红涨
  static const Color downColor = Color(0xFF18a058); // A股绿跌
  static const Color flatColor = Color(0xFF999999);

  static const Color bgPrimary = Color(0xFFF2F3F5);
  static const Color bgSecondary = Color(0xFFFFFFFF);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textMuted = Color(0xFF999999);
  static const Color borderColor = Color(0xFFEEEEEE);
  static const Color borderLight = Color(0xFFF5F5F5);

  // ── 暗色模式色值 ──
  static const Color darkBg = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF1A1A2E);
  static const Color darkCard = Color(0xFF16213E);
  static const Color darkBorder = Color(0xFF2A2A4A);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkTextMuted = Color(0xFF6E6E6E);

  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? darkBg : bgPrimary;
    final surface = isDark ? darkSurface : bgSecondary;
    final card = isDark ? darkCard : bgCard;
    final border = isDark ? darkBorder : borderColor;
    final text = isDark ? darkTextPrimary : textPrimary;
    final textSec = isDark ? darkTextSecondary : textSecondary;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: border, width: 0.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        primary: primary,
        surface: surface,
        error: upColor,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: cardShape,
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 0.5,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: primary);
          }
          return TextStyle(
              fontSize: 12, fontWeight: FontWeight.w400, color: textSec);
        }),
      ),
      textTheme: TextTheme(
        headlineLarge:
            TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: text),
        headlineMedium:
            TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: text),
        titleLarge:
            TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text),
        titleMedium:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text),
        titleSmall:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
        bodyLarge: TextStyle(fontSize: 16, color: text),
        bodyMedium: TextStyle(fontSize: 14, color: text),
        bodySmall: TextStyle(fontSize: 12, color: textSec),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  static Color changeColor(double? value) {
    if (value == null || value == 0) return flatColor;
    return value > 0 ? upColor : downColor;
  }

  static String formatPercent(double? value, {bool withSign = true}) {
    if (value == null) return '--';
    final sign = withSign && value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  static String formatMoney(double? value, {String prefix = '¥'}) {
    if (value == null) return '--';
    return '$prefix${value.toStringAsFixed(2)}';
  }

  static String formatNetValue(double? value) {
    if (value == null || value <= 0) return '--';
    return value.toStringAsFixed(4);
  }

  static String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--';
    final parts = timeStr.split(' ');
    return parts.length > 1 ? parts[1] : timeStr;
  }

  static String formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '--';
    final parts = dateStr.split('-');
    if (parts.length >= 3) return '${parts[1]}-${parts[2]}';
    return dateStr;
  }
}
