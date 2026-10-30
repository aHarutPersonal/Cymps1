// Native book and video UI flow; paid generation and video playback are fixtures.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test/learning_support_test.dart' as scenarios;

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Support smoke cannot use the network.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    await GoogleFonts.pendingFonts([
      GoogleFonts.instrumentSerif(),
      GoogleFonts.instrumentSerif(fontStyle: FontStyle.italic),
      GoogleFonts.literata(),
      GoogleFonts.playfairDisplay(),
      GoogleFonts.playfairDisplay(fontStyle: FontStyle.italic),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w600),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      for (final weight in [
        FontWeight.w300,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
      ])
        GoogleFonts.jetBrainsMono(fontWeight: weight),
    ]).timeout(const Duration(seconds: 30));
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = _NoNetwork();
  });
  scenarios.main();
}
