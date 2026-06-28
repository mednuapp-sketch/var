import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My Wallet',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('Manage your balance and transactions',
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        isMobile
            ? Column(children: [const _BalanceCard(), const SizedBox(height: 16), _WalletActions()])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Expanded(flex: 2, child: _BalanceCard()),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: _WalletActions()),
              ]),
        const SizedBox(height: 28),
        const _TransactionsList(),
      ]),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _uid.isEmpty
          ? null
          : FirebaseFirestore.instance.collection('wallet').doc(_uid).snapshots(),
      builder: (context, snap) {
        final balance = snap.data?.data()?['balance'];
        final balanceStr = balance != null
            ? '₹${(balance as num).toStringAsFixed(2)}'
            : '₹0.00';

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('💰', style: TextStyle(fontSize: 28)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('MedNu Wallet',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Available Balance',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 4),
            snap.connectionState == ConnectionState.waiting
                ? const SizedBox(
                    height: 44,
                    child: Center(
                        child: SizedBox(
                            width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))))
                : Text(balanceStr,
                    style: GoogleFonts.poppins(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1)),
          ]),
        );
      },
    );
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wallet Info',
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Text(
          'Your MedNu wallet balance is credited automatically when you receive referral rewards or cashback. Payments are debited when you book appointments or services.',
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppColors.textSecondary, height: 1.6),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Wallet top-up and withdrawals coming soon.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.info)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream {
    if (_uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('payments')
        .where('userId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Text('Transaction History',
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
        ),
        const Divider(height: 1),
        _uid.isEmpty
            ? _emptyTx()
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) return _emptyTx();
                  return Column(
                    children: docs.asMap().entries.map((entry) {
                      final i = entry.key;
                      final d = entry.value.data();
                      return Column(children: [
                        _TxRow(tx: d),
                        if (i < docs.length - 1)
                          const Divider(height: 1, indent: 72),
                      ]);
                    }).toList(),
                  );
                },
              ),
      ]),
    );
  }

  Widget _emptyTx() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📊', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('No transactions yet',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String? ?? 'payment';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final isCredit = type == 'credit' || type == 'cashback' || type == 'referral';
    final amountStr = isCredit ? '+₹${amount.toStringAsFixed(0)}' : '-₹${amount.toStringAsFixed(0)}';

    final createdAt = tx['createdAt'];
    final dateStr = createdAt is Timestamp ? _formatTs(createdAt) : '';

    final subtitle = tx['doctorId'] != null
        ? 'Appointment payment'
        : _capitalize(type);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (isCredit ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(
              isCredit ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
              color: isCredit ? AppColors.success : AppColors.error,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_capitalize(type),
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(subtitle,
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(amountStr,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isCredit ? AppColors.success : AppColors.error)),
          if (dateStr.isNotEmpty)
            Text(dateStr,
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
        ]),
      ]),
    );
  }
}

String _formatTs(Timestamp ts) {
  final d = ts.toDate();
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month]} ${d.year}';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
