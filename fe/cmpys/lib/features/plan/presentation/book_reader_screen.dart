// In-app reader for a public-domain / summarized book backed by a shared
// content resource. Fetches the resource markdown by id and renders it on the
// CMPYS reading surface. Pushed from a plan item's "book" material.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_markdown.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../data/plan_repository.dart';

class BookReaderScreen extends ConsumerStatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.resourceId,
    required this.fallbackTitle,
  });

  final String resourceId;
  final String fallbackTitle;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  String? _markdown;
  String? _title;
  String? _author;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resource = await ref
          .read(planRepositoryProvider)
          .getContentResource(widget.resourceId);
      if (!mounted) return;
      setState(() {
        _markdown = resource.contentMarkdown;
        _title = resource.title;
        _author = resource.authorOrCreator;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load this book. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_title != null && _title!.trim().isNotEmpty)
        ? _title!
        : widget.fallbackTitle;
    final hasText = _markdown != null && _markdown!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: AppColors.paper,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              floating: true,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hair),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          size: 22, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  22, 6, 22, AppShell.bottomNavClearance(context)),
              sliver: SliverList.list(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.ochreSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'BOOK',
                      style: AppTypography.kicker
                          .copyWith(color: AppColors.ochre2, fontSize: 10.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      style: AppTypography.h1.copyWith(
                          fontSize: 30, letterSpacing: -0.5, height: 1.12)),
                  if (_author != null && _author!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('By $_author',
                        style: AppTypography.captionMedium.copyWith(
                            color: AppColors.ink3,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 24),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 50),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.green),
                          ),
                        ),
                      ),
                    )
                  else if (_error != null)
                    CmpysCardSurface(
                      onTap: _fetch,
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded,
                              size: 18, color: AppColors.ink3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('$_error Tap to retry.',
                                style: AppTypography.caption.copyWith(
                                    color: AppColors.ink2, fontSize: 13.5)),
                          ),
                        ],
                      ),
                    )
                  else if (hasText)
                    CmpysMarkdown(_markdown!)
                  else
                    Text('This book has no readable content yet.',
                        style: AppTypography.body
                            .copyWith(color: AppColors.ink2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
