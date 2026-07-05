import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cmpys/features/cmpys/presentation/compare_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';

/// Seeds the store with a long AI verdict, like a real LLM-generated one —
/// the verdict card must preview it without RenderFlex overflow.
class _TestStore extends CmpysStore {
  _TestStore(String md) {
    state = state.copyWith(comparisonMd: md);
  }
}

void main() {
  testWidgets('Compare screen lays out at phone width without overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longVerdict = List.generate(
      30,
      (i) => 'Paragraph $i: truth is the first step toward wisdom, '
          'and your candor reveals both promise and gaps in equal measure.',
    ).join('\n\n');

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint('--- FULL DETAILS ---\n$details');
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cmpysStoreProvider.overrideWith((ref) => _TestStore(longVerdict)),
        ],
        child: const MaterialApp(home: CmpysCompareScreen()),
      ),
    );
    // Let entrance animations and the store's persist debounce settle.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}
