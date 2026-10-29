import '../../../../app/assets.dart';
import '../../data/cmpys_seed.dart';

/// The catalog identity of the one mentor with a portrait video (Warren
/// Buffett in `cmpysIdols`: id `buffett`, bundled portrait `wb`).
/// Suggestions and restored selections that name him resolve to this
/// catalog entry (`cmpysIdolFromSuggestion`, `cmpysIdolFromJson`); a
/// synthesised suggestion whose id happens to read `buffett` has no bundled
/// portrait, so the slug keeps it out.
const String _buffettCatalogId = 'buffett';
const String _buffettCatalogSlug = 'wb';

/// The looping backdrop video for [idol]'s portrait hero
/// (`Portrait withVideo` in the design), or null to keep today's duotone
/// portrait.
///
/// Matched by the stable catalog identity only, never by the display name:
/// only Warren Buffett has a video, and every other mentor (catalog or
/// suggested) keeps the portrait. The video shows a lamp-lit study, not the
/// person.
String? cmpysIdolVideo(CmpysIdol idol) =>
    idol.id == _buffettCatalogId && idol.slug == _buffettCatalogSlug
    ? AppAssets.videoMentorBuffett
    : null;
