// In-app web view for plan materials that only have an external URL
// (e.g. a book's store page or an article without extracted text).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';
import '../models/plan_models.dart';

class MaterialWebScreen extends StatefulWidget {
  const MaterialWebScreen({
    super.key,
    required this.title,
    required this.url,
    this.sourceDescription,
    this.initialSectionTitle,
  });

  final String title;
  final String url;
  final String? sourceDescription;
  final String? initialSectionTitle;

  @override
  State<MaterialWebScreen> createState() => _MaterialWebScreenState();
}

class _MaterialWebScreenState extends State<MaterialWebScreen> {
  WebViewController? _controller;
  int _progress = 0;
  bool _paging = false;
  double _readingViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    final directUrl = safeDirectMaterialUrl(widget.url);
    if (directUrl == null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            final section = widget.initialSectionTitle;
            if (section == null) return;
            // A known author page may place its excerpt below the book overview.
            try {
              await _controller?.runJavaScript("""
              (() => { const label = ${jsonEncode(section)};
                const heading = [...document.querySelectorAll('h1,h2,h3,h4,strong,b')]
                  .find(e => e.textContent.trim().startsWith(label));
                if (heading) heading.scrollIntoView(); })();
              """);
            } catch (_) {
              // The page remains readable from the top if its heading changes.
            }
          },
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        ),
      )
      ..loadRequest(Uri.parse(directUrl));
  }

  Future<void> _turnPage(int direction) async {
    final controller = _controller;
    if (controller == null || _paging || _progress < 100) return;
    // Measure the actual page area after the source banner and safe insets.
    // Overlap also keeps text below a publisher’s sticky header readable.
    if (_readingViewportHeight <= 0) return;
    final distance = (_readingViewportHeight * 0.75).round().clamp(1, 10000);
    setState(() => _paging = true);
    try {
      await controller.scrollBy(0, direction * distance);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not turn the page. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to lesson',
          icon: const Icon(
            Icons.chevron_left_rounded,
            size: 26,
            color: AppColors.ink,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(fontSize: 15),
        ),
        actions: controller == null
            ? null
            : [
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: _progress < 100 || _paging
                      ? null
                      : () => _turnPage(-1),
                ),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: _progress < 100 || _paging
                      ? null
                      : () => _turnPage(1),
                ),
              ],
        bottom: controller != null && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: AppColors.hair,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.green,
                  ),
                ),
              )
            : null,
      ),
      // Reserve space for the floating tab nav so it doesn't cover the page.
      body: Padding(
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        child: controller == null
            ? Center(
                child: Text(
                  'This resource does not have a verified direct link.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium,
                ),
              )
            : Column(
                children: [
                  if (widget.sourceDescription case final description?)
                    Container(
                      width: double.infinity,
                      color: AppColors.greenSoft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        description,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.green2,
                        ),
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _readingViewportHeight = constraints.maxHeight;
                        return WebViewWidget(controller: controller);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
