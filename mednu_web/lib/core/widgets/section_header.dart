import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../utils/responsive.dart';

class SectionHeader extends StatelessWidget {
  final String tag;
  final String title;
  final String? subtitle;
  final CrossAxisAlignment alignment;
  final bool lightMode;

  const SectionHeader({
    super.key,
    required this.tag,
    required this.title,
    this.subtitle,
    this.alignment = CrossAxisAlignment.center,
    this.lightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isCenter = alignment == CrossAxisAlignment.center;
    final subtitleColor = lightMode ? Colors.white60 : AppColors.textSecondary;
    final tagColor = lightMode ? Colors.white70 : AppColors.primary;
    final tagBg1 = lightMode
        ? Colors.white.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.1);
    final tagBg2 = lightMode
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.secondary.withValues(alpha: 0.1);
    final tagBorder = lightMode
        ? Colors.white.withValues(alpha: 0.2)
        : AppColors.primary.withValues(alpha: 0.25);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tagBg1, tagBg2]),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: tagBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tagColor),
              ),
              const SizedBox(width: 8),
              Text(
                tag.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tagColor,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // lightMode = dark background → plain white text
        // !lightMode = light background → gradient text via ShaderMask srcIn
        if (lightMode)
          Text(
            title,
            textAlign: isCenter ? TextAlign.center : TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: isMobile ? 28 : 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
              letterSpacing: -0.8,
            ),
          )
        else
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) =>
                AppColors.primaryGradient.createShader(bounds),
            child: Text(
              title,
              textAlign: isCenter ? TextAlign.center : TextAlign.left,
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 28 : 40,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.15,
                letterSpacing: -0.8,
              ),
            ),
          ),
        if (subtitle != null) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              subtitle!,
              textAlign: isCenter ? TextAlign.center : TextAlign.left,
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 14 : 16.5,
                fontWeight: FontWeight.w400,
                color: subtitleColor,
                height: 1.7,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
