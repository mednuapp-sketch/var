import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../articles/health_article_service.dart';

class HealthArticlesSection extends StatelessWidget {
  const HealthArticlesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossCount = isMobile ? 1 : Responsive.isTablet(context) ? 2 : 3;

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: Responsive.sectionPaddingV(context),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.maxContentWidth(context)),
          child: Column(
            children: [
              const SectionHeader(
                tag: 'Health Tips',
                title: 'Stay Informed,\nStay Healthy',
                subtitle: 'Expert-backed health articles written for real people, not doctors.',
              ),
              SizedBox(height: isMobile ? 32 : 48),
              StreamBuilder<List<HealthArticle>>(
                stream: HealthArticleService.stream(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    );
                  }
                  final articles = snap.data!.take(6).toList();
                  if (articles.isEmpty) return const SizedBox.shrink();
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: isMobile ? 2.6 : 1.1,
                    ),
                    itemCount: articles.length,
                    itemBuilder: (context, i) => isMobile
                        ? _ArticleCardHorizontal(article: articles[i])
                        : _ArticleCard(article: articles[i]),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleCard extends StatefulWidget {
  final HealthArticle article;
  const _ArticleCard({required this.article});

  @override
  State<_ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<_ArticleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.go('/article/${a.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: Matrix4.translationValues(0, _hovered ? -6 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _hovered ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
            boxShadow: _hovered
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: a.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: a.imageUrl,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => _ImageFallback(),
                        errorWidget: (context, url, error) => _ImageFallback(),
                      )
                    : _ImageFallback(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          a.category,
                          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        a.title,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(a.readTime, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
                        const Spacer(),
                        Text(
                          'Read More →',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _hovered ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.08), AppColors.secondary.withValues(alpha: 0.08)],
        ),
      ),
      child: const Center(child: Icon(Icons.health_and_safety_rounded, size: 40, color: AppColors.primary)),
    );
  }
}

class _ArticleCardHorizontal extends StatelessWidget {
  final HealthArticle article;
  const _ArticleCardHorizontal({required this.article});

  @override
  Widget build(BuildContext context) {
    final a = article;
    return GestureDetector(
      onTap: () => context.go('/article/${a.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: a.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: a.imageUrl,
                    width: 80,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _HorizontalImageFallback(),
                    errorWidget: (context, url, error) => _HorizontalImageFallback(),
                  )
                : _HorizontalImageFallback(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(a.category, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(a.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Text(a.readTime, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textHint)),
                    const Spacer(),
                    Text('Read More →', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HorizontalImageFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.1), AppColors.secondary.withValues(alpha: 0.1)]),
      ),
      child: const Center(child: Icon(Icons.health_and_safety_rounded, size: 28, color: AppColors.primary)),
    );
  }
}
