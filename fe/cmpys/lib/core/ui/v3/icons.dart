import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/design_tokens.dart';

/// The v3 icon set: every `IP` path from `v3/core.jsx`, verbatim, in the
/// design's 24×24 viewBox, plus the filled `play` and `pause` glyphs.
///
/// Stroked icons render with round caps and joins at the [V3Icon] stroke
/// width. Data-driven screens (tab ids, toast icons) can resolve a design key
/// with [fromName], which falls back to [info] like `IP[n] || IP.info`.
enum V3Icons {
  check('M20 6 9 17l-5-5'),
  x('M18 6 6 18M6 6l12 12'),
  left('m15 18-6-6 6-6'),
  right('m9 18 6-6-6-6'),
  down('m6 9 6 6 6-6'),
  up('m18 15-6-6-6 6'),
  arrowR('M5 12h14M13 5l7 7-7 7'),
  arrowL('M19 12H5M11 19l-7-7 7-7'),
  plus('M12 5v14M5 12h14'),
  minus('M5 12h14'),
  search('M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3'),
  home('M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z'),
  plan('M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14'),
  chat('M21 12a8.5 8.5 0 0 1-12.4 7.6L3 21l1.4-5.2A8.5 8.5 0 1 1 21 12z'),
  compare(
    'M9 18A6 6 0 1 0 9 6a6 6 0 0 0 0 12zM15 18a6 6 0 1 0 0-12 6 6 0 0 0 0 12z',
  ),
  user('M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0'),
  book(
    'M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5zM4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5',
  ),
  headphones(
    'M3 18v-6a9 9 0 0 1 18 0v6M21 19a2 2 0 0 1-2 2h-1v-6h3zM3 19a2 2 0 0 0 2 2h1v-6H3z',
  ),
  lock('M7 11V7a5 5 0 0 1 10 0v4M5 11h14v10H5z'),
  unlock('M7 11V7a5 5 0 0 1 9.6-2M5 11h14v10H5z'),
  bulb(
    'M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7c.6.5 1 1.3 1 2.3h6c0-1 .4-1.8 1-2.3A7 7 0 0 0 12 2z',
  ),
  bookmark('M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z'),
  heart(
    'M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z',
  ),
  share('M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M16 6l-4-4-4 4M12 2v13'),
  send('M5 12h14M13 5l7 7-7 7'),
  sparkle(
    'M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9zM19 17l.7 1.8 1.8.7-1.8.7L19 22l-.7-1.8-1.8-.7 1.8-.7z',
  ),
  clock('M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 6v6l4 2'),
  target(
    'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 18a6 6 0 1 0 0-12 6 6 0 0 0 0 12zM12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4z',
  ),
  trophy(
    'M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3',
  ),
  flame(
    'M12 22c4 0 7-3 7-7 0-4-3-6-4-9-1 2-2 3-4 3 0-2-1-4-2-6-1 4-4 7-4 12 0 4 3 7 7 7z',
  ),
  edit('M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z'),
  sliders(
    'M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6',
  ),
  logout('M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9'),
  list('M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01'),
  eye(
    'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  ),
  eyeOff(
    'M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2',
  ),
  refresh('M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5'),
  info('M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 16v-4M12 8h.01'),
  alert('M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 8v4M12 16h.01'),
  external(
    'M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6',
  ),
  video('M2 6h14v12H2zM22 8l-6 4 6 4z'),
  file('M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6'),
  type('M4 7V4h16v3M9 20h6M12 4v16'),
  back15('M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5'),
  fwd15('M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5'),
  mic(
    'M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3zM5 10a7 7 0 0 0 14 0M12 17v5',
  ),
  cap('M22 10 12 5 2 10l10 5 10-5zM6 12v5c3 2 9 2 12 0v-5'),
  layers('m12 2 10 5-10 5L2 7zM2 17l10 5 10-5M2 12l10 5 10-5'),
  moon('M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z'),
  sun(
    'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  ),
  trash('M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6'),
  more('M5 12h.01M12 12h.01M19 12h.01'),
  dots('M12 5h.01M12 12h.01M12 19h.01'),
  note('M4 4h16v12l-4 4H4zM16 20v-4h4'),
  calendar('M3 5h18v16H3zM16 3v4M8 3v4M3 10h18'),
  grid('M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z'),
  flag('M4 22V4M4 4h13l-2 4 2 4H4'),
  mail('M3 5h18v14H3zM3 6l9 7 9-7'),
  key('M15 7a4 4 0 1 0-3.9 4.9L3 20v1h3l1-1v-2h2v-2h2l1.3-1.3A4 4 0 0 0 15 7z'),
  wifiOff(
    'M2 2l20 20M8.5 16.5a5 5 0 0 1 7 0M5 13a10 10 0 0 1 5.2-2.8M19 13a10 10 0 0 0-2.4-1.7M12 20h.01',
  ),
  hint(
    'M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7c.6.5 1 1.3 1 2.3h6c0-1 .4-1.8 1-2.3A7 7 0 0 0 12 2z',
  ),
  quote('M7 7h4v4c0 3-1.5 5-4 6M15 7h4v4c0 3-1.5 5-4 6'),
  history('M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5M12 7v5l3 2'),
  users(
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8',
  ),
  link(
    'M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7',
  ),
  highlight(
    'M9 11l-6 6v3h9l3-3M22 12l-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4',
  ),

  /// Filled play triangle (special-cased in `Icon`; ignores stroke).
  play(null),

  /// Two filled rounded bars (special-cased in `Icon`; ignores stroke).
  pause(null);

  const V3Icons(this.path);

  /// SVG path data in the 24×24 viewBox; null for the filled [play] and
  /// [pause] glyphs, which are drawn from their own shapes.
  final String? path;

  /// The icon for a design key such as `'arrowR'`; unknown or missing keys
  /// fall back to [info].
  static V3Icons fromName(String? name) {
    if (name == null) return V3Icons.info;
    return V3Icons.values.asNameMap()[name] ?? V3Icons.info;
  }
}

/// `Icon` from `v3/core.jsx`: a stroked 24×24 line icon.
///
/// [color] defaults to the ambient [IconTheme] colour (the design's
/// `currentColor`); every v3 control sets that theme to its foreground.
/// [fill] fills the shape under the stroke (the design's `fill`, `none` by
/// default). [play] and [pause] are solid glyphs in [color].
class V3Icon extends StatelessWidget {
  const V3Icon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.8,
    this.fill,
    this.semanticLabel,
  });

  final V3Icons icon;

  /// Rendered width and height (the design's `s`).
  final double size;

  /// Stroke colour (the design's `c`); null uses [IconTheme].
  final Color? color;

  /// Stroke width in viewBox units (the design's `w`).
  final double strokeWidth;

  /// Optional fill under the stroke; null is `fill="none"`.
  final Color? fill;

  /// Announced by screen readers; null keeps the icon decorative.
  final String? semanticLabel;

  /// The SVG document for [icon]. Exposed so tests and tools can check the
  /// exact markup that reaches flutter_svg.
  static String svg(
    V3Icons icon, {
    required Color color,
    double strokeWidth = 1.8,
    Color? fill,
  }) {
    const open =
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
        'viewBox="0 0 24 24">';
    final paint = _paint('fill', color);
    switch (icon) {
      case V3Icons.play:
        return '$open<path d="M7 4.5v15a1 1 0 0 0 1.5.9l12-7.5a1 1 0 0 0 '
            '0-1.7l-12-7.5A1 1 0 0 0 7 4.5z" $paint/></svg>';
      case V3Icons.pause:
        return '$open<rect x="6" y="4" width="4" height="16" rx="1.2" '
            '$paint/><rect x="14" y="4" width="4" height="16" rx="1.2" '
            '$paint/></svg>';
      default:
        final fillAttr = fill == null ? 'fill="none"' : _paint('fill', fill);
        return '$open<path d="${icon.path}" $fillAttr ${_paint('stroke', color)} '
            'stroke-width="$strokeWidth" stroke-linecap="round" '
            'stroke-linejoin="round"/></svg>';
    }
  }

  static String _paint(String attribute, Color color) {
    final argb = color.toARGB32();
    final hex = (argb & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    final alpha = (argb >> 24) & 0xFF;
    if (alpha == 0xFF) return '$attribute="#$hex"';
    return '$attribute="#$hex" $attribute-opacity="${(alpha / 255).toStringAsFixed(3)}"';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? AppColors.ink;
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.string(
        svg(icon, color: resolved, strokeWidth: strokeWidth, fill: fill),
        width: size,
        height: size,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      ),
    );
  }
}
