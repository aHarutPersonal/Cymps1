import 'package:flutter/widgets.dart';

import '../../data/cmpys_seed.dart';

/// The portrait for a mentor, resolved the way `CmpysMentorAvatar` does: the
/// image URL from the API when there is one (a suggestion may also carry it in
/// its slug), else the bundled portrait for the seeded mentors, else null so
/// the v3 avatar and portrait fall back to initials / the night ground.
ImageProvider? cmpysIdolImage(CmpysIdol idol) {
  final explicit = idol.imageUrl?.trim();
  final remote = explicit != null && explicit.isNotEmpty
      ? explicit
      : (idol.slug.startsWith('https://') ? idol.slug : null);
  if (remote != null && remote.isNotEmpty) return NetworkImage(remote);
  final slug = idol.slug.trim();
  if (slug.isEmpty || slug == '__llm__') return null;
  return AssetImage('assets/images/mentors/$slug.png');
}
