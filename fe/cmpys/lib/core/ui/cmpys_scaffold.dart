import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// App scaffold with consistent background, SafeArea, and padding rules.
class CmpysScaffold extends StatelessWidget {
  const CmpysScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.useSafeArea = true,
    this.useHorizontalPadding = true,
    this.useTopSafeArea = true,
    this.useBottomSafeArea = true,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool useSafeArea;
  final bool useHorizontalPadding;
  final bool useTopSafeArea;
  final bool useBottomSafeArea;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    Widget content = body;

    if (useHorizontalPadding) {
      content = Padding(
        padding: AppSpacing.screenH,
        child: content,
      );
    }

    if (useSafeArea) {
      content = SafeArea(
        top: useTopSafeArea && appBar == null,
        bottom: useBottomSafeArea && bottomNavigationBar == null,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.bg,
      appBar: appBar,
      body: content,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

/// Scrollable scaffold variant.
class CmpysScrollScaffold extends StatelessWidget {
  const CmpysScrollScaffold({
    super.key,
    required this.children,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.useHorizontalPadding = true,
    this.physics,
    this.padding,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool useHorizontalPadding;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = bottomNavigationBar != null ? 0.0 : AppSpacing.s32;

    return CmpysScaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      useHorizontalPadding: false,
      body: SingleChildScrollView(
        physics: physics ?? const BouncingScrollPhysics(),
        padding: padding ??
            EdgeInsets.only(
              left: useHorizontalPadding ? AppSpacing.s24 : 0,
              right: useHorizontalPadding ? AppSpacing.s24 : 0,
              bottom: bottomPadding,
            ),
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        ),
      ),
    );
  }
}
