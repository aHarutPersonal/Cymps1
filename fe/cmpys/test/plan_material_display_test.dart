import 'package:flutter_test/flutter_test.dart';
import 'package:cmpys/features/plans/models/plan_models.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:cmpys/features/session/models/session_models.dart';

void main() {
  test('PlanMaterial exposes resource-card labels', () {
    final material = PlanMaterial.fromJson({
      'type': 'book',
      'title': 'Deep Work',
      'durationMinutes': 15,
      'reason': 'Build focus rituals.',
    });

    expect(material.kindLabel, 'Book');
    expect(material.metaLabel, '15 min');
    expect(material.displaySubtitle, 'Build focus rituals.');
  });

  test('ContentResource exposes reusable resource-card labels', () {
    final resource = ContentResource.fromJson({
      'id': 'resource-1',
      'kind': 'video',
      'canonicalKey': 'youtube:abc',
      'title': 'Margin of Safety',
      'authorOrCreator': 'Berkshire Hathaway',
      'licenseStatus': 'external_link',
      'durationMinutes': 12,
      'progressPercent': 40,
      'metadataJson': {'unavailable': true},
    });

    expect(resource.kindLabel, 'Video');
    expect(resource.metaLabel, 'Berkshire Hathaway • 12 min');
    expect(resource.isUnavailable, isTrue);
  });

  test('LearningMaterial carries shared resource metadata', () {
    final material = LearningMaterial.fromJson({
      'title': 'Margin of Safety',
      'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'type': 'video',
      'summary': 'A guided learning clip.',
      'content_resource_id': 'resource-video',
      'canonical_key': 'youtube:dQw4w9WgXcQ',
      'license_status': 'external_link',
      'duration_minutes': 12,
    });

    expect(material.contentResourceId, 'resource-video');
    expect(material.canonicalKey, 'youtube:dQw4w9WgXcQ');
    expect(material.licenseStatus, 'external_link');
    expect(material.durationMinutes, 12);
  });
}
