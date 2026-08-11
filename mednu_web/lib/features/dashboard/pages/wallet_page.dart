import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';

String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

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
        const SizedBox(height: 28),
        const _SendRefundPanel(),
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
                child: Text('MedNU Wallet',
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
          'Your MedNU wallet balance is credited automatically when you receive referral rewards or cashback. Payments are debited when you book appointments or services.',
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
            const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
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

// ── Send Refund Panel (Admin) ─────────────────────────────
class _SendRefundPanel extends StatefulWidget {
  const _SendRefundPanel();

  @override
  State<_SendRefundPanel> createState() => _SendRefundPanelState();
}

class _SendRefundPanelState extends State<_SendRefundPanel> {
  final _phoneCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool    _loading      = false;
  String? _error;
  String? _successMsg;

  // Resolved user after lookup
  String? _resolvedUid;
  String? _resolvedName;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupUser() async {
    setState(() { _error = null; _resolvedUid = null; _resolvedName = null; _successMsg = null; });
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a phone number');
      return;
    }
    final normalised = phone.startsWith('+') ? phone : '+91$phone';
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: normalised)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        setState(() { _loading = false; _error = 'No MedNU user found with this phone number.'; });
        return;
      }
      final data = snap.docs.first.data();
      setState(() {
        _loading = false;
        _resolvedUid = snap.docs.first.id;
        _resolvedName = data['name'] as String? ?? normalised;
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Lookup failed: ${e.toString()}'; });
    }
  }

  Future<void> _sendRefund() async {
    final uid    = _resolvedUid;
    final amount = double.tryParse(_amountCtrl.text.trim());
    final reason = _reasonCtrl.text.trim();

    if (uid == null) { setState(() => _error = 'Look up a user first.'); return; }
    if (amount == null || amount <= 0) { setState(() => _error = 'Enter a valid amount.'); return; }
    if (reason.isEmpty) { setState(() => _error = 'Enter a reason for the refund.'); return; }

    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final db      = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      final txRef   = userRef.collection('transactions').doc();

      await db.runTransaction((tx) async {
        final snap    = await tx.get(userRef);
        final current = snap.exists
            ? ((snap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        tx.set(userRef, {'walletBalance': current + amount}, SetOptions(merge: true));
        tx.set(txRef, {
          'title':     'Refund: $reason',
          'amount':    amount,
          'type':      'credit',
          'category':  'refund',
          'description': 'Admin refund — $reason',
          'timestamp': FieldValue.serverTimestamp(),
          'walletType': 'main',
          'issuedBy':  FirebaseAuth.instance.currentUser?.uid ?? 'admin',
        });
      });

      setState(() {
        _loading    = false;
        _successMsg = '₹${NumberFormat('#,##,##0.00').format(amount)} refund sent to $_resolvedName successfully.';
        _resolvedUid   = null;
        _resolvedName  = null;
        _phoneCtrl.clear();
        _amountCtrl.clear();
        _reasonCtrl.clear();
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed: ${e.toString()}'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.replay_rounded, color: Color(0xFF1565C0), size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Send Refund to User',
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('Credit wallet balance as a refund',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ]),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 20),

        // ── Phone lookup ──────────────────────────────────
        Text('User Phone Number', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: '10-digit mobile number',
                hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint),
                prefixText: '+91 ',
                prefixStyle: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              onChanged: (_) => setState(() { _resolvedUid = null; _resolvedName = null; _error = null; }),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _lookupUser,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Look Up', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),

        // ── Resolved user chip ────────────────────────────
        if (_resolvedName != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text('User found: $_resolvedName',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32))),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),

        // ── Amount + Reason ───────────────────────────────
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: _refundFieldWidth(context, 200),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Refund Amount (₹)', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '₹ ',
                    hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ]),
            ),
            SizedBox(
              width: _refundFieldWidth(context, 340),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reason', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonCtrl,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Cancelled appointment, overcharge fix…',
                    hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textHint),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Error / Success ───────────────────────────────
        if (_error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.error))),
            ]),
          ),
        if (_successMsg != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_successMsg!, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF2E7D32)))),
            ]),
          ),

        if (_error != null || _successMsg != null) const SizedBox(height: 16),

        // ── Submit button ─────────────────────────────────
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (_loading || _resolvedUid == null) ? null : _sendRefund,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Send Refund', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
          ),
        ),
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

/// Refund-form fields sit inside a [Wrap], which does not shrink its children.
/// Clamp each field to the viewport so a narrow mobile-web window (<~380px)
/// does not overflow horizontally.
double _refundFieldWidth(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).width - 88;
  return available < preferred ? (available < 160 ? 160 : available) : preferred;
}
