import 'package:flutter/material.dart';

class AppFonts {
  static const List<String> _sansFallback = <String>[
    'Noto Sans KR',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'Segoe UI',
    'Arial',
  ];

  static const List<String> _displayFallback = <String>[
    'Noto Sans KR',
    'Apple SD Gothic Neo',
    'Malgun Gothic',
    'Segoe UI',
  ];

  static const List<String> _monoFallback = <String>[
    'D2Coding',
    'Menlo',
    'Consolas',
    'Monaco',
    'monospace',
  ];

  static TextStyle sourceSans3({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    return _composeStyle(
      textStyle: textStyle,
      primaryFamily: 'Source Sans 3',
      fallbackFamilies: _sansFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle lexend({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    return _composeStyle(
      textStyle: textStyle,
      primaryFamily: 'Lexend',
      fallbackFamilies: _displayFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle jetBrainsMono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    return _composeStyle(
      textStyle: textStyle,
      primaryFamily: 'JetBrains Mono',
      fallbackFamilies: _monoFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextTheme sourceSans3TextTheme([TextTheme? textTheme]) {
    final base = textTheme ?? ThemeData.light().textTheme;
    return base.copyWith(
      displayLarge: sourceSans3(textStyle: base.displayLarge),
      displayMedium: sourceSans3(textStyle: base.displayMedium),
      displaySmall: sourceSans3(textStyle: base.displaySmall),
      headlineLarge: sourceSans3(textStyle: base.headlineLarge),
      headlineMedium: sourceSans3(textStyle: base.headlineMedium),
      headlineSmall: sourceSans3(textStyle: base.headlineSmall),
      titleLarge: sourceSans3(textStyle: base.titleLarge),
      titleMedium: sourceSans3(textStyle: base.titleMedium),
      titleSmall: sourceSans3(textStyle: base.titleSmall),
      bodyLarge: sourceSans3(textStyle: base.bodyLarge),
      bodyMedium: sourceSans3(textStyle: base.bodyMedium),
      bodySmall: sourceSans3(textStyle: base.bodySmall),
      labelLarge: sourceSans3(textStyle: base.labelLarge),
      labelMedium: sourceSans3(textStyle: base.labelMedium),
      labelSmall: sourceSans3(textStyle: base.labelSmall),
    );
  }

  static TextStyle _composeStyle({
    required String primaryFamily,
    required List<String> fallbackFamilies,
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
  }) {
    final base = textStyle ?? const TextStyle();
    final mergedFallbacks = <String>{
      ...fallbackFamilies,
      ...?base.fontFamilyFallback,
    }.toList(growable: false);

    return base.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: mergedFallbacks,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}
