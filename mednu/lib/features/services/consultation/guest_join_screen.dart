import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

enum _GuestJoinState { redeeming, error, waitingForDoctor, readyToJoin }

/// Landing screen for a family member tapping a guest-join link
/// (mednu://join?a=&t=&exp=) shared from the account holder's appointment
/// screen — see _ShareGuestLinkButton in appointment_screen.dart.
///
/// Unlike every other screen in this app, the person here has no MedNU
/// account: [redeemGuestJoinLink] (functions/index.js) verifies the signed
/// link and hands back a Firebase custom token scoped to exactly this one
/// appointment (via the `guestAppointmentId` claim), which is what lets the
/// rest of this flow — Firestore reads, generateAgoraToken — work at all.
class GuestJoinScreen extends StatefulWidget {
  final String appointmentId;
  final String token;
  final int exp;

  const GuestJoinScreen({
    super.key,
    required this.appointmentId,
    required this.token,
    required this.exp,
  });

  @override
  State<GuestJoinScreen> createState() => _GuestJoinScreenState();
}

class _GuestJoinScreenState extends State<GuestJoinScreen> {
  _GuestJoinState _state = _GuestJoinState.redeeming;
  String _errorMessage = '';
  String _doctorName = '';
  String _doctorSpecialty = '';
  String _date = '';
  String _time = '';
  String? _consultationId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _apptSub;

  @override
  void initState() {
    super.initState();
    _redeem();
  }

  @override
  void dispose() {
    _apptSub?.cancel();
    super.dispose();
  }

  Future<void> _redeem() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('redeemGuestJoinLink')
          .call({
        'appointmentId': widget.appointmentId,
        'token': widget.token,
        'exp': widget.exp,
      });
      final data = (result.data as Map).cast<String, dynamic>();
      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw Exception('Invalid response from server.');
      }

      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      if (!mounted) return;

      setState(() {
        _doctorName = (data['doctorName'] as String?)?.trim() ?? '';
        _doctorSpecialty = data['doctorSpecialty'] as String? ?? '';
        _date = data['date'] as String? ?? '';
        _time = data['time'] as String? ?? '';
        _consultationId = (data['consultationId'] as String?)?.trim();
        _consultationId = (_consultationId?.isEmpty ?? true) ? null : _consultationId;
        _state = _consultationId != null
            ? _GuestJoinState.readyToJoin
            : _GuestJoinState.waitingForDoctor;
      });

      if (_state == _GuestJoinState.waitingForDoctor) {
        _watchAppointment();
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GuestJoinState.error;
        _errorMessage = e.message ?? 'This join link is no longer valid.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _GuestJoinState.error;
        _errorMessage = 'Could not open this link. Please try again.';
      });
    }
  }

  /// Once redeemed, the guest's custom-token session is scoped to this
  /// appointment (Firestore rules: guestAppointmentId == appointmentId), so
  /// this read is allowed even though the guest never logged in normally.
  void _watchAppointment() {
    _apptSub = FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.appointmentId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final cid = (snap.data()?['consultationId'] as String?)?.trim();
      if (cid != null && cid.isNotEmpty) {
        setState(() {
          _consultationId = cid;
          _state = _GuestJoinState.readyToJoin;
        });
      }
    });
  }

  void _joinCall() {
    if (_consultationId == null) return;
    context.pushReplacement(
      AppRoutes.guestVideoCall,
      extra: {
        'appointmentId': widget.appointmentId,
        'consultationId': _consultationId,
        'doctorName': _doctorName,
        'doctorSpecialty': _doctorSpecialty,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0533),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _GuestJoinState.redeeming:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white54),
            SizedBox(height: 20),
            Text('Opening your invitation…',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.white70)),
          ],
        );

      case _GuestJoinState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.link_off_rounded, color: Colors.white54, size: 32),
            ),
            const SizedBox(height: 20),
            const Text('This link can\'t be used',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white60, height: 1.4)),
          ],
        );

      case _GuestJoinState.waitingForDoctor:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _doctorAvatar(),
            const SizedBox(height: 20),
            Text('Consultation with $_doctorTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            if (_scheduleLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_scheduleLine,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white60)),
            ],
            const SizedBox(height: 24),
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
            const SizedBox(height: 14),
            const Text(
              'Your doctor hasn\'t started this consultation yet.\nThis screen will update automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white70, height: 1.5),
            ),
          ],
        );

      case _GuestJoinState.readyToJoin:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _doctorAvatar(),
            const SizedBox(height: 20),
            Text('Consultation with $_doctorTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            if (_scheduleLine.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_scheduleLine,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.white60)),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _joinCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Join call',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        );
    }
  }

  String get _doctorTitle => _doctorName.isEmpty ? 'your doctor' : 'Dr. $_doctorName';

  String get _scheduleLine {
    if (_date.isEmpty && _time.isEmpty) return '';
    return [_date, _time].where((s) => s.isNotEmpty).join(' · ');
  }

  Widget _doctorAvatar() {
    return Container(
      width: 88, height: 88,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
      child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 38),
    );
  }
}
