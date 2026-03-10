import 'package:flutter/material.dart';
import 'package:soft_egg_packager/src/theme/app_fonts.dart';
import 'package:soft_egg_packager/src/features/wizard/packaging_wizard_page.dart';

class SoftEggApp extends StatelessWidget {
  const SoftEggApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = AppFonts.sourceSans3TextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SoftEgg Packaging Tool',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF111621),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF0F172A),
          onSurface: Color(0xFFE2E8F0),
        ),
        textTheme: baseTextTheme.copyWith(
          headlineLarge: AppFonts.lexend(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineMedium: AppFonts.lexend(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          titleLarge: AppFonts.lexend(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const PackagingWizardPage(),
    );
  }
}
