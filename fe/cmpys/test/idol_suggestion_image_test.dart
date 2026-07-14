import 'package:cmpys/core/ui/cmpys/cmpys_primitives.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suggestion image URL survives API mapping and idol persistence', () {
    const url = 'https://upload.wikimedia.org/example.jpg';
    final suggestion = IdolSuggestion.fromJson(const {
      'name': 'Example Mentor',
      'era': '20th century',
      'relevance_summary': 'A relevant mentor.',
      'image_url': url,
    });

    final idol = cmpysIdolFromSuggestion(
      name: suggestion.name,
      era: suggestion.era,
      summary: suggestion.relevanceSummary,
      domains: suggestion.domains,
      imageUrl: suggestion.imageUrl,
    );
    final restored = cmpysIdolFromJson(cmpysIdolToJson(idol));

    expect(suggestion.imageUrl, url);
    expect(idol.imageUrl, url);
    expect(restored.imageUrl, url);
  });

  testWidgets('mentor avatar renders a remote suggestion portrait', (
    tester,
  ) async {
    const url = 'https://upload.wikimedia.org/example.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: CmpysMentorAvatar(slug: '__llm__', initials: 'EM', imageUrl: url),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, url);
  });
}
