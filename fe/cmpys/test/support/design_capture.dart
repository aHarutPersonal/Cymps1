// Optional local visual QA. Set DESIGN_CAPTURE_DIR and DESIGN_FONT_DIR to
// capture the responsive fixtures with readable substitute fonts, offline.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Test-only asset substitution avoids runtime font downloads.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_assets;

class _CaptureFonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
    for (final family in [
      'Inter',
      'PlayfairDisplay',
      'JetBrainsMono',
      'BricolageGrotesque',
      'PlusJakartaSans',
    ])
      for (final variant in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Italic',
        'BoldItalic',
        'Light',
      ])
        'design-capture/$family-$variant.ttf',
  ];
}

Future<void> prepareDesignCapture() async {
  final fonts = Platform.environment['DESIGN_FONT_DIR'];
  if (fonts == null || Platform.environment['DESIGN_CAPTURE_DIR'] == null) {
    return;
  }
  final regular = await File('$fonts/Roboto-Regular.ttf').readAsBytes();
  font_assets.assetManifest = _CaptureFonts();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final name = utf8.decode(message!.buffer.asUint8List());
        if (name.startsWith('design-capture/')) {
          final familyFont = File('$fonts/${name.split('/').last}');
          if (familyFont.existsSync()) {
            return familyFont.readAsBytesSync().buffer.asByteData();
          }
          return regular.buffer.asByteData();
        }
        final file = File('build/unit_test_assets/$name');
        return file.existsSync()
            ? file.readAsBytesSync().buffer.asByteData()
            : null;
      });
  for (final family in ['Roboto', 'Ahem', 'Plus Jakarta Sans']) {
    await (FontLoader(
      family,
    )..addFont(Future.value(regular.buffer.asByteData()))).load();
  }
  for (final style in ['Regular', 'Fill', 'Bold']) {
    final name = style == 'Regular' ? 'Phosphor' : 'Phosphor-$style';
    final bytes = await File(
      'build/unit_test_assets/packages/phosphor_flutter/lib/fonts/$name.ttf',
    ).readAsBytes();
    await (FontLoader(
      'packages/phosphor_flutter/Phosphor$style',
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
  }
  final icons = await File('$fonts/MaterialIcons-Regular.otf').readAsBytes();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(icons.buffer.asByteData()))).load();

  // Finish filesystem-backed font loading before a widget test enters its
  // fake clock. Otherwise a capture can wait on an unpumped asset future.
  for (final family in [
    'Inter',
    'Playfair Display',
    'JetBrains Mono',
    'Bricolage Grotesque',
    'Plus Jakarta Sans',
  ]) {
    for (final weight in [
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]) {
      GoogleFonts.getFont(family, fontWeight: weight);
    }
    GoogleFonts.getFont(family, fontStyle: FontStyle.italic);
  }
  await GoogleFonts.pendingFonts();
}

const designCaptureKey = ValueKey('design-capture');

Future<void> captureDesign(WidgetTester tester, String name) async {
  final directory = Platform.environment['DESIGN_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() => GoogleFonts.pendingFonts());
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(designCaptureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$slug.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
