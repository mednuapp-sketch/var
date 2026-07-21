import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';

class DashboardSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onLogout;
  final bool collapsed;

  const DashboardSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    this.collapsed = false,
  });

  static const List<_SidebarItem> items = [
    _SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _SidebarItem(icon: Icons.calendar_today_rounded, label: 'Appointments'),
    _SidebarItem(icon: Icons.medication_rounded, label: 'Prescriptions'),
    _SidebarItem(icon: Icons.account_balance_wallet_rounded, label: 'Wallet'),
    _SidebarItem(icon: Icons.people_rounded, label: 'Family'),
    _SidebarItem(icon: Icons.favorite_rounded, label: 'Health'),
    _SidebarItem(icon: Icons.card_giftcard_rounded, label: 'Referrals'),
    _SidebarItem(icon: Icons.notifications_rounded, label: 'Notifications'),
    _SidebarItem(icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: collapsed ? 72 : 256,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(right: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        children: [
          _SidebarHeader(collapsed: collapsed),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: items.length,
              itemBuilder: (context, i) => _SidebarNavItem(
                item: items[i],
                selected: selectedIndex == i,
                collapsed: collapsed,
                onTap: () => onItemSelected(i),
              ),
            ),
          ),
          const Divider(color: Color(0x1AFFFFFF), height: 1),
          _LogoutButton(collapsed: collapsed, onLogout: onLogout),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  const _SidebarItem({required this.icon, required this.label});
}

class _SidebarHeader extends StatelessWidget {
  final bool collapsed;
  const _SidebarHeader({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 20),
      child: Row(
        children: [
          Image.asset('assets/images/mednu_logo.png', width: 36, height: 36, filterQuality: FilterQuality.high),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            Text('MedNU', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
          ],
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final _SidebarItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.collapsed ? 16 : 14,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            gradient: widget.selected ? AppColors.primaryGradient : null,
            color: widget.selected ? null : (_hovered ? Colors.white.withOpacity(0.07) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.selected
                ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                : [],
          ),
          child: Row(children: [
            Icon(
              widget.item.icon,
              size: 20,
              color: widget.selected ? Colors.white : (widget.selected || _hovered ? Colors.white70 : const Color(0xFF4A6080)),
            ),
            if (!widget.collapsed) ...[
              const SizedBox(width: 12),
              Text(
                widget.item.label,
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.selected ? Colors.white : (_hovered ? Colors.white70 : const Color(0xFF4A6080)),
                ),
              ),
              if (widget.item.label == 'Notifications') ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('3', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatefulWidget {
  final bool collapsed;
  final VoidCallback onLogout;
  const _LogoutButton({required this.collapsed, required this.onLogout});

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onLogout,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 16 : 14, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered ? Colors.red.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.logout_rounded, size: 20, color: _hovered ? Colors.redAccent : const Color(0xFF4A6080)),
            if (!widget.collapsed) ...[
              const SizedBox(width: 12),
              Text(
                'Sign Out',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: _hovered ? Colors.redAccent : const Color(0xFF4A6080),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
