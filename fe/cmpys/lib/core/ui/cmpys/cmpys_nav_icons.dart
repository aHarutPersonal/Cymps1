// CMPYS navigation glyphs — the v3 icon set (`IP` in `v3/core.jsx`).
//
// The five tabs use the design's own paths: home, plan, chat, compare and
// user. The earlier hand-traced painter (v2 line icons) is gone; the glyphs
// now render through [V3Icon] so the tab bar, the listening menu and every
// other screen draw the exact same shapes.
//
// The centre tab of the bar shows the mentor's portrait instead of a glyph;
// [CmpysNavGlyph.chat] is the icon used wherever the portrait is not (the
// listening app menu).

import 'package:flutter/material.dart';

import '../v3/icons.dart';

enum CmpysNavGlyph {
  today(V3Icons.home),
  plan(V3Icons.plan),
  chat(V3Icons.chat),
  compare(V3Icons.compare),
  you(V3Icons.user);

  const CmpysNavGlyph(this.icon);

  /// The design icon drawn for this tab.
  final V3Icons icon;
}

class CmpysNavIcon extends StatelessWidget {
  const CmpysNavIcon(
    this.glyph, {
    super.key,
    this.size = 23,
    this.color = const Color(0xFF17151A),
    this.strokeWidth = 1.8,
    this.fill,
  });

  final CmpysNavGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  /// Optional fill under the stroke (the design fills the active tab).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return V3Icon(
      glyph.icon,
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      fill: fill,
    );
  }
}
