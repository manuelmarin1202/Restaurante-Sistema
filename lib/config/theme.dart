import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Tema Claro (Light Mode)
  static final ThemeData lightTheme = FlexThemeData.light(
    scheme: FlexScheme.mandyRed, // Un color rojo queda bien para restaurantes
    useMaterial3: true,
    fontFamily: GoogleFonts.poppins().fontFamily, // Tipografía moderna
    subThemesData: const FlexSubThemesData(
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorRadius: 12.0,
    ),
  );

  // Tema Oscuro (Dark Mode) - Opcional por ahora
  static final ThemeData darkTheme = FlexThemeData.dark(
    scheme: FlexScheme.mandyRed,
    useMaterial3: true,
    fontFamily: GoogleFonts.poppins().fontFamily,
  );
}