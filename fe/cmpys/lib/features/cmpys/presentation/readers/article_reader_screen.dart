import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/app_shell.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../data/cmpys_seed.dart';

/// CMPYS article reader — editorial, white background, generous typography.
class CmpysArticleReaderScreen extends StatefulWidget {
  const CmpysArticleReaderScreen({super.key, required this.reading});
  final CmpysReading reading;

  @override
  State<CmpysArticleReaderScreen> createState() =>
      _CmpysArticleReaderScreenState();
}

class _CmpysArticleReaderScreenState extends State<CmpysArticleReaderScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.paper,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            pinned: false,
            floating: true,
            leading: _circleBtn(
              icon: Icons.chevron_left_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              _circleBtn(
                icon: _saved
                    ? PhosphorIconsFill.bookmarkSimple
                    : PhosphorIconsRegular.bookmarkSimple,
                fg: _saved ? AppColors.green : AppColors.ink,
                onTap: () {
                  setState(() => _saved = !_saved);
                  showCmpysToast(
                    context,
                    _saved ? 'Saved' : 'Removed from saved',
                    icon: _saved
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_border_rounded,
                    tone: _saved ? AppColors.green : AppColors.ink3,
                  );
                },
              ),
              const SizedBox(width: 14),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(22, 6, 22, AppShell.bottomNavClearance(context)),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.reading.tag.toUpperCase(),
                        style: AppTypography.kicker.copyWith(
                          color: AppColors.blue,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${widget.reading.minutes} min read',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink3,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  widget.reading.title,
                  style: AppTypography.h1.copyWith(
                    fontSize: 34,
                    letterSpacing: -0.6,
                    height: 1.06,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'By ${widget.reading.author}',
                  style: AppTypography.captionMedium.copyWith(
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 26),
                for (final block in widget.reading.body) _block(block),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(CmpysReadingBlock b) {
    switch (b.kind) {
      case CmpysReadingBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Text(
            b.text,
            style: AppTypography.h3.copyWith(fontSize: 21, letterSpacing: -0.3),
          ),
        );
      case CmpysReadingBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            b.text,
            style: AppTypography.reading.copyWith(
              fontSize: 17,
              height: 1.6,
              color: AppColors.ink,
            ),
          ),
        );
      case CmpysReadingBlockKind.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 18),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: AppRadii.card,
            border: const Border(
              left: BorderSide(color: AppColors.green, width: 3),
            ),
          ),
          child: Text(
            '"${b.text}"',
            style: AppTypography.readingQuote.copyWith(
              fontSize: 19,
              color: AppColors.ink,
              height: 1.42,
            ),
          ),
        );
    }
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color fg = AppColors.ink,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 0, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hair),
            ),
            child: Icon(icon, color: fg, size: 19),
          ),
        ),
      ),
    );
  }
}
