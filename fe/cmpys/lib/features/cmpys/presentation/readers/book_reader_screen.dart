import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/ui/app_shell.dart';
import '../../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../data/cmpys_seed.dart';

/// Paginated book-lesson reader. One "page" per [CmpysBook.pages] entry, with
/// a segmented progress bar and a closing "Warren's note" panel.
class CmpysBookReaderScreen extends StatefulWidget {
  const CmpysBookReaderScreen({super.key, required this.book});
  final CmpysBook book;

  @override
  State<CmpysBookReaderScreen> createState() => _CmpysBookReaderScreenState();
}

class _CmpysBookReaderScreenState extends State<CmpysBookReaderScreen> {
  late final PageController _ctl;
  int _page = 0;

  // total = pages.length pages + 1 note page
  int get _total => widget.book.pages.length + 1;

  @override
  void initState() {
    super.initState();
    _ctl = PageController();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _total - 1) {
      _ctl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: AppCurves.easeOut,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_page > 0) {
      _ctl.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: AppCurves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(),
            _progress(),
            Expanded(
              child: PageView.builder(
                controller: _ctl,
                itemCount: _total,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  if (i < widget.book.pages.length) {
                    return _pageBody(widget.book.pages[i], i);
                  }
                  return _notePage();
                },
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.book.title,
                  style: AppTypography.label.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.book.chapter,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ink3,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${(_page + 1).toString().padLeft(2, '0')}/${_total.toString().padLeft(2, '0')}',
            style: AppTypography.kicker,
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: CmpysSegBar(
        total: _total,
        done: _page + 1,
        color: AppColors.green,
        track: AppColors.hair,
        height: 6,
      ),
    );
  }

  Widget _pageBody(String text, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAGE ${(index + 1).toString().padLeft(2, '0')}',
            style: AppTypography.kicker.copyWith(color: AppColors.green),
          ),
          const SizedBox(height: 18),
          Text(
            text,
            style: AppTypography.reading.copyWith(
              fontSize: 19,
              height: 1.65,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notePage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CmpysKicker('${widget.book.via} · ${widget.book.author}',
                color: AppColors.green),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: AppRadii.card,
                border: const Border(
                  left: BorderSide(color: AppColors.green, width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(PhosphorIconsFill.sparkle,
                      color: AppColors.green, size: 18),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      widget.book.note,
                      style: AppTypography.body.copyWith(
                        fontSize: 16,
                        height: 1.6,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 10, 18, AppShell.bottomNavClearance(context)),
      child: Row(
        children: [
          if (_page > 0) ...[
            CmpysButton(
              variant: CmpysBtnVariant.outline,
              size: CmpysBtnSize.md,
              leadingIcon: Icons.chevron_left_rounded,
              onTap: _prev,
              child: const Text('Back'),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: CmpysButton(
              variant: CmpysBtnVariant.primary,
              size: CmpysBtnSize.md,
              full: true,
              trailingIcon: Icons.arrow_forward_rounded,
              onTap: _next,
              child: Text(_page == _total - 1 ? 'Done' : 'Next page'),
            ),
          ),
        ],
      ),
    );
  }
}
