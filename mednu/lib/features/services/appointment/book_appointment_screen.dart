import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

// Booking is handled entirely by DoctorProfileScreen.
// This screen exists only so the /appointment/book route doesn't 404.
class BookAppointmentScreen extends StatelessWidget {
  const BookAppointmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go(AppRoutes.doctors);
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
