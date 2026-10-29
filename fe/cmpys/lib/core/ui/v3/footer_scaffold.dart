import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../app/design_tokens.dart';

/// Builds the scrolling body of a [V3FooterScaffold]. [bottomPadding] is the
/// space the body must leave at the end of its content (give it to the scroll
/// view's bottom padding) so the last item can scroll clear of the footer.
typedef V3FooterBodyBuilder =
    Widget Function(BuildContext context, double bottomPadding);

/// A scroll body with a primary-action footer: the pattern behind the design's
/// `Scroll` + absolutely positioned bottom bar (`linear-gradient(transparent,
/// var(--paper) 30%)`).
///
/// - **Keyboard closed:** the [footer] overlays the bottom edge on a paper
///   gradient, with 20 pt above it and 20 pt plus the home-indicator inset
///   below (40 pt on a phone without one). The body runs behind it to the
///   screen edge and receives the measured footer height as `bottomPadding`.
/// - **Keyboard open** (the window's bottom view inset is above zero): the
///   footer drops out of the overlay and sits *below* the body, so the body's
///   viewport ends above the footer and a focused field scrolls into the
///   visible space between the top bar and the footer, never behind the button.
///   The body stays mounted across the switch, so focus, typed text and scroll
///   position survive.
///
/// Place it where the surrounding `Scaffold` resizes for the keyboard (the
/// default, `resizeToAvoidBottomInset`), so its own height already excludes
/// the keyboard. A `Scaffold` also zeroes the view insets it hands its body, so
/// the keyboard is read from the window itself, not from that `MediaQuery`.
/// [topBar] sits above the body in both modes. [background] is the colour the
/// gradient fades into (paper, or night on a dark screen).
class V3FooterScaffold extends StatefulWidget {
  const V3FooterScaffold({
    super.key,
    required this.body,
    required this.footer,
    this.topBar,
    this.background = AppColors.paper,
    this.footerHorizontalPadding = 24,
    this.keyboardBottomPadding = 16,
  });

  /// The scrolling content; see [V3FooterBodyBuilder].
  final V3FooterBodyBuilder body;

  /// Usually a full-width `V3Button`.
  final Widget footer;

  /// Shown above the body (a `V3TopBar`, a progress bar, …).
  final Widget? topBar;

  /// The colour behind the scaffold and the end colour of the footer gradient.
  final Color background;

  /// Side padding around [footer] (a wide-screen gutter, for example).
  final double footerHorizontalPadding;

  /// `bottomPadding` handed to [body] while the keyboard is open, when the
  /// footer is no longer over the content.
  final double keyboardBottomPadding;

  @override
  State<V3FooterScaffold> createState() => _V3FooterScaffoldState();
}

class _V3FooterScaffoldState extends State<V3FooterScaffold>
    with WidgetsBindingObserver {
  double _footerHeight = 0;
  bool _windowKeyboard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _windowKeyboard = _readWindowKeyboard();
  }

  @override
  void didChangeMetrics() {
    final open = _readWindowKeyboard();
    if (open != _windowKeyboard && mounted) {
      setState(() => _windowKeyboard = open);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _readWindowKeyboard() =>
      (View.maybeOf(context)?.viewInsets.bottom ?? 0) > 0;

  void _measured(Size size) {
    if (!mounted || size.height == _footerHeight) return;
    setState(() => _footerHeight = size.height);
  }

  Widget _footerShell(BuildContext context, {required bool keyboardOpen}) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final h = widget.footerHorizontalPadding;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.background.withValues(alpha: 0),
            widget.background,
            widget.background,
          ],
          stops: const [0, 0.3, 1],
        ),
      ),
      child: Padding(
        // The keyboard covers the home indicator, so it needs no room below.
        padding: EdgeInsets.fromLTRB(
          h,
          keyboardOpen ? 12 : 20,
          h,
          keyboardOpen ? 12 : 20 + math.max(20.0, bottomInset),
        ),
        child: widget.footer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen =
        _windowKeyboard || MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomPadding = keyboardOpen
        ? widget.keyboardBottomPadding
        : _footerHeight;
    return ColoredBox(
      color: widget.background,
      child: Column(
        children: [
          if (widget.topBar != null) widget.topBar!,
          Expanded(
            // The body is always the Stack's first child, so it keeps its
            // state (focus, text, scroll offset) when the footer moves.
            child: Stack(
              children: [
                Positioned.fill(child: widget.body(context, bottomPadding)),
                if (!keyboardOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _MeasureSize(
                      onChange: _measured,
                      child: _footerShell(context, keyboardOpen: false),
                    ),
                  ),
              ],
            ),
          ),
          if (keyboardOpen) _footerShell(context, keyboardOpen: true),
        ],
      ),
    );
  }
}

/// Reports its child's size after layout, once per change.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    final measured = size;
    _reported = measured;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
  }
}
