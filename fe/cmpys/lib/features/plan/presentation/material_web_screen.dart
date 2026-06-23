// In-app web view for plan materials that only have an external URL
// (e.g. a book's store page or an article without extracted text).

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../core/ui/app_shell.dart';

class MaterialWebScreen extends StatefulWidget {
  const MaterialWebScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<MaterialWebScreen> createState() => _MaterialWebScreenState();
}

class _MaterialWebScreenState extends State<MaterialWebScreen> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 26, color: AppColors.ink),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(fontSize: 15)),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: AppColors.hair,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.green),
                ),
              )
            : null,
      ),
      // Reserve space for the floating tab nav so it doesn't cover the page.
      body: Padding(
        padding: EdgeInsets.only(bottom: AppShell.bottomNavClearance(context)),
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
