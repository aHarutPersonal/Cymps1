// In-app web view for plan materials that only have an external URL
// (e.g. a book's store page or an article without extracted text).
//
// Laid out as the design's `WebViewer` (`v3/library.jsx`): a URL pill with a
// lock, an ember load hairline, the reading-access banner, the page, and a
// bottom toolbar.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/motion/motion_config.dart';
import '../../../core/ui/v3/v3.dart';
import '../models/plan_models.dart';

class MaterialWebScreen extends StatefulWidget {
  const MaterialWebScreen({
    super.key,
    required this.title,
    required this.url,
    this.sourceDescription,
    this.initialSectionTitle,
    this.access,
    this.openedFrom,
  });

  final String title;
  final String url;

  /// The verified reading source's own scope line ("Chapter 12 excerpt on
  /// the coauthor’s website. Full book not included."), shown in the banner.
  final String? sourceDescription;
  final String? initialSectionTitle;

  /// What the page is; every caller passes it. Null falls back to the host:
  /// a Project Gutenberg page is the original, any other described reading
  /// source is an excerpt, and the rest are web sources.
  final AccessType? access;

  /// Where the page was opened from, e.g. "Mission · Find what the business
  /// really earns". A web page shows "Opened from …" only when this is set;
  /// otherwise it has no banner.
  final String? openedFrom;

  static const urlPillKey = ValueKey('material-web-url-pill');
  static const progressKey = ValueKey('material-web-progress');
  static const bannerKey = ValueKey('material-web-banner');
  static const toolbarKey = ValueKey('material-web-toolbar');

  @override
  State<MaterialWebScreen> createState() => _MaterialWebScreenState();
}

class _MaterialWebScreenState extends State<MaterialWebScreen> {
  /// `NSURLErrorCancelled`.
  static const _cancelledErrorCode = -999;

  WebViewController? _controller;
  late final String? _directUrl = safeDirectMaterialUrl(widget.url);

  /// The page the web view is on; starts at the verified link.
  String? _currentUrl;
  int _progress = 0;

  /// The hairline jumps instead of sweeping back when a new page starts.
  bool _barJumps = false;
  bool _paging = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  double _readingViewportHeight = 0;

  /// Set once a page has finished loading.
  bool _hasLoadedPage = false;

  /// The last page that finished loading.
  String? _lastLoadedUrl;

  /// The first page failed to load, so there is nothing to show. Reload
  /// and the next page start clear it.
  bool _loadFailed = false;

  /// Reload after a failed first load: a plain cover hides the platform's
  /// own error page until the new page finishes or fails again.
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    final directUrl = _directUrl;
    _currentUrl = directUrl;
    if (directUrl == null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              // The platform reports an unknown URL as ''.
              if (url.isNotEmpty) _currentUrl = url;
              _barJumps = true;
              _progress = 0;
              _loadFailed = false;
            });
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() {
                if (url.isNotEmpty) _currentUrl = url;
                _barJumps = false;
                // Not every page reports 100 through onProgress.
                _progress = 100;
                if (!_loadFailed) {
                  _hasLoadedPage = true;
                  _retrying = false;
                  if (url.isNotEmpty) _lastLoadedUrl = url;
                }
              });
            }
            _syncHistory();
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
          // iOS reports a failed main-frame navigation only here, never
          // through onPageFinished.
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            // WebKit's NSURLErrorCancelled: a newer navigation superseded
            // this one, which has not failed. (Android has no -999 code.)
            if (error.errorCode == _cancelledErrorCode) return;
            _recoverFromFailedNavigation();
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && mounted) setState(() => _currentUrl = url);
            _syncHistory();
          },
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _barJumps = p < _progress;
              _progress = p;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(directUrl));
  }

  /// A main-frame navigation failed: finish the hairline and point the pill
  /// back at the page the web view is still showing. When no page has
  /// loaded yet, the screen shows its error state instead of a blank page.
  Future<void> _recoverFromFailedNavigation() async {
    if (!mounted) return;
    setState(() {
      _barJumps = false;
      _progress = 100;
      if (!_hasLoadedPage) _loadFailed = true;
      _retrying = false;
    });
    String? current;
    try {
      current = await _controller?.currentUrl();
    } catch (_) {
      current = null;
    }
    if (!mounted) return;
    setState(() {
      _currentUrl = current != null && current.isNotEmpty
          ? current
          : (_lastLoadedUrl ?? _directUrl);
    });
    _syncHistory();
  }

  Future<void> _syncHistory() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final back = await controller.canGoBack();
      final forward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    } catch (_) {
      // History buttons stay as they were.
    }
  }

  Future<void> _turnPage(int direction) async {
    final controller = _controller;
    if (controller == null || _loadFailed || _paging || _progress < 100) {
      return;
    }
    // Measure the actual page area after the source banner and safe insets.
    // Overlap also keeps text below a publisher’s sticky header readable.
    if (_readingViewportHeight <= 0) return;
    final distance = (_readingViewportHeight * 0.75).round().clamp(1, 10000);
    setState(() => _paging = true);
    try {
      await controller.scrollBy(0, direction * distance);
    } catch (_) {
      if (mounted) {
        showV3Toast(
          context,
          'Could not turn the page. Try again.',
          icon: V3Icons.alert,
          tone: V3ToastTone.warn,
        );
      }
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  /// The next page start resets the hairline; page finished completes it.
  /// Before any page has loaded there is nothing to reload, so the verified
  /// link is requested again.
  void _reload() {
    final controller = _controller;
    final directUrl = _directUrl;
    if (controller == null || directUrl == null) return;
    if (_loadFailed) {
      setState(() {
        _loadFailed = false;
        _retrying = true;
      });
    }
    if (_hasLoadedPage) {
      controller.reload();
    } else {
      controller.loadRequest(Uri.parse(directUrl));
    }
  }

  /// Opens the page the reader is on (else the verified link) in the
  /// system browser.
  Future<void> _openInBrowser() async {
    String? current;
    try {
      current = await _controller?.currentUrl();
    } catch (_) {
      current = null;
    }
    // A page that fails verification opens the verified link instead.
    final target = safeDirectMaterialUrl(current ?? _currentUrl) ?? _directUrl;
    if (target == null) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(target),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      showV3Toast(
        context,
        'Could not open the browser. Try again.',
        icon: V3Icons.alert,
        tone: V3ToastTone.warn,
      );
    }
  }

  /// The banner's subject; see [MaterialWebScreen.access].
  AccessType get _access {
    final explicit = widget.access;
    if (explicit != null) return explicit;
    // PlanRepository.resolveBookReadingSource accepts full texts only from
    // Project Gutenberg; every other described source is an author excerpt.
    final host = Uri.tryParse(
      _directUrl ?? widget.url.trim(),
    )?.host.toLowerCase();
    if (host == 'gutenberg.org' || host == 'www.gutenberg.org') {
      return AccessType.original;
    }
    if (widget.sourceDescription != null) return AccessType.excerpt;
    return AccessType.web;
  }

  Uri? get _shownUri =>
      Uri.tryParse((_currentUrl ?? _directUrl ?? widget.url).trim());

  /// The host the URL pill shows, without a leading "www.".
  String get _host {
    final host = _shownUri?.host ?? '';
    final bare = host.startsWith('www.') ? host.substring(4) : host;
    return bare.isEmpty ? 'source' : bare;
  }

  bool get _loaded => _progress >= 100;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final insets = MediaQuery.paddingOf(context);
    final banner = controller == null || _loadFailed ? null : _banner(insets);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topChrome(context, insets),
          if (controller == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'This resource does not have a verified direct link.',
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      15,
                    ).copyWith(color: AppColors.ink2, height: 1.45),
                  ),
                ),
              ),
            )
          else ...[
            ?banner,
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    // Always in the tree, so covering the page never
                    // remounts the platform view; only the flags toggle.
                    child: IgnorePointer(
                      ignoring: _loadFailed || _retrying,
                      child: ExcludeSemantics(
                        excluding: _loadFailed || _retrying,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _readingViewportHeight = constraints.maxHeight;
                            return WebViewWidget(controller: controller);
                          },
                        ),
                      ),
                    ),
                  ),
                  // The web view stays mounted under the failure, so Reload
                  // loads into it.
                  if (_loadFailed)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.white,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                'Couldn’t load this page.',
                                textAlign: TextAlign.center,
                                style: AppTypography.sans(
                                  15,
                                ).copyWith(color: AppColors.ink2, height: 1.45),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (_retrying)
                    const Positioned.fill(
                      key: Key('web-retry-cover'),
                      child: ColoredBox(color: Colors.white),
                    ),
                ],
              ),
            ),
            _toolbar(insets),
          ],
        ],
      ),
    );
  }

  Widget _topChrome(BuildContext context, EdgeInsets insets) {
    final motion = MotionConfig.enabled(context);
    final hasPage = _controller != null;
    final loading = hasPage && !_loadFailed && !_loaded;
    final sweep = motion && !_barJumps;
    return Container(
      // Only the bar row clears the landscape insets; the hairline runs
      // edge to edge.
      padding: EdgeInsets.only(top: insets.top),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14 + insets.left,
                  right: 14 + insets.right,
                ),
                child: Row(
                  children: [
                    V3IconButton(
                      icon: V3Icons.x,
                      label: 'Close',
                      size: 36,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _urlPill(hasPage: hasPage && !_loadFailed)),
                    const SizedBox(width: 10),
                    if (hasPage)
                      V3IconButton(
                        icon: V3Icons.refresh,
                        label: 'Reload',
                        size: 36,
                        onPressed: _reload,
                      )
                    else
                      const SizedBox(width: 36),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 2.5,
            child: hasPage
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: sweep
                          ? const Duration(milliseconds: 250)
                          : Duration.zero,
                      widthFactor: _progress.clamp(0, 100) / 100,
                      heightFactor: 1,
                      child: AnimatedOpacity(
                        opacity: loading ? 1 : 0,
                        duration: motion
                            ? const Duration(milliseconds: 400)
                            : Duration.zero,
                        child: Container(
                          key: MaterialWebScreen.progressKey,
                          decoration: const BoxDecoration(
                            color: AppColors.ember,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// The host of the page the reader is on, behind a padlock only for https.
  /// An http page and the error state show no lock.
  Widget _urlPill({required bool hasPage}) {
    final secure = hasPage && _shownUri?.scheme.toLowerCase() == 'https';
    return Semantics(
      label: '${widget.title}, $_host',
      excludeSemantics: true,
      child: Container(
        key: MaterialWebScreen.urlPillKey,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (secure) ...[
              const V3Icon(V3Icons.lock, size: 12, color: AppColors.ink3),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                _host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  13.5,
                  FontWeight.w500,
                ).copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Excerpt and original pages always say what they are; a web page says
  /// where it was opened from, or shows no banner.
  Widget? _banner(EdgeInsets insets) {
    final access = _access;
    final isBook =
        access == AccessType.excerpt || access == AccessType.original;
    final String text;
    final Color background;
    final Color foreground;
    final V3Icons icon;
    if (isBook) {
      final copy = accessCopy(access);
      final description = widget.sourceDescription?.trim() ?? '';
      text = description.isNotEmpty ? description : copy.note;
      background = copy.background;
      foreground = copy.color;
      icon = copy.icon;
    } else {
      final from = widget.openedFrom?.trim() ?? '';
      if (from.isEmpty) return null;
      text = 'Opened from $from';
      background = AppColors.paper;
      foreground = AppColors.ink2;
      icon = V3Icons.link;
    }
    return Container(
      key: MaterialWebScreen.bannerKey,
      padding: EdgeInsets.fromLTRB(16 + insets.left, 10, 16 + insets.right, 10),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: V3Icon(icon, size: 15, color: foreground),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.sans(
                12.5,
                FontWeight.w500,
              ).copyWith(color: foreground, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(EdgeInsets insets) {
    final controller = _controller;
    final canPage = controller != null && !_loadFailed && _loaded && !_paging;
    return Container(
      key: MaterialWebScreen.toolbarKey,
      padding: EdgeInsets.only(
        left: insets.left,
        right: insets.right,
        bottom: insets.bottom.clamp(8, 34).toDouble(),
      ),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tool(
              V3Icons.left,
              'Back',
              controller != null && _canGoBack ? controller.goBack : null,
            ),
            _tool(
              V3Icons.right,
              'Forward',
              controller != null && _canGoForward ? controller.goForward : null,
            ),
            _tool(
              V3Icons.up,
              'Previous page',
              canPage ? () => _turnPage(-1) : null,
            ),
            _tool(
              V3Icons.down,
              'Next page',
              canPage ? () => _turnPage(1) : null,
            ),
            _tool(
              V3Icons.external,
              'Open in browser',
              _directUrl == null ? null : _openInBrowser,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tool(V3Icons icon, String label, VoidCallback? onTap) {
    return V3Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: V3Icon(
            icon,
            size: 21,
            color: onTap == null ? AppColors.ink3 : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
