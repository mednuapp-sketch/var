import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewCategories {
  final double communication;
  final double treatment;
  final double waitTime;
  final double professionalism;
  final double helpfulness;

  const ReviewCategories({
    this.communication = 0,
    this.treatment = 0,
    this.waitTime = 0,
    this.professionalism = 0,
    this.helpfulness = 0,
  });

  Map<String, dynamic> toMap() => {
        'communication': communication,
        'treatment': treatment,
        'waitTime': waitTime,
        'professionalism': professionalism,
        'helpfulness': helpfulness,
      };

  factory ReviewCategories.fromMap(Map<String, dynamic> m) => ReviewCategories(
        communication: (m['communication'] as num?)?.toDouble() ?? 0,
        treatment: (m['treatment'] as num?)?.toDouble() ?? 0,
        waitTime: (m['waitTime'] as num?)?.toDouble() ?? 0,
        professionalism: (m['professionalism'] as num?)?.toDouble() ?? 0,
        helpfulness: (m['helpfulness'] as num?)?.toDouble() ?? 0,
      );
}

class DoctorReview {
  final String id;
  final String doctorId;
  final String patientId;
  final String patientName;
  final String appointmentId;
  final String sourceType; // 'appointment' | 'consultation'
  final double rating;
  final String reviewText;
  final ReviewCategories categories;
  final String consultationType;
  final DateTime createdAt;
  final bool isVerified;
  final bool isFlagged;

  const DoctorReview({
    required this.id,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.appointmentId,
    required this.sourceType,
    required this.rating,
    required this.reviewText,
    required this.categories,
    required this.consultationType,
    required this.createdAt,
    this.isVerified = true,
    this.isFlagged = false,
  });

  Map<String, dynamic> toMap() => {
        'doctorId': doctorId,
        'patientId': patientId,
        'patientName': patientName,
        'appointmentId': appointmentId,
        'sourceType': sourceType,
        'rating': rating,
        'reviewText': reviewText,
        'categories': categories.toMap(),
        'consultationType': consultationType,
        'createdAt': FieldValue.serverTimestamp(),
        'isVerified': true,
        'isFlagged': false,
      };

  factory DoctorReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final ts = d['createdAt'];
    final created = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DoctorReview(
      id: doc.id,
      doctorId: d['doctorId'] as String? ?? '',
      patientId: d['patientId'] as String? ?? '',
      patientName: d['patientName'] as String? ?? 'Patient',
      appointmentId: d['appointmentId'] as String? ?? '',
      sourceType: d['sourceType'] as String? ?? 'appointment',
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      reviewText: d['reviewText'] as String? ?? '',
      categories: d['categories'] != null
          ? ReviewCategories.fromMap(
              Map<String, dynamic>.from(d['categories'] as Map))
          : const ReviewCategories(),
      consultationType: d['consultationType'] as String? ?? 'Video',
      createdAt: created,
      isVerified: d['isVerified'] as bool? ?? true,
      isFlagged: d['isFlagged'] as bool? ?? false,
    );
  }
}

class DoctorRatingSummary {
  final String doctorId;
  final double averageRating;
  final int totalReviews;
  final Map<int, int> ratingDistribution;

  const DoctorRatingSummary({
    required this.doctorId,
    required this.averageRating,
    required this.totalReviews,
    required this.ratingDistribution,
  });

  factory DoctorRatingSummary.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final rawDist = d['ratingDistribution'];
    if (rawDist is Map) {
      rawDist.forEach((k, v) {
        final key = int.tryParse(k.toString());
        if (key != null) dist[key] = (v as num?)?.toInt() ?? 0;
      });
    }
    return DoctorRatingSummary(
      doctorId: doc.id,
      averageRating: (d['averageRating'] as num?)?.toDouble() ?? 0,
      totalReviews: (d['totalReviews'] as num?)?.toInt() ?? 0,
      ratingDistribution: dist,
    );
  }

  factory DoctorRatingSummary.empty(String doctorId) => DoctorRatingSummary(
        doctorId: doctorId,
        averageRating: 0,
        totalReviews: 0,
        ratingDistribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      );
}
