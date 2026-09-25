import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/launch_utils.dart';
import '../../../core/utils/responsive.dart';

/// "Join us" area for doctors and other healthcare service providers.
class ProviderSection extends StatelessWidget {
  const ProviderSection({super.key});

  static String get _waNumber {
    final raw = AppConstants.whatsappNumber.isNotEmpty ? AppConstants.whatsappNumber : AppConstants.contactPhone;
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: isMobile ? 48 : 80,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: Container(
            padding: EdgeInsets.all(isMobile ? 24 : 48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 40, offset: const Offset(0, 16))],
            ),
            child: isMobile
                ? Column(children: [_Info(center: true), const SizedBox(height: 32), const _Qr()])
                : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(flex: 6, child: _Info(center: false)),
                    const SizedBox(width: 48),
                    const _Qr(),
                  ]),
          ),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final bool center;
  const _Info({required this.center});

  @override
  Widget build(BuildContext context) {
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final ta = center ? TextAlign.center : TextAlign.left;
    return Column(crossAxisAlignment: align, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text('For Doctors & Service Providers',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
      ),
      const SizedBox(height: 16),
      Text('Are you a Doctor or Healthcare\nservices provider? Join us.',
          textAlign: ta,
          style: GoogleFonts.poppins(
              fontSize: Responsive.isMobile(context) ? 24 : 34,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
              letterSpacing: -0.5)),
      const SizedBox(height: 14),
      Text('Reach more patients, manage appointments and grow your practice with the MedNU partner app. Get in touch with our team or download the app to get started.',
          textAlign: ta,
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.7)),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        children: [
          _ActionBtn(
            icon: FontAwesomeIcons.whatsapp,
            label: 'WhatsApp us',
            filled: true,
            onTap: () => openUrl('https://wa.me/${ProviderSection._waNumber}?text=${Uri.encodeComponent('Hi MedNU, I would like to join as a service provider.')}'),
          ),
          _ActionBtn(
            icon: FontAwesomeIcons.envelope,
            label: 'Email us',
            filled: false,
            onTap: () => openUrl('mailto:${AppConstants.contactEmail}?subject=${Uri.encodeComponent('Join MedNU as a service provider')}'),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Wrap(
        spacing: 24,
        runSpacing: 10,
        alignment: center ? WrapAlignment.center : WrapAlignment.start,
        children: [
          _ContactLine(icon: FontAwesomeIcons.phone, text: AppConstants.contactPhone, url: 'tel:${AppConstants.contactPhone.replaceAll(' ', '')}'),
          _ContactLine(icon: FontAwesomeIcons.envelope, text: AppConstants.contactEmail, url: 'mailto:${AppConstants.contactEmail}'),
        ],
      ),
    ]);
  }
}

class _ActionBtn extends StatefulWidget {
  final FaIconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.filled, required this.onTap});

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.filled;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            gradient: f ? AppColors.primaryGradient : null,
            color: f ? null : (_hovered ? AppColors.primarySoft : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: f ? null : Border.all(color: AppColors.primary, width: 1.5),
            boxShadow: f ? [BoxShadow(color: AppColors.primary.withValues(alpha: _hovered ? 0.4 : 0.22), blurRadius: 16, offset: const Offset(0, 6))] : [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FaIcon(widget.icon, size: 17, color: f ? Colors.white : AppColors.primary),
            const SizedBox(width: 10),
            Text(widget.label,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: f ? Colors.white : AppColors.primary)),
          ]),
        ),
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  final FaIconData icon;
  final String text;
  final String url;
  const _ContactLine({required this.icon, required this.text, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openUrl(url),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FaIcon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      ]),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 170,
        height: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: QrImageView(
          data: AppConstants.partnerAppUrl,
          version: QrVersions.auto,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.primaryDark),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.primaryDark),
        ),
      ),
      const SizedBox(height: 14),
      Text('Scan to get the MedNU Partner app',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => openUrl(AppConstants.partnerAppUrl),
        child: Text('or download from Google Play',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary, decoration: TextDecoration.underline)),
      ),
    ]);
  }
}
