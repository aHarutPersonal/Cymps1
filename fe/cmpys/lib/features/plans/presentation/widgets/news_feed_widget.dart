import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/assets.dart';
import '../../../../app/design_tokens.dart';
import '../../../../app/env.dart';
import '../../../../core/ui/cmpys_card.dart';
import '../../../../core/ui/loading_state.dart';

class NewsArticle {
  final String title;
  final String link;
  final String source;
  final String? publishedAt;

  NewsArticle({
    required this.title,
    required this.link,
    required this.source,
    this.publishedAt,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      title: json['title'] ?? '',
      link: json['link'] ?? '',
      source: json['source'] ?? '',
      publishedAt: json['published_at'],
    );
  }
}

class NewsFeedWidget extends StatefulWidget {
  const NewsFeedWidget({
    super.key,
    required this.query,
  });

  final String query;

  @override
  State<NewsFeedWidget> createState() => _NewsFeedWidgetState();
}

class _NewsFeedWidgetState extends State<NewsFeedWidget> {
  List<NewsArticle>? _articles;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: Env.apiBaseUrl));
      // Clean query: remove "Read", "Daily", etc.
      final cleanQuery = widget.query
          .replaceAll(RegExp(r'read|daily|practice|study', caseSensitive: false), '')
          .trim();
          
      final response = await dio.get('/api/v1/tools/news', queryParameters: {
        'query': cleanQuery.isNotEmpty ? cleanQuery : widget.query,
      });

      if (mounted) {
        setState(() {
          _articles = (response.data as List)
              .map((e) => NewsArticle.fromJson(e))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset(
              AppAssets.iconGlobe,
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                AppColors.textPrimary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text('Latest News', style: AppTypography.h4),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        if (_isLoading)
          const LoadingState(message: 'Fetching latest news...')
        else if (_error != null)
           Text('Unable to load news', style: AppTypography.caption.copyWith(color: AppColors.error))
        else if (_articles == null || _articles!.isEmpty)
           Text('No news found', style: AppTypography.caption.copyWith(color: AppColors.textSecondary))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _articles!.map((article) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.s12),
                child: SizedBox(
                  width: 240,
                  height: 140,
                  child: CmpysCard(
                    onTap: () => _launchUrl(article.link),
                    padding: AppSpacing.p12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.source,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            article.title,
                            style: AppTypography.bodySmall.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Row(
                          children: [
                            const Icon(Icons.open_in_new, size: 12, color: AppColors.accent),
                            const SizedBox(width: AppSpacing.s4),
                            Text(
                              'Read Article',
                              style: AppTypography.caption.copyWith(color: AppColors.accent),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }
}
