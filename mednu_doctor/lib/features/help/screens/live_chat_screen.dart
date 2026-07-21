import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/ux_widgets.dart';
import '../../auth/services/doctor_auth_service.dart';

class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _uploading = false;
  String? _doctorName;
  String? _uid;

  // Typing indicator debounce
  DateTime? _lastTyped;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _uid = uid;
    final data = await DoctorAuthService.getProfile(uid);
    _doctorName = data?['name'] as String? ?? 'Doctor';

    // Ensure chat doc exists
    final chatRef = FirebaseFirestore.instance.collection('support_chats').doc(uid);
    final snap = await chatRef.get();
    if (!snap.exists) {
      await chatRef.set({
        'doctorId':      uid,
        'doctorName':    _doctorName,
        'status':        'open',
        'lastMessage':   'Chat started',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByAdmin': 0,
        'unreadByDoctor': 0,
        'createdAt':     FieldValue.serverTimestamp(),
        'doctorTyping':  false,
        'adminTyping':   false,
      });
    } else {
      // Reset unread for doctor on open
      await chatRef.update({'unreadByDoctor': 0});
    }
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    final uid = _uid;
    if (uid == null) return;
    if ((text?.trim().isEmpty ?? true) && imageUrl == null) return;

    setState(() => _sending = true);
    try {
      final msgText = text?.trim() ?? '';
      final batch = FirebaseFirestore.instance.batch();

      final msgRef = FirebaseFirestore.instance
          .collection('support_chats')
          .doc(uid)
          .collection('messages')
          .doc();

      batch.set(msgRef, {
        'senderId':   uid,
        'senderName': _doctorName ?? 'Doctor',
        'senderRole': 'doctor',
        'text':       msgText,
        'imageUrl':   imageUrl,
        'type':       imageUrl != null ? 'image' : 'text',
        'createdAt':  FieldValue.serverTimestamp(),
        'isRead':     false,
      });

      final chatRef = FirebaseFirestore.instance.collection('support_chats').doc(uid);
      batch.update(chatRef, {
        'lastMessage':   imageUrl != null ? '📷 Image' : msgText,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByAdmin': FieldValue.increment(1),
        'doctorTyping':  false,
        'status':        'open',
      });

      await batch.commit();
      _msgCtrl.clear();
      _scrollToBottom();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );
      if (picked == null) return;
      setState(() => _uploading = true);
      final uid = _uid;
      if (uid == null) return;
      final ref = FirebaseStorage.instance
          .ref('chat_attachments/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await _sendMessage(imageUrl: url);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTyping(String value) {
    final uid = _uid;
    if (uid == null) return;
    _lastTyped = DateTime.now();
    FirebaseFirestore.instance
        .collection('support_chats')
        .doc(uid)
        .update({'doctorTyping': value.isNotEmpty});
    if (value.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_lastTyped != null &&
            DateTime.now().difference(_lastTyped!).inSeconds >= 3) {
          FirebaseFirestore.instance
              .collection('support_chats')
              .doc(uid)
              .update({'doctorTyping': false});
        }
      });
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('h:mm a').format(ts.toDate());
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('d MMM yyyy').format(dt);
  }

  @override
  void dispose() {
    // Clear typing indicator on close
    if (_uid != null) {
      FirebaseFirestore.instance
          .collection('support_chats')
          .doc(_uid)
          .update({'doctorTyping': false}).catchError((_) {});
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(uid),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(uid)),
          _buildTypingIndicator(uid),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String uid) {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF880E4F), Color(0xFFC2185B), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MedNU Support',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white),
              ),
              Text(
                '24/7 Live Support',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
      actions: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid.isNotEmpty
              ? FirebaseFirestore.instance
                  .collection('support_chats')
                  .doc(uid)
                  .snapshots()
              : const Stream.empty(),
          builder: (context, snap) {
            final status = snap.data?.data()?['status'] as String? ?? 'open';
            return Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'resolved'
                    ? Colors.white.withValues(alpha:0.15)
                    : AppColors.success.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: status == 'resolved'
                      ? Colors.white30
                      : Colors.white.withValues(alpha:0.4),
                ),
              ),
              child: Text(
                status == 'resolved' ? 'Resolved' : 'Online',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessageList(String uid) {
    if (uid.isEmpty) {
      return const Center(child: Text('Not logged in'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('support_chats')
          .doc(uid)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: List.generate(5, (_) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: SkeletonListTile(),
            )),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        // Mark admin messages as read
        for (final doc in docs) {
          if (doc.data()['senderRole'] == 'admin' &&
              doc.data()['isRead'] == false) {
            doc.reference.update({'isRead': true}).catchError((_) {});
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        String? lastDateHeader;
        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final ts = data['createdAt'] as Timestamp?;
            final dateHeader = ts != null
                ? _formatDateHeader(ts.toDate())
                : null;

            final showHeader =
                dateHeader != null && dateHeader != lastDateHeader;
            if (showHeader) lastDateHeader = dateHeader;

            return Column(
              children: [
                if (showHeader) _buildDateHeader(lastDateHeader!),
                _buildMessageBubble(data, uid),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha:0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.secondary, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Start a Conversation', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'Type your message below to connect with\nour 24/7 support team.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.black54,
                fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> data, String uid) {
    final isDoctor = data['senderRole'] == 'doctor';
    final text = data['text'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String?;
    final ts = data['createdAt'] as Timestamp?;
    final isRead = data['isRead'] as bool? ?? false;

    return Align(
      alignment: isDoctor ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment:
              isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isDoctor)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(
                  data['senderName'] as String? ?? 'Support',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: isDoctor ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isDoctor ? 16 : 4),
                  bottomRight: Radius.circular(isDoctor ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isDoctor ? 16 : 4),
                  bottomRight: Radius.circular(isDoctor ? 4 : 16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null)
                      Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    height: 180,
                                    color: Colors.grey.shade100,
                                    child: const Center(
                                        child: CircularProgressIndicator()),
                                  ),
                      ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Text(
                          text,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: isDoctor ? Colors.white : AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(ts),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              color: isDoctor
                                  ? Colors.white60
                                  : AppColors.textHint,
                            ),
                          ),
                          if (isDoctor) ...[
                            const SizedBox(width: 4),
                            Icon(
                              isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 12,
                              color: isRead
                                  ? Colors.lightBlueAccent
                                  : Colors.white60,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(String uid) {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('support_chats')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final adminTyping = snap.data?.data()?['adminTyping'] as bool? ?? false;
        if (!adminTyping) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(children: [
                  const Text('Support is typing',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.textHint)),
                  const SizedBox(width: 6),
                  _TypingDots(),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Attachment button
          GestureDetector(
            onTap: _uploading ? null : _pickAndSendImage,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _uploading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.attach_file_rounded,
                      color: AppColors.secondary, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _msgCtrl,
                onChanged: _onTyping,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: _sending
                ? null
                : () => _sendMessage(text: _msgCtrl.text),
            child: Container(
              width: 42, height: 42,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
            final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5, height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.textHint.withValues(alpha:opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
