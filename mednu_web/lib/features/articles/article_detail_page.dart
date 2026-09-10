import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/responsive.dart';
import 'health_article_service.dart';

class ArticleDetailPage extends StatefulWidget {
  final String articleId;
  const ArticleDetailPage({super.key, required this.articleId});

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  @override
  void initState() {
    super.initState();
    HealthArticleService.incrementViews(widget.articleId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<HealthArticle?>(
        stream: HealthArticleService.streamOne(widget.articleId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final article = snap.data;
          if (article == null) {
            return _NotFound(onBack: () => context.go('/'));
          }
          return _ArticleBody(article: article);
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final VoidCallback onBack;
  const _NotFound({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Article not found', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text("It may have been removed.", style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

class _ArticleBody extends StatelessWidget {
  final HealthArticle article;
  const _ArticleBody({required this.article});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => context.go('/'),
          ),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        article.category,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      article.title,
                      style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.25),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      if (article.author.isNotEmpty) ...[
                        Icon(Icons.person_outline_rounded, size: 15, color: AppColors.textHint),
                        const SizedBox(width: 5),
                        Text(article.author, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 16),
                      ],
                      if (article.readTime.isNotEmpty) ...[
                        Icon(Icons.access_time_rounded, size: 15, color: AppColors.textHint),
                        const SizedBox(width: 5),
                        Text(article.readTime, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 16),
                      ],
                      if (article.createdAt != null) ...[
                        Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textHint),
                        const SizedBox(width: 5),
                        Text(DateFormat('MMM d, yyyy').format(article.createdAt!), style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ]),
                    const SizedBox(height: 28),
                    if (article.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: CachedNetworkImage(
                          imageUrl: article.imageUrl,
                          width: double.infinity,
                          height: 360,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(height: 360, color: AppColors.background),
                          errorWidget: (context, url, error) => Container(height: 360, color: AppColors.background),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 220,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppColors.primary.withValues(alpha: 0.08),
                            AppColors.secondary.withValues(alpha: 0.08),
                          ]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Icon(Icons.health_and_safety_rounded, size: 56, color: AppColors.primary),
                        ),
                      ),
                    const SizedBox(height: 32),
                    if (article.summary.isNotEmpty) ...[
                      Text(
                        article.summary,
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.6),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      article.content.isNotEmpty ? article.content : article.summary,
                      style: GoogleFonts.poppins(fontSize: 15, color: AppColors.textSecondary, height: 1.9),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
