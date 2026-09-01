import 'package:cloud_firestore/cloud_firestore.dart';

class HealthArticle {
  final String id;
  final String title;
  final String category;
  final String author;
  final String readTime;
  final String summary;
  final String content;
  final String imageUrl;
  final int views;
  final bool isFeatured;
  final bool isEnabled;
  final DateTime? createdAt;

  const HealthArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.author,
    required this.readTime,
    required this.summary,
    required this.content,
    required this.imageUrl,
    required this.views,
    required this.isFeatured,
    required this.isEnabled,
    required this.createdAt,
  });

  factory HealthArticle.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    final createdTs = d['createdAt'];
    return HealthArticle(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      category: (d['category'] as String?) ?? 'Heart Health',
      author: (d['author'] as String?) ?? '',
      readTime: (d['readTime'] as String?) ?? '',
      summary: (d['summary'] as String?) ?? '',
      content: (d['content'] as String?) ?? '',
      imageUrl: (d['imageUrl'] as String?) ?? '',
      views: (d['views'] as num?)?.toInt() ?? 0,
      isFeatured: (d['isFeatured'] as bool?) ?? false,
      isEnabled: (d['isEnabled'] as bool?) ?? true,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
    );
  }
}

class HealthArticleService {
  static final _db = FirebaseFirestore.instance;

  static Stream<List<HealthArticle>> stream() => _db
      .collection('health_articles')
      .snapshots()
      .map((s) => s.docs
          .map(HealthArticle.fromFirestore)
          .where((a) => a.isEnabled)
          .toList()
        ..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        }));

  static Future<void> incrementViews(String id) {
    return _db.collection('health_articles').doc(id).update({
      'views': FieldValue.increment(1),
    }).catchError((_) {});
  }
}
