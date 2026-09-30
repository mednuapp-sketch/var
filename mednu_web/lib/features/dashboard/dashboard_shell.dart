import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/net_image.dart';
import 'package:go_router/go_router.dart';
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

  List<Widget> get _pages => [
    DashboardHomePage(onNavigate: (i) => setState(() => _selectedIndex = i)),
    const AppointmentsPage(),
    const PrescriptionsPage(),
    const WalletPage(),
    const FamilyPage(),
    const HealthPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  static const int _notificationsIndex = 6;
  static const int _profileIndex = 7;

  Stream<int> get _unreadStream {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('patient_notifications')
        .doc(uid)
        .collection('items')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadStream,
      builder: (context, snap) => _buildShell(context, snap.data ?? 0),
    );
  }

  Widget _buildShell(BuildContext context, int unread) {
    final isMobile = Responsive.isMobile(context);
    void openNotifications() => setState(() => _selectedIndex = _notificationsIndex);
    void openProfile() => setState(() => _selectedIndex = _profileIndex);

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
          unreadCount: unread,
        ),
      ) : null,
      body: isMobile
          ? Column(children: [
              _MobileTopBar(
                selectedIndex: _selectedIndex,
                onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                onLogout: widget.onLogout,
                unread: unread,
                onBellTap: openNotifications,
                onProfileTap: openProfile,
              ),
              Expanded(child: _pages[_selectedIndex]),
            ])
          : Row(children: [
              DashboardSidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: (i) => setState(() => _selectedIndex = i),
                onLogout: widget.onLogout,
                collapsed: _sidebarCollapsed,
                unreadCount: unread,
              ),
              Expanded(
                child: Column(children: [
                  _DesktopTopBar(
                    pageTitle: _pageTitles[_selectedIndex],
                    collapsed: _sidebarCollapsed,
                    onCollapseToggle: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    onLogout: widget.onLogout,
                    unread: unread,
                    onBellTap: openNotifications,
                    onProfileTap: openProfile,
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
  'Family Members', 'Health Dashboard', 'Notifications', 'Profile',
];

class _DesktopTopBar extends StatelessWidget {
  final String pageTitle;
  final bool collapsed;
  final VoidCallback onCollapseToggle;
  final VoidCallback onLogout;
  final int unread;
  final VoidCallback onBellTap;
  final VoidCallback onProfileTap;

  const _DesktopTopBar({
    required this.pageTitle,
    required this.collapsed,
    required this.onCollapseToggle,
    required this.onLogout,
    required this.unread,
    required this.onBellTap,
    required this.onProfileTap,
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
        _NotificationBell(unread: unread, onTap: onBellTap),
        const SizedBox(width: 12),
        _UserAvatar(onLogout: onLogout, onProfile: onProfileTap),
      ]),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  final int selectedIndex;
  final VoidCallback onMenuTap;
  final VoidCallback onLogout;
  final int unread;
  final VoidCallback onBellTap;
  final VoidCallback onProfileTap;

  const _MobileTopBar({
    required this.selectedIndex,
    required this.onMenuTap,
    required this.onLogout,
    required this.unread,
    required this.onBellTap,
    required this.onProfileTap,
  });

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
        GestureDetector(
          onTap: () => context.go('/'),
          child: Row(children: [
            Image.asset('assets/images/mednu_logo.png', width: 28, height: 28, filterQuality: FilterQuality.high),
            const SizedBox(width: 7),
            Text('MedNU', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ),
        const Spacer(),
        _NotificationBell(unread: unread, onTap: onBellTap),
        const SizedBox(width: 8),
        _UserAvatar(onLogout: onLogout, onProfile: onProfileTap),
      ]),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _NotificationBell({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.notifications_outlined, size: 20, color: AppColors.textSecondary),
          ),
          if (unread > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.3)),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfile;
  const _UserAvatar({required this.onLogout, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid.isEmpty ? null : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = (data['name'] as String?) ?? '';
        final photo = (data['photoUrl'] as String?) ?? '';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : null;
        return PopupMenuButton<String>(
          tooltip: 'Account',
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) => v == 'profile' ? onProfile() : onLogout(),
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
            child: ClipOval(
              child: photo.isNotEmpty
                  ? NetImage(
                      url: photo,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      fallback: Center(child: Text(initial ?? '?', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                    )
                  : Center(
                      child: initial != null
                          ? Text(initial, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))
                          : const Icon(Icons.person_rounded, size: 20, color: Colors.white),
                    ),
            ),
          ),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'profile',
              child: Row(children: [
                const Icon(Icons.person_outline_rounded, size: 16),
                const SizedBox(width: 8),
                Text('My Profile', style: GoogleFonts.poppins(fontSize: 13)),
              ]),
            ),
            PopupMenuItem(
              value: 'logout',
              child: Row(children: [
                const Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Text('Sign Out', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.error)),
              ]),
            ),
          ],
        );
      },
    );
  }
}
