import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';

class OrderTrackingScreen extends StatefulWidget {
  /// Passed from MedicineScreen cart checkout.
  /// Shape: {orderId, items: [{id, name, brand, price, count}], total, deliveryBoy: {name, phone, rating, deliveries}}
  final Map<String, dynamic>? orderData;
  const OrderTrackingScreen({super.key, this.orderData});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  Timer? _etaTimer;

  late final String _orderId;
  late final List<Map<String, dynamic>> _orderItems;
  late final int _subtotal;
  late final String _dbName;
  late final String _dbPhone;
  late final double _dbRating;
  late final int _dbDeliveries;
  int _etaMinutes = 35;

  static const _green = Color(0xFF2E7D32);
  static const _orange = Color(0xFFE65100);

  final _steps = [
    {'title': 'Order Placed', 'desc': 'Your order has been placed successfully', 'icon': Icons.check_circle_outline_rounded, 'done': true, 'active': false},
    {'title': 'Order Confirmed', 'desc': 'Pharmacy confirmed your order', 'icon': Icons.store_rounded, 'done': true, 'active': false},
    {'title': 'Preparing Order', 'desc': 'Medicines being packed carefully', 'icon': Icons.inventory_2_rounded, 'done': true, 'active': false},
    {'title': 'Out for Delivery', 'desc': 'Delivery partner is on the way', 'icon': Icons.delivery_dining_rounded, 'done': false, 'active': true},
    {'title': 'Delivered', 'desc': 'Order delivered to your doorstep', 'icon': Icons.home_rounded, 'done': false, 'active': false},
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.orderData ?? {};
    _orderId = d['orderId'] as String? ?? 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    final rawItems = d['items'] as List?;
    _orderItems = rawItems != null
        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : [
            {'name': 'Paracetamol 500mg', 'brand': 'Crocin', 'price': 45, 'count': 2},
            {'name': 'Omeprazole 20mg', 'brand': 'Omez', 'price': 65, 'count': 1},
          ];

    _subtotal = d['total'] as int? ?? _orderItems.fold(0, (s, m) => s + (m['price'] as int) * (m['count'] as int));

    final db = (d['deliveryBoy'] as Map?)?.cast<String, dynamic>() ?? {};
    _dbName = db['name'] as String? ?? 'Ravi Kumar';
    _dbPhone = db['phone'] as String? ?? '+91 98765 43210';
    _dbRating = (db['rating'] as num?)?.toDouble() ?? 4.8;
    _dbDeliveries = db['deliveries'] as int? ?? 532;

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

    _etaTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && _etaMinutes > 1) setState(() => _etaMinutes--);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _etaTimer?.cancel();
    super.dispose();
  }

  Future<void> _openInMaps() async {
    final d = widget.orderData ?? {};
    final addr = (d['deliveryAddress'] as Map?)?.cast<String, dynamic>();
    final addressStr = addr?['address'] as String? ?? '';
    final query = Uri.encodeComponent(
      addressStr.isNotEmpty ? addressStr : 'my location',
    );
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  Future<void> _callDriver() async {
    final digits = _dbPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $_dbPhone'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showSupportChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSupportChat(orderId: _orderId),
    );
  }

  String _eta() {
    final t = DateTime.now().add(Duration(minutes: _etaMinutes));
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $suffix';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final deliveryFee = _subtotal > 499 ? 0 : 30;
    final totalPaid = _subtotal + deliveryFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildLiveCard(),
                const SizedBox(height: 20),
                _buildDeliveryPartner(),
                const SizedBox(height: 20),
                Text('Order Progress', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                _buildProgress(),
                const SizedBox(height: 20),
                Text('Order Items', style: AppTextStyles.h4),
                const SizedBox(height: 12),
                _buildOrderItems(deliveryFee, totalPaid),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar() => SliverAppBar(
    pinned: true,
    expandedHeight: 160,
    leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF1B5E20), _green], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 36),
            const SizedBox(height: 8),
            Text('Track Order', style: AppTextStyles.onPrimaryH2),
            Text('Order ID: $_orderId', style: AppTextStyles.onPrimaryBody),
          ]),
        )),
      ),
    ),
  );

  Widget _buildLiveCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1B5E20), _green], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(children: [
      // Header row
      Row(children: [
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.5 + _pulseCtrl.value * 0.5),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('Live Tracking Active', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.15), borderRadius: BorderRadius.circular(8)),
          child: Text('ETA: $_etaMinutes min', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 14),

      // Address row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          const Expanded(child: Text('Delivering to your saved address', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70))),
          Text('By ${_eta()}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 14),

      // Map placeholder (custom painted)
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 130,
          child: Stack(children: [
            CustomPaint(painter: _MapPainter(), child: const SizedBox.expand()),
            // Destination pin
            Positioned(
              right: 30, top: 15,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 14),
                ),
                Container(width: 2, height: 6, color: Colors.red),
                Container(width: 6, height: 3, decoration: BoxDecoration(color: Colors.red.withValues(alpha:0.4), borderRadius: BorderRadius.circular(3))),
              ]),
            ),
            // Delivery bike marker (animated pulse)
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Positioned(
                left: 40 + _pulseCtrl.value * 5,
                top: 50 + _pulseCtrl.value * 3,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                    child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 18),
                  ),
                  Container(width: 2, height: 6, color: _green),
                  Container(width: 6, height: 3, decoration: BoxDecoration(color: _green.withValues(alpha:0.4), borderRadius: BorderRadius.circular(3))),
                ]),
              ),
            ),
            // Route line
            Positioned.fill(
              child: CustomPaint(painter: _RoutePainter()),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),

      // Open in Maps button
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openInMaps,
          icon: const Icon(Icons.map_rounded, size: 16, color: Colors.white),
          label: const Text('Track on Google Maps', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white54),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Action buttons
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: _callDriver,
          icon: const Icon(Icons.call_rounded, size: 16),
          label: const Text('Call Driver'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _green,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        )),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _showSupportChat(context),
          icon: const Icon(Icons.chat_rounded, size: 16, color: Colors.white),
          label: const Text('Chat', style: TextStyle(color: Colors.white)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white54),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        )),
      ]),
    ]),
  );

  Widget _buildDeliveryPartner() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.divider),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Stack(children: [
        Container(
          width: 54, height: 54,
          decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
        ),
        Positioned(bottom: 0, right: 0, child: Container(
          width: 16, height: 16,
          decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
        )),
      ]),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_dbName, style: AppTextStyles.labelLarge),
        const Text('Delivery Partner', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
          const SizedBox(width: 3),
          Text('$_dbRating  •  $_dbDeliveries deliveries', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.phone_rounded, size: 13, color: _green),
          const SizedBox(width: 4),
          Text(_dbPhone, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
        ]),
      ])),
      Column(children: [
        GestureDetector(
          onTap: _callDriver,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: _green.withValues(alpha:0.1), shape: BoxShape.circle),
            child: const Icon(Icons.call_rounded, color: _green, size: 22),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: _green.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
          child: const Text('On the way', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: _green)),
        ),
      ]),
    ]),
  );

  Widget _buildProgress() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(children: _steps.asMap().entries.map((e) {
      final step = e.value;
      final isLast = e.key == _steps.length - 1;
      final isDone = step['done'] as bool;
      final isActive = step['active'] as bool;

      Widget icon;
      if (isDone) {
        icon = Container(
          width: 38, height: 38,
          decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
          child: Icon(step['icon'] as IconData, size: 18, color: Colors.white),
        );
      } else if (isActive) {
        icon = AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Color.lerp(_orange, const Color(0xFFFF8A65), _pulseCtrl.value),
              shape: BoxShape.circle,
            ),
            child: Icon(step['icon'] as IconData, size: 18, color: Colors.white),
          ),
        );
      } else {
        icon = Container(
          width: 38, height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.border, width: 2)),
          child: Icon(step['icon'] as IconData, size: 18, color: AppColors.textHint),
        );
      }

      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          icon,
          if (!isLast) Container(width: 2, height: 42, color: isDone ? _green : AppColors.border),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              step['title'] as String,
              style: AppTextStyles.labelLarge.copyWith(
                color: isDone ? _green : isActive ? _orange : AppColors.textHint,
              ),
            ),
            const SizedBox(height: 2),
            Text(step['desc'] as String, style: AppTextStyles.bodySmall),
          ]),
        )),
      ]);
    }).toList()),
  );

  Widget _buildOrderItems(int deliveryFee, int totalPaid) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(children: [
      ..._orderItems.asMap().entries.map((e) => Column(children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: _green.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.medication_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.value['name'] as String? ?? '', style: AppTextStyles.labelLarge),
            Text('${e.value['brand'] ?? ''}  •  Qty: ${e.value['count']}', style: AppTextStyles.bodySmall),
          ])),
          Text(
            '₹${(e.value['price'] as int) * (e.value['count'] as int)}',
            style: AppTextStyles.labelLarge.copyWith(color: _green),
          ),
        ]),
        if (e.key < _orderItems.length - 1) const Divider(height: 20),
      ])),
      const Divider(height: 24),
      _SummaryRow('Subtotal', '₹$_subtotal'),
      const SizedBox(height: 6),
      _SummaryRow('Delivery Fee', deliveryFee == 0 ? 'FREE' : '₹$deliveryFee', green: deliveryFee == 0),
      const Divider(height: 20),
      _SummaryRow('Total Paid', '₹$totalPaid', bold: true),
    ]),
  );
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final bool bold, green;
  const _SummaryRow(this.label, this.value, {this.bold = false, this.green = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: bold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium),
    Text(value, style: (bold ? AppTextStyles.labelLarge : AppTextStyles.bodyMedium).copyWith(
      color: green ? const Color(0xFF2E7D32) : null,
    )),
  ]);
}

// ── Order Support Chat ────────────────────────────────────────────────────

class _OrderSupportChat extends StatefulWidget {
  final String orderId;
  const _OrderSupportChat({required this.orderId});

  @override
  State<_OrderSupportChat> createState() => _OrderSupportChatState();
}

class _OrderSupportChatState extends State<_OrderSupportChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  static const _green = Color(0xFF2E7D32);

  String get _chatPath =>
      'order_chats/${widget.orderId}/messages';

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();

    await FirebaseFirestore.instance.collection(_chatPath).add({
      'text': text,
      'senderId': _uid,
      'senderRole': 'patient',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            Container(width: 38, height: 38,
                decoration: BoxDecoration(color: _green.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.support_agent_rounded, color: _green, size: 20)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Order Support', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Order #${widget.orderId}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
            ]),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: AppColors.textHint)),
          ]),
        ),
        const Divider(height: 1),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(_chatPath)
                .orderBy('timestamp', descending: false)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: List.generate(4, (_) => const _ChatBubbleSkeleton()),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 68, height: 68,
                        decoration: BoxDecoration(color: _green.withValues(alpha:0.08), shape: BoxShape.circle),
                        child: const Icon(Icons.support_agent_rounded, color: _green, size: 32)),
                    const SizedBox(height: 12),
                    const Text('Support Chat', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text('Send us a message about your order and our support team will respond shortly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint, height: 1.5)),
                    ),
                  ]),
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final isMe = data['senderId'] == _uid;
                  final text = data['text'] as String? ?? '';
                  final ts = data['timestamp'] as Timestamp?;
                  final time = ts != null
                      ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isMe) ...[
                          Container(width: 30, height: 30,
                              decoration: BoxDecoration(color: _green.withValues(alpha:0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.support_agent_rounded, color: _green, size: 15)),
                          const SizedBox(width: 8),
                        ],
                        Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? _green : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                              ),
                              child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: isMe ? Colors.white : AppColors.textPrimary, height: 1.4)),
                            ),
                            const SizedBox(height: 3),
                            Text(time, style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, color: AppColors.textHint)),
                          ],
                        ),
                        if (isMe) const SizedBox(width: 8),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8, offset: const Offset(0, -2))]),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Type your message...',
                  hintStyle: AppTextStyles.bodySmall,
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(14)),
                child: _sending
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Custom painters ───────────────────────────────────────────────────────

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFFE8F5E9));

    final road = Paint()..color = Colors.white..strokeWidth = 10..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height * 0.45), Offset(size.width, size.height * 0.45), road);
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), road);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.7, size.height), road);

    final road2 = Paint()..color = Colors.white..strokeWidth = 6..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height * 0.7), Offset(size.width, size.height * 0.7), road2);

    final block = Paint()..color = const Color(0xFFDCEDC8)..style = PaintingStyle.fill;
    final rr = const Radius.circular(4);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.04, size.height * 0.05, size.width * 0.28, size.height * 0.35), rr), block);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.38, size.height * 0.05, size.width * 0.28, size.height * 0.35), rr), block);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.74, size.height * 0.05, size.width * 0.22, size.height * 0.35), rr), block);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.04, size.height * 0.50, size.width * 0.28, size.height * 0.45), rr), block);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.38, size.height * 0.75, size.width * 0.28, size.height * 0.20), rr), block);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * 0.74, size.height * 0.75, size.width * 0.22, size.height * 0.20), rr), block);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2E7D32).withValues(alpha:0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.58)
      ..cubicTo(
        size.width * 0.3, size.height * 0.58,
        size.width * 0.3, size.height * 0.25,
        size.width * 0.52, size.height * 0.25,
      )
      ..cubicTo(
        size.width * 0.65, size.height * 0.25,
        size.width * 0.75, size.height * 0.25,
        size.width * 0.82, size.height * 0.22,
      );

    canvas.drawPath(path, paint);

    // Dashed overlay
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha:0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var dist = 0.0;
      while (dist < metric.length) {
        final start = dist;
        final end = (dist + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), dashPaint);
        dist += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppShimmer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(right: 60),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: double.infinity, height: 12, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 160, height: 12, radius: 4),
            ]),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 60),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const SkeletonBox(width: 140, height: 12, radius: 4),
            ),
          ),
        ]),
      ),
    );
  }
}
