import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/responsive.dart';
import 'widgets/sidebar.dart';
import 'pages/home_page.dart';
import 'pages/appointments_page.dart';
import 'pages/prescriptions_page.dart';
import 'pages/wallet_page.dart';
import 'pages/profile_page.dart';
import 'pages/health_page.dart';
import 'pages/family_page.dart';
import 'pages/referrals_page.dart';
import 'pages/notifications_page.dart';

class DashboardShell extends StatefulWidget {
  final VoidCallback onLogout;
  const DashboardShell({super.key, required this.onLogout});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;
  // Scaffold.of() cannot be used here: this State's `context` sits ABOVE the
  // Scaffold created in build(), so the lookup walks past it and throws.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static final List<Widget> _pages = [
    const DashboardHomePage(),
    const AppointmentsPage(),
    const PrescriptionsPage(),
    const WalletPage(),
    const FamilyPage(),
    const HealthPage(),
    const ReferralsPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isMobile ? Drawer(
        child: DashboardSidebar(
          selectedIndex: _selectedIndex,
          onItemSelected: (i) {
            setState(() => _selectedIndex = i);
            Navigator.pop(context);
          },
          onLogout: widget.onLogout,
          collapsed: false,
        ),
      ) : null,
      body: isMobile
          ? Column(children: [
              _MobileTopBar(
                selectedIndex: _selectedIndex,
                onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                onLogout: widget.onLogout,
              ),
              Expanded(child: _pages[_selectedIndex]),
            ])
          : Row(children: [
              DashboardSidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: (i) => setState(() => _selectedIndex = i),
                onLogout: widget.onLogout,
                collapsed: _sidebarCollapsed,
              ),
              Expanded(
                child: Column(children: [
                  _DesktopTopBar(
                    pageTitle: _pageTitles[_selectedIndex],
                    collapsed: _sidebarCollapsed,
                    onCollapseToggle: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    onLogout: widget.onLogout,
                  ),
                  Expanded(child: _pages[_selectedIndex]),
                ]),
              ),
            ]),
    );
  }
}

const List<String> _pageTitles = [
  'Dashboard', 'Appointments', 'Prescriptions', 'Wallet',
  'Family Members', 'Health Dashboard', 'Referrals', 'Notifications', 'Profile',
];

class _DesktopTopBar extends StatelessWidget {
  final String pageTitle;
  final bool collapsed;
  final VoidCallback onCollapseToggle;
  final VoidCallback onLogout;

  const _DesktopTopBar({
    required this.pageTitle,
    required this.collapsed,
    required this.onCollapseToggle,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onCollapseToggle,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: Icon(
              collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(pageTitle, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const Spacer(),
        _SearchBar(),
        const SizedBox(width: 12),
        _NotificationBell(),
        const SizedBox(width: 12),
        _UserAvatar(onLogout: onLogout),
      ]),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  final int selectedIndex;
  final VoidCallback onMenuTap;
  final VoidCallback onLogout;

  const _MobileTopBar({required this.selectedIndex, required this.onMenuTap, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onMenuTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.menu_rounded, size: 20, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Row(children: [
          Image.asset('assets/images/mednu_logo.png', width: 28, height: 28, filterQuality: FilterQuality.high),
          const SizedBox(width: 7),
          Text('MedNU', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
        ]),
        const Spacer(),
        _NotificationBell(),
        const SizedBox(width: 8),
        _UserAvatar(onLogout: onLogout),
      ]),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const SizedBox(width: 10),
        const Icon(Icons.search_rounded, size: 16, color: AppColors.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search...',
              border: InputBorder.none,
              isDense: true,
              hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ]),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: const Icon(Icons.notifications_outlined, size: 20, color: AppColors.textSecondary),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final VoidCallback onLogout;
  const _UserAvatar({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
        child: const Center(child: Text('👤', style: TextStyle(fontSize: 18))),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          child: Row(children: [
            const Icon(Icons.person_outline_rounded, size: 16),
            const SizedBox(width: 8),
            Text('Profile', style: GoogleFonts.poppins(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          onTap: onLogout,
          child: Row(children: [
            const Icon(Icons.logout_rounded, size: 16, color: Colors.red),
            const SizedBox(width: 8),
            Text('Sign Out', style: GoogleFonts.poppins(fontSize: 13, color: Colors.red)),
          ]),
        ),
      ],
    );
  }
}

