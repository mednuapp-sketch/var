import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  static const _transactions = [
    {'title': 'Referral Bonus', 'subtitle': 'Friend joined MedNu', 'amount': '+₹100', 'date': 'Jun 10, 2026', 'type': 'credit', 'emoji': '🎁'},
    {'title': 'Appointment Payment', 'subtitle': 'Dr. Priya Sharma', 'amount': '-₹800', 'date': 'Jun 8, 2026', 'type': 'debit', 'emoji': '💊'},
    {'title': 'Cashback', 'subtitle': 'Lab test booking', 'amount': '+₹50', 'date': 'Jun 5, 2026', 'type': 'credit', 'emoji': '💰'},
    {'title': 'Appointment Payment', 'subtitle': 'Dr. Arjun Menon', 'amount': '-₹600', 'date': 'May 28, 2026', 'type': 'debit', 'emoji': '🏥'},
    {'title': 'Wallet Top-up', 'subtitle': 'Via UPI', 'amount': '+₹500', 'date': 'May 20, 2026', 'type': 'credit', 'emoji': '📱'},
    {'title': 'Referral Bonus', 'subtitle': 'Sister joined MedNu', 'amount': '+₹100', 'date': 'May 15, 2026', 'type': 'credit', 'emoji': '🎁'},
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Wallet', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Manage your balance and transactions', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        isMobile
            ? Column(children: [_BalanceCard(), const SizedBox(height: 16), _WalletActions()])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: _BalanceCard()),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _WalletActions()),
              ]),
        const SizedBox(height: 28),
        _TransactionsList(transactions: _transactions),
      ]),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 28)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text('MedNu Wallet', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Available Balance', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 4),
        Text('₹500.00', style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
        const SizedBox(height: 16),
        Row(children: [
          _BalanceStat(label: 'Total Earned', value: '₹750'),
          const SizedBox(width: 20),
          _BalanceStat(label: 'Total Spent', value: '₹1,400'),
        ]),
      ]),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  const _BalanceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white60)),
      Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
    ]);
  }
}

class _WalletActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quick Actions', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _ActionChip(emoji: '💳', label: 'Add Money', color: AppColors.primary),
          _ActionChip(emoji: '📤', label: 'Withdraw', color: AppColors.secondary),
          _ActionChip(emoji: '🔄', label: 'Transfer', color: AppColors.accent),
          _ActionChip(emoji: '📊', label: 'Statement', color: AppColors.info),
        ]),
      ]),
    );
  }
}

class _ActionChip extends StatefulWidget {
  final String emoji;
  final String label;
  final Color color;
  const _ActionChip({required this.emoji, required this.label, required this.color});

  @override
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withOpacity(0.1) : widget.color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.color.withOpacity(_hovered ? 0.4 : 0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(widget.label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: widget.color)),
          ]),
        ),
      ),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  final List<Map<String, String>> transactions;
  const _TransactionsList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Text('Transaction History', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            TextButton(onPressed: () {}, child: Text('Export', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1),
        ...transactions.asMap().entries.map((entry) => Column(children: [
          _TxRow(tx: entry.value),
          if (entry.key < transactions.length - 1) const Divider(height: 1, indent: 72),
        ])),
      ]),
    );
  }
}

class _TxRow extends StatelessWidget {
  final Map<String, String> tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx['type'] == 'credit';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isCredit ? AppColors.success : AppColors.error).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(tx['emoji']!, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx['title']!, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(tx['subtitle']!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            tx['amount']!,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isCredit ? AppColors.success : AppColors.error,
            ),
          ),
          Text(tx['date']!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
        ]),
      ]),
    );
  }
}
