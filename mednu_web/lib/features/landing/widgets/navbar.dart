import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/launch_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/gradient_button.dart';

class WebNavbar extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onLoginTap;
  final void Function(String)? onNavTap;
  final String activeSection;

  const WebNavbar({
    super.key,
    required this.scrollController,
    required this.onLoginTap,
    this.onNavTap,
    this.activeSection = 'Home',
  });

  @override
  State<WebNavbar> createState() => _WebNavbarState();
}

class _WebNavbarState extends State<WebNavbar> {
  bool _scrolled = false;
  bool _mobileMenuOpen = false;
  late String _activeItem;

  @override
  void initState() {
    super.initState();
    _activeItem = widget.activeSection;
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(WebNavbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSection != widget.activeSection) {
      setState(() => _activeItem = widget.activeSection);
    }
  }

  void _onScroll() {
    final scrolled = widget.scrollController.offset > 20;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: _scrolled ? Colors.white.withOpacity(0.97) : Colors.white,
        boxShadow: _scrolled
            ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 70,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
              ),
              child: Row(
                children: [
                  _Logo(),
                  const Spacer(),
                  if (!isMobile) ...[
                    _NavLinks(
                      activeItem: _activeItem,
                      onItemTap: (item) {
                        setState(() => _activeItem = item);
                        widget.onNavTap?.call(item);
                      },
                    ),
                    const SizedBox(width: 32),
                    _AuthButtons(onLoginTap: widget.onLoginTap),
                  ] else ...[
                    GestureDetector(
                      onTap: () => setState(() => _mobileMenuOpen = !_mobileMenuOpen),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _mobileMenuOpen ? Icons.close_rounded : Icons.menu_rounded,
                          color: AppColors.textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isMobile && _mobileMenuOpen)
            _MobileMenu(
              activeItem: _activeItem,
              onItemTap: (item) {
                setState(() {
                  _activeItem = item;
                  _mobileMenuOpen = false;
                });
                widget.onNavTap?.call(item);
              },
              onLoginTap: () {
                setState(() => _mobileMenuOpen = false);
                widget.onLoginTap();
              },
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Text('M', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
          child: Text(
            'MedNu',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _NavLinks extends StatelessWidget {
  final String activeItem;
  final ValueChanged<String> onItemTap;

  const _NavLinks({required this.activeItem, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: AppConstants.navItems.map((item) => _NavItem(
        label: item,
        isActive: activeItem == item,
        onTap: () => onItemTap(item),
      )).toList(),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({required this.label, required this.isActive, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                  color: widget.isActive || _hovered ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: widget.isActive ? 20 : 0,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthButtons extends StatelessWidget {
  final VoidCallback onLoginTap;
  const _AuthButtons({required this.onLoginTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onLoginTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Log In',
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GradientButton(
          label: 'Get Started',
          onTap: onLoginTap,
          height: 40,
          fontSize: 13,
          width: 115,
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }
}

class _MobileMenu extends StatelessWidget {
  final String activeItem;
  final ValueChanged<String> onItemTap;
  final VoidCallback onLoginTap;

  const _MobileMenu({
    required this.activeItem,
    required this.onItemTap,
    required this.onLoginTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...AppConstants.navItems.map((item) => ListTile(
            dense: true,
            title: Text(
              item,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: activeItem == item ? FontWeight.w600 : FontWeight.w500,
                color: activeItem == item ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            trailing: activeItem == item
                ? Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))
                : null,
            onTap: () => onItemTap(item),
            contentPadding: EdgeInsets.zero,
          )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlineGradientButton(label: 'Login', onTap: onLoginTap, height: 44),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Download',
                onTap: () => openUrl(AppConstants.apkDownloadUrl),
                height: 44,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
