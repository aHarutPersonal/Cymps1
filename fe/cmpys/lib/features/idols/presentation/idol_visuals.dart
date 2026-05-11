import '../../../app/env.dart';
import '../models/idol_models.dart';

const String kPrototypeThinkingAsset =
    'https://media.screensdesign.com/gasset/5ee65af8-5e74-4b21-9765-76f984b984aa.png';

const String kPrototypeMentorAvatar =
    'https://media.screensdesign.com/gasset/d88db46c-1a93-490c-a53d-89378af01266.png';

const String kPrototypeBuffettHero =
    'https://media.screensdesign.com/gasset/e022767a-ab77-4f7e-bd3f-bd53d9f98538.png';

const String kPrototypeDefaultPortrait =
    'https://media.screensdesign.com/gasset/0280f1f7-efd1-4190-bcca-b4418b82feea.png';

String? resolveIdolImageUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;
  final url = rawUrl.trim();
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('/')) {
    final base = Env.apiBaseUrl.replaceFirst('/api/v1', '');
    return '$base$url';
  }
  return url;
}

String idolImageUrlForName(String name, {bool hero = false}) {
  final normalized = name.toLowerCase();
  if (normalized.contains('warren') || normalized.contains('buffett')) {
    return hero ? kPrototypeBuffettHero : kPrototypeDefaultPortrait;
  }
  if (normalized.contains('grace') || normalized.contains('hopper')) {
    return 'https://media.screensdesign.com/gasset/8bc0d95f-2ad3-4d29-af07-4068efc2ed0e.png';
  }
  if (normalized.contains('marcus') || normalized.contains('aurelius')) {
    return 'https://media.screensdesign.com/gasset/c7e9018d-832c-4195-bade-99cb94c8d42c.png';
  }
  if (normalized.contains('steve') || normalized.contains('jobs')) {
    return 'https://media.screensdesign.com/gasset/f0a7591c-2778-42b7-a1d9-2c819473cb20.png';
  }
  return kPrototypeDefaultPortrait;
}

String imageUrlForIdolCandidate(IdolCandidate idol, {bool hero = false}) {
  return resolveIdolImageUrl(idol.avatarThumbUrl) ??
      idolImageUrlForName(idol.name, hero: hero);
}

String idolDomainLabel(IdolCandidate idol) {
  if (idol.domain != null && idol.domain!.trim().isNotEmpty) {
    return idol.domain!.trim();
  }
  if (idol.occupations.isNotEmpty) return idol.occupations.first;
  if (idol.tags.isNotEmpty && idol.tags.first.name != null) {
    return idol.tags.first.name!;
  }
  return 'Strategic Logic';
}

String idolInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  if (parts.first.length >= 2) return parts.first.substring(0, 2).toUpperCase();
  return parts.first.toUpperCase();
}
