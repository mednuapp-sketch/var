import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle get displayLarge => GoogleFonts.poppins(
    fontSize: 56, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
    height: 1.1, letterSpacing: -1.5,
  );

  static TextStyle get displayMedium => GoogleFonts.poppins(
    fontSize: 44, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
    height: 1.15, letterSpacing: -1.0,
  );

  static TextStyle get displaySmall => GoogleFonts.poppins(
    fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
    height: 1.2, letterSpacing: -0.5,
  );

  static TextStyle get h1 => GoogleFonts.poppins(
    fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
    height: 1.25, letterSpacing: -0.3,
  );

  static TextStyle get h2 => GoogleFonts.poppins(
    fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
    height: 1.3, letterSpacing: -0.2,
  );

  static TextStyle get h3 => GoogleFonts.poppins(
    fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
    height: 1.35,
  );

  static TextStyle get h4 => GoogleFonts.poppins(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get bodyLarge => GoogleFonts.poppins(
    fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
    height: 1.6,
  );

  static TextStyle get bodyMedium => GoogleFonts.poppins(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
    height: 1.6,
  );

  static TextStyle get bodySmall => GoogleFonts.poppins(
    fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textHint,
    height: 1.5,
  );

  static TextStyle get labelLarge => GoogleFonts.poppins(
    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
    height: 1.4, letterSpacing: 0.1,
  );

  static TextStyle get labelMedium => GoogleFonts.poppins(
    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
    height: 1.4, letterSpacing: 0.5,
  );

  static TextStyle get labelSmall => GoogleFonts.poppins(
    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textHint,
    height: 1.4, letterSpacing: 0.5,
  );

  static TextStyle get button => GoogleFonts.poppins(
    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
    letterSpacing: 0.3,
  );

  static TextStyle get caption => GoogleFonts.poppins(
    fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textHint,
    height: 1.4,
  );

  static TextStyle get navLink => GoogleFonts.poppins(
    fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
    height: 1.0,
  );

  static TextStyle get sectionTitle => GoogleFonts.poppins(
    fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
    height: 1.2, letterSpacing: -0.5,
  );

  static TextStyle get sectionSubtitle => GoogleFonts.poppins(
    fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
    height: 1.6,
  );

  static TextStyle get cardTitle => GoogleFonts.poppins(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get cardSubtitle => GoogleFonts.poppins(
    fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary,
    height: 1.5,
  );
}
