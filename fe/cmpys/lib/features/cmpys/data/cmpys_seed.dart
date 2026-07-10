// CMPYS design seed data — mirrors data.jsx from the React prototype so the
// Flutter implementation looks identical at first load. Backend wiring can
// progressively replace these with live providers once the design system is
// stable; the field shapes are deliberately the same.

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Idols
// ─────────────────────────────────────────────────────────────────────────────

class CmpysIdol {
  const CmpysIdol({
    required this.id,
    required this.slug,
    required this.name,
    required this.short,
    required this.initials,
    required this.title,
    required this.era,
    required this.field,
    required this.color,
    required this.tint,
    required this.tag,
    required this.blurb,
    required this.quote,
    this.atYourAge,
    this.pillars = const [],
    this.featured = false,
  });

  final String id;
  final String slug; // asset filename without extension
  final String name;
  final String short;
  final String initials;
  final String title;
  final String era;
  final String field;
  final Color color;
  final Color tint;
  final String tag;
  final String blurb;
  final String quote;
  final String? atYourAge;
  final List<String> pillars;
  final bool featured;
}

const cmpysIdols = <CmpysIdol>[
  CmpysIdol(
    id: 'buffett',
    slug: 'wb',
    name: 'Warren Buffett',
    short: 'Buffett',
    initials: 'WB',
    title: 'Investor',
    era: 'b. 1930',
    field: 'Wealth',
    color: AppColors.green,
    tint: AppColors.greenSoft,
    tag: 'The Oracle of Omaha',
    blurb:
        'Built one of history’s great fortunes through patience, reading, and rational temperament — not speed.',
    quote:
        'The stock market is a device for transferring money from the impatient to the patient.',
    atYourAge:
        'At 24, Buffett was managing money for family and friends, reading 600 pages a day, and had saved his first serious capital.',
    pillars: ['Wealth', 'Knowledge', 'Discipline'],
    featured: true,
  ),
  CmpysIdol(
    id: 'curie',
    slug: 'mc',
    name: 'Marie Curie',
    short: 'Curie',
    initials: 'MC',
    title: 'Scientist',
    era: '1867–1934',
    field: 'Science',
    color: AppColors.blue,
    tint: AppColors.blueSoft,
    tag: 'Two-time Nobel laureate',
    blurb:
        'Turned relentless focus and sacrifice into discoveries that reshaped physics and chemistry.',
    quote: 'Nothing in life is to be feared, it is only to be understood.',
  ),
  CmpysIdol(
    id: 'jobs',
    slug: 'sj',
    name: 'Steve Jobs',
    short: 'Jobs',
    initials: 'SJ',
    title: 'Founder',
    era: '1955–2011',
    field: 'Craft',
    color: AppColors.blkInk,
    tint: Color(0xFFE6E6EA),
    tag: 'Reality distortion field',
    blurb:
        'Married taste and technology, and demanded a standard of craft most thought impossible.',
    quote: 'Stay hungry. Stay foolish.',
  ),
  CmpysIdol(
    id: 'rockefeller',
    slug: 'jdr',
    name: 'John D. Rockefeller',
    short: 'Rockefeller',
    initials: 'JR',
    title: 'Industrialist',
    era: '1839–1937',
    field: 'Wealth',
    color: AppColors.ochre,
    tint: AppColors.ochreSoft,
    tag: 'America’s first billionaire',
    blurb:
        'Built Standard Oil into an empire through ruthless discipline and methodical reinvestment.',
    quote:
        'I always tried to turn every disaster into an opportunity.',
  ),
  CmpysIdol(
    id: 'rothschild',
    slug: 'roth',
    name: 'Mayer Rothschild',
    short: 'Rothschild',
    initials: 'MR',
    title: 'Banker',
    era: '1744–1812',
    field: 'Trust',
    color: AppColors.lilac,
    tint: AppColors.lilacSoft,
    tag: 'Founded a financial dynasty',
    blurb:
        'Turned trust between five sons in five capitals into the most powerful private bank of his age.',
    quote:
        'Information is the source of all wealth.',
  ),
  CmpysIdol(
    id: 'musk',
    slug: 'em',
    name: 'Elon Musk',
    short: 'Musk',
    initials: 'EM',
    title: 'Founder',
    era: 'b. 1971',
    field: 'Industry',
    color: AppColors.clay,
    tint: AppColors.claySoft,
    tag: 'First-principles operator',
    blurb:
        'Builds at the intersection of physics, code, and willpower, on timescales few others can sustain.',
    quote: 'When something is important enough, you do it even if the odds are not in your favor.',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Interests, goals — onboarding personalisation
// ─────────────────────────────────────────────────────────────────────────────

const cmpysInterests = <String>[
  'Investing',
  'Reading',
  'Building a startup',
  'Writing',
  'Fitness',
  'Career growth',
  'Public speaking',
  'Productivity',
  'Philosophy',
  'Saving money',
  'Leadership',
  'Learning to code',
  'Negotiation',
  'Mindfulness',
];

class CmpysGoal {
  const CmpysGoal(this.id, this.label, this.sub);
  final String id;
  final String label;
  final String sub;
}

const cmpysGoals = <CmpysGoal>[
  CmpysGoal('wealth', 'Build wealth', 'Save, invest, compound'),
  CmpysGoal('knowledge', 'Learn relentlessly', 'Read & master new fields'),
  CmpysGoal('discipline', 'Build discipline', 'Consistent daily habits'),
  CmpysGoal('career', 'Grow my career', 'Skills, reputation, scope'),
  CmpysGoal('network', 'Expand my network', 'Relationships & mentors'),
  CmpysGoal('clarity', 'Find direction', 'Figure out what matters'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Comparison — you vs Buffett at 24
// ─────────────────────────────────────────────────────────────────────────────

class CmpysDimension {
  const CmpysDimension({
    required this.id,
    required this.label,
    required this.you,
    required this.idol,
    required this.youNote,
    required this.idolNote,
  });
  final String id;
  final String label;
  final int you;
  final int idol;
  final String youNote;
  final String idolNote;
}

class CmpysMilestone {
  const CmpysMilestone(this.id, this.label);
  final String id;
  final String label;
}

class CmpysStrength {
  const CmpysStrength(this.id, this.label);
  final String id;
  final String label;
}

class CmpysComparison {
  const CmpysComparison({
    required this.age,
    required this.idolYear,
    required this.headline,
    required this.summary,
    required this.dimensions,
    required this.milestones,
    required this.strengths,
  });
  final int age;
  final int idolYear;
  final String headline;
  final String summary;
  final List<CmpysDimension> dimensions;
  final List<CmpysMilestone> milestones;
  final List<CmpysStrength> strengths;
}

const cmpysComparison = CmpysComparison(
  age: 24,
  idolYear: 1954,
  headline:
      'At 24, you and Warren are closer than you think — and further than you’d like.',
  summary:
      'Buffett wasn’t a genius stock-picker at your age. He was a relentless reader with a saving habit and a tiny pool of trusted capital. That’s a position you can build deliberately — starting this week.',
  dimensions: [
    CmpysDimension(
      id: 'capital',
      label: 'Capital at work',
      you: 22,
      idol: 70,
      youNote: 'Small savings, mostly idle in a checking account.',
      idolNote: 'Had compounded early earnings into a meaningful personal stake.',
    ),
    CmpysDimension(
      id: 'knowledge',
      label: 'Knowledge base',
      you: 48,
      idol: 88,
      youNote: 'Curious and capable, but reading is sporadic.',
      idolNote: 'Read every investing book in the library — some twice.',
    ),
    CmpysDimension(
      id: 'habits',
      label: 'Daily discipline',
      you: 41,
      idol: 82,
      youNote: 'Good intentions, inconsistent follow-through.',
      idolNote: 'Tracked every dollar and habit with monk-like routine.',
    ),
    CmpysDimension(
      id: 'network',
      label: 'Trusted network',
      you: 35,
      idol: 64,
      youNote: 'A few peers, no mentors managing your growth.',
      idolNote: 'Apprenticed directly under Benjamin Graham.',
    ),
    CmpysDimension(
      id: 'clarity',
      label: 'Strategic clarity',
      you: 52,
      idol: 78,
      youNote: 'You know the direction, not yet the system.',
      idolNote:
          'Had a written philosophy he could state in one paragraph.',
    ),
  ],
  milestones: [
    CmpysMilestone('m1', 'Defined a personal investing philosophy in writing'),
    CmpysMilestone('m2', 'Saved 6 months of expenses as a base'),
    CmpysMilestone('m3', 'Read 20+ books in your core field'),
    CmpysMilestone('m4', 'Found one mentor who reviews your decisions'),
    CmpysMilestone('m5', 'Built a daily reading & review habit'),
  ],
  strengths: [
    CmpysStrength('s1', 'You started ten years earlier than most realize they should'),
    CmpysStrength('s2', 'You have access to information Warren couldn’t dream of'),
    CmpysStrength('s3', 'Your curiosity is already pointed in the right direction'),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Plan — 4 pillars × items
// ─────────────────────────────────────────────────────────────────────────────

enum CmpysItemKind { task, read, video, book }

enum CmpysRepeat { once, daily, weekly }

class CmpysPlanItem {
  const CmpysPlanItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.repeat,
    required this.minutes,
    required this.desc,
    this.tag,
  });
  final String id;
  final String title;
  final CmpysItemKind kind;
  final CmpysRepeat repeat;
  final int minutes;
  final String desc;
  final String? tag;
}

class CmpysPillar {
  const CmpysPillar({
    required this.id,
    required this.title,
    required this.accent,
    required this.kicker,
    required this.why,
    required this.items,
  });
  final String id;
  final String title;
  final Color accent;
  final String kicker;
  final String why;
  final List<CmpysPlanItem> items;
}

class CmpysPlan {
  const CmpysPlan({
    required this.title,
    required this.subtitle,
    required this.durationDays,
    required this.pillars,
  });
  final String title;
  final String subtitle;
  final int durationDays;
  final List<CmpysPillar> pillars;
}

const cmpysPlan = CmpysPlan(
  title: 'The Patient Compounder',
  subtitle: 'A 90-day plan, designed with Warren',
  durationDays: 90,
  pillars: [
    CmpysPillar(
      id: 'p_read',
      title: 'Build the reading engine',
      accent: AppColors.lilac,
      kicker: 'Knowledge',
      why:
          'Warren attributes his edge to reading more than anyone he competes with. We start here because it compounds everything else.',
      items: [
        CmpysPlanItem(
          id: 'r1',
          title: 'Read 25 pages every day',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.daily,
          minutes: 20,
          desc:
              'A non-negotiable daily block. Same time, same place. We are building the habit before the volume.',
        ),
        CmpysPlanItem(
          id: 'r2',
          title: 'How Buffett actually reads',
          kind: CmpysItemKind.read,
          repeat: CmpysRepeat.once,
          minutes: 6,
          tag: 'Article',
          desc:
              'A short field guide to reading for judgment, not for finishing.',
        ),
        CmpysPlanItem(
          id: 'r3',
          title: 'The Intelligent Investor — Ch. 8',
          kind: CmpysItemKind.book,
          repeat: CmpysRepeat.once,
          minutes: 12,
          tag: 'Lesson',
          desc:
              'Mr. Market, in plain language. The single most important chapter Warren ever read.',
        ),
        CmpysPlanItem(
          id: 'r4',
          title: 'Build a “to-learn” list, not a to-do list',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.once,
          minutes: 10,
          desc: 'Capture the questions you want answered. Curiosity, organized.',
        ),
      ],
    ),
    CmpysPillar(
      id: 'p_money',
      title: 'Put capital to work',
      accent: AppColors.green,
      kicker: 'Wealth',
      why:
          'You don’t need to pick stocks yet. You need a system that saves automatically and invests boringly.',
      items: [
        CmpysPlanItem(
          id: 'm1',
          title: 'Automate one transfer to savings',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.once,
          minutes: 15,
          desc: 'Pay yourself first — before you can spend it. Even \$20 builds the muscle.',
        ),
        CmpysPlanItem(
          id: 'm2',
          title: 'Understand compound interest, deeply',
          kind: CmpysItemKind.video,
          repeat: CmpysRepeat.once,
          minutes: 9,
          tag: 'Video',
          desc: 'Watch the eighth wonder of the world do its quiet work.',
        ),
        CmpysPlanItem(
          id: 'm3',
          title: 'Track every dollar for 7 days',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.daily,
          minutes: 5,
          desc: 'Warren tracked everything. Awareness precedes control.',
        ),
        CmpysPlanItem(
          id: 'm4',
          title: 'Your one-paragraph money philosophy',
          kind: CmpysItemKind.read,
          repeat: CmpysRepeat.once,
          minutes: 5,
          tag: 'Article',
          desc: 'Write the rules you’ll live by, so you don’t decide them in a panic.',
        ),
      ],
    ),
    CmpysPillar(
      id: 'p_disc',
      title: 'Forge daily discipline',
      accent: AppColors.clay,
      kicker: 'Discipline',
      why:
          'Temperament beats intellect. Small, kept promises to yourself are the raw material of trust.',
      items: [
        CmpysPlanItem(
          id: 'd1',
          title: 'Morning review — 5 minutes',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.daily,
          minutes: 5,
          desc: 'Name the one thing that would make today a win.',
        ),
        CmpysPlanItem(
          id: 'd2',
          title: 'The inner scorecard',
          kind: CmpysItemKind.book,
          repeat: CmpysRepeat.once,
          minutes: 8,
          tag: 'Lesson',
          desc:
              'Buffett’s test: would you rather be the best lover and thought the worst, or the worst and thought the best?',
        ),
        CmpysPlanItem(
          id: 'd3',
          title: 'Say no to one good opportunity',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.weekly,
          minutes: 5,
          desc:
              '"The difference between successful people and very successful people is that very successful people say no to almost everything."',
        ),
      ],
    ),
    CmpysPillar(
      id: 'p_net',
      title: 'Compound your network',
      accent: AppColors.blue,
      kicker: 'Relationships',
      why:
          'Warren apprenticed under Graham. Find people whose judgment you can borrow.',
      items: [
        CmpysPlanItem(
          id: 'n1',
          title: 'List 3 people whose judgment you trust',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.once,
          minutes: 10,
          desc:
              'These become your informal board. We’ll reach out next.',
        ),
        CmpysPlanItem(
          id: 'n2',
          title: 'How to find a mentor (without being weird)',
          kind: CmpysItemKind.read,
          repeat: CmpysRepeat.once,
          minutes: 7,
          tag: 'Article',
          desc: 'Give before you ask. Be specific. Be brief.',
        ),
        CmpysPlanItem(
          id: 'n3',
          title: 'Send one thoughtful message this week',
          kind: CmpysItemKind.task,
          repeat: CmpysRepeat.weekly,
          minutes: 10,
          desc: 'A real question to someone you admire. Most people never ask.',
        ),
      ],
    ),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Ideas feed (quote cards)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysIdea {
  const CmpysIdea({
    required this.id,
    required this.text,
    required this.author,
    required this.tag,
    required this.tone,
    required this.likes,
    this.comments = const [],
    this.isSourced = false,
    this.isVerified = false,
    this.sourceUrl,
    this.sourceTitle,
    this.sourceReference,
  });
  final String id;
  final String text;
  final String author;
  final String tag;
  final Color tone;
  final int likes;
  final List<({String who, String text})> comments;
  final bool isSourced;
  final bool isVerified;
  final String? sourceUrl;
  final String? sourceTitle;
  final String? sourceReference;
}

const cmpysIdeas = <CmpysIdea>[
  CmpysIdea(
    id: 'i1',
    text:
        'The stock market is a device for transferring money from the impatient to the patient.',
    author: 'Warren Buffett',
    tag: 'Investing',
    tone: AppColors.green,
    likes: 1284,
    comments: [
      (who: 'Dana K.', text: 'Read this the morning I almost panic-sold. Held instead.'),
      (who: 'Marcus', text: 'Patience is a position.'),
    ],
  ),
  CmpysIdea(
    id: 'i2',
    text:
        'Someone is sitting in the shade today because someone planted a tree a long time ago.',
    author: 'Warren Buffett',
    tag: 'Patience',
    tone: AppColors.lilac,
    likes: 980,
    comments: [
      (who: 'Priya', text: 'Planting my tree this week 🌱'),
    ],
  ),
  CmpysIdea(
    id: 'i3',
    text: 'Risk comes from not knowing what you are doing.',
    author: 'Warren Buffett',
    tag: 'Investing',
    tone: AppColors.blue,
    likes: 760,
  ),
  CmpysIdea(
    id: 'i4',
    text: 'An investment in knowledge pays the best interest.',
    author: 'Benjamin Franklin',
    tag: 'Learning',
    tone: AppColors.clay,
    likes: 1512,
    comments: [
      (who: 'Theo', text: '25 pages a day, day 14. It’s working.'),
    ],
  ),
  CmpysIdea(
    id: 'i5',
    text:
        'The difference between successful people and very successful people is that very successful people say no to almost everything.',
    author: 'Warren Buffett',
    tag: 'Discipline',
    tone: AppColors.pink,
    likes: 1103,
  ),
  CmpysIdea(
    id: 'i6',
    text: 'It takes 20 years to build a reputation and five minutes to ruin it.',
    author: 'Warren Buffett',
    tag: 'Character',
    tone: AppColors.blkInk,
    likes: 640,
  ),
  CmpysIdea(
    id: 'i7',
    text: 'Wealth is the ability to fully experience life.',
    author: 'Henry David Thoreau',
    tag: 'Wealth',
    tone: AppColors.mint,
    likes: 520,
  ),
];

CmpysIdol defaultIdol() => cmpysIdols.first;

/// Serialize an idol for persistence (colors as ARGB ints). Used by the store
/// so an LLM-suggested idol survives an app restart, not just catalog ones.
Map<String, dynamic> cmpysIdolToJson(CmpysIdol i) => {
      'id': i.id,
      'slug': i.slug,
      'name': i.name,
      'short': i.short,
      'initials': i.initials,
      'title': i.title,
      'era': i.era,
      'field': i.field,
      'color': i.color.toARGB32(),
      'tint': i.tint.toARGB32(),
      'tag': i.tag,
      'blurb': i.blurb,
      'quote': i.quote,
      'atYourAge': i.atYourAge,
      'pillars': i.pillars,
    };

CmpysIdol cmpysIdolFromJson(Map<String, dynamic> j) {
  // Prefer the rich catalog entry when the id matches (keeps portrait asset).
  final id = j['id'] as String?;
  if (id != null) {
    final match = cmpysIdols.where((i) => i.id == id);
    if (match.isNotEmpty) return match.first;
  }
  return CmpysIdol(
    id: id ?? 'idol',
    slug: j['slug'] as String? ?? '__llm__',
    name: j['name'] as String? ?? 'Mentor',
    short: j['short'] as String? ?? 'Mentor',
    initials: j['initials'] as String? ?? 'M',
    title: j['title'] as String? ?? 'Mentor',
    era: j['era'] as String? ?? '—',
    field: j['field'] as String? ?? 'Mastery',
    color: Color((j['color'] as num?)?.toInt() ?? AppColors.green.toARGB32()),
    tint: Color((j['tint'] as num?)?.toInt() ?? AppColors.greenSoft.toARGB32()),
    tag: j['tag'] as String? ?? 'Mentor',
    blurb: j['blurb'] as String? ?? '',
    quote: j['quote'] as String? ?? '',
    atYourAge: j['atYourAge'] as String?,
    pillars: (j['pillars'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Idol suggestion — display model for backend LLM suggestions.
// All suggestions come from /sessions/{id}/suggest-idols; there is no
// client-side ranker. If the backend is unreachable, discovery shows an
// error + retry instead of synthetic content.
// ─────────────────────────────────────────────────────────────────────────────

class CmpysIdolSuggestion {
  const CmpysIdolSuggestion({
    required this.idol,
    required this.score,
    required this.reason,
  });
  final CmpysIdol idol;

  /// 0–100 confidence straight from the LLM, shown as the "% fit" badge.
  final int score;

  /// The LLM's relevance summary — shown as the "why we suggested" copy.
  final String reason;
}

/// Builds a renderable [CmpysIdol] from a raw LLM suggestion.
///
/// The suggest-idols endpoint can return *any* historical figure — most won't
/// be in our hand-authored catalog. When the name matches the catalog we reuse
/// its portrait + rich content; otherwise we synthesise a deterministic colour
/// and monogram so the unknown idol still renders on-brand (no portrait asset,
/// so [CmpysMentorAvatar] falls back to initials on the tint).
CmpysIdol cmpysIdolFromSuggestion({
  required String name,
  required String era,
  required String summary,
  required List<String> domains,
}) {
  final match = cmpysIdols
      .where((i) => i.name.toLowerCase().trim() == name.toLowerCase().trim());
  if (match.isNotEmpty) return match.first;

  const palette = <List<Color>>[
    [AppColors.green, AppColors.greenSoft],
    [AppColors.blue, AppColors.blueSoft],
    [AppColors.lilac, AppColors.lilacSoft],
    [AppColors.clay, AppColors.claySoft],
    [AppColors.ochre, AppColors.ochreSoft],
    [AppColors.mint, AppColors.mintSoft],
    [AppColors.pink, AppColors.pinkSoft],
  ];
  final idx =
      name.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length;
  final pair = palette[idx];
  final field = domains.isNotEmpty ? _cap(domains.first) : 'Mastery';
  final cleanSummary = summary.trim().isEmpty
      ? 'A life worth measuring yourself against.'
      : summary.trim();

  return CmpysIdol(
    id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
    slug: '__llm__', // no asset → monogram fallback
    name: name,
    short: name.split(' ').last,
    initials: _initialsFromName(name),
    title: field,
    era: era.trim().isEmpty ? '—' : era,
    field: field,
    color: pair[0],
    tint: pair[1],
    tag: domains.isNotEmpty
        ? domains.map(_cap).take(2).join(' · ')
        : 'Suggested for you',
    blurb: cleanSummary,
    quote: cleanSummary,
    atYourAge: null,
    pillars: domains.map(_cap).take(3).toList(),
  );
}

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Thoughts shown during the brief "LLM is thinking" overlay before discovery
/// renders. Adapts to the user's interests when present.
List<String> cmpysSuggestionThoughts({
  required Set<String> interests,
  String? goalId,
}) {
  final first = interests.isEmpty
      ? 'Reading your answers, one by one…'
      : 'You told me you care about ${_friendlyJoin(interests.take(3))}.';
  return [
    first,
    'Pulling biographies of people who built lives around that.',
    'Filtering for the ones who started where you are now.',
    'Ranking by how well their early years map onto yours.',
    'Three mentors stand out. Showing them in a moment.',
  ];
}

String _friendlyJoin(Iterable<String> items) {
  final list = items.toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return list.first;
  if (list.length == 2) return '${list[0]} and ${list[1]}';
  return '${list.sublist(0, list.length - 1).join(", ")}, and ${list.last}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Long-form readers (article / book lesson / video chapter list)
// ─────────────────────────────────────────────────────────────────────────────

enum CmpysReadingBlockKind { heading, paragraph, quote }

class CmpysReadingBlock {
  const CmpysReadingBlock(this.kind, this.text);
  final CmpysReadingBlockKind kind;
  final String text;
}

class CmpysReading {
  const CmpysReading({
    required this.id,
    required this.title,
    required this.tag,
    required this.minutes,
    required this.author,
    required this.body,
  });
  final String id;
  final String title;
  final String tag;
  final int minutes;
  final String author;
  final List<CmpysReadingBlock> body;
}

const cmpysReadings = <String, CmpysReading>{
  'r2': CmpysReading(
    id: 'r2',
    title: 'How Buffett actually reads',
    tag: 'Article',
    minutes: 6,
    author: 'CMPYS Editorial',
    body: [
      CmpysReadingBlock(
          CmpysReadingBlockKind.heading, 'Reading for judgment, not for finishing'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'Most people read to reach the last page. Warren Buffett reads to change how he thinks. The distinction sounds small. It is everything.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'He estimates he spends 80% of his working day reading. Not skimming — reading. Annual reports, newspapers, biographies, and the same handful of investing books, returned to again and again until the ideas became reflexes.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.quote, 'I just sit in my office and read all day.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.heading, 'Three habits you can borrow today'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'First: read slowly enough to argue with the author. If you never disagree, you’re not reading — you’re absorbing.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'Second: re-read the few things that matter rather than chasing the many that don’t. Depth compounds; breadth distracts.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'Third: keep a notebook of what surprised you. Surprise is the sound of a model updating.'),
      CmpysReadingBlock(
          CmpysReadingBlockKind.paragraph,
          'Start with 25 pages a day. In a year that’s roughly 30 books — more than most of the people you’ll ever compete with.'),
    ],
  ),
  'm4': CmpysReading(
    id: 'm4',
    title: 'Your one-paragraph money philosophy',
    tag: 'Article',
    minutes: 5,
    author: 'CMPYS Editorial',
    body: [
      CmpysReadingBlock(CmpysReadingBlockKind.heading,
          'Decide the rules before you need them'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'In a calm moment, money decisions are easy. In a panic, they’re nearly impossible. The solution is to decide your rules now, in writing, while you’re thinking clearly.'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'Warren can state his entire philosophy in a sentence or two. That clarity is what lets him act when everyone else freezes.'),
      CmpysReadingBlock(CmpysReadingBlockKind.quote,
          'Rule No. 1: Never lose money. Rule No. 2: Never forget Rule No. 1.'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'Write your own paragraph. What will you always do? What will you never do? How much can you lose without losing sleep? Keep it where you’ll see it.'),
    ],
  ),
  'n2': CmpysReading(
    id: 'n2',
    title: 'How to find a mentor (without being weird)',
    tag: 'Article',
    minutes: 7,
    author: 'CMPYS Editorial',
    body: [
      CmpysReadingBlock(CmpysReadingBlockKind.heading, 'Give before you ask'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'The fastest way to lose a potential mentor is to open with a demand on their time. The fastest way to earn one is to be useful first, and specific second.'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'Buffett wrote to Benjamin Graham, took his class, worked for him for free when offered nothing else. He made himself worth mentoring.'),
      CmpysReadingBlock(CmpysReadingBlockKind.heading,
          'A message that actually works'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'Be brief. Reference something specific they made or said. Ask one precise question they can answer in two minutes. Make it effortless to say yes.'),
      CmpysReadingBlock(CmpysReadingBlockKind.paragraph,
          'Then — this is the part people skip — report back what you did with their advice. Nothing earns a second conversation like evidence the first one mattered.'),
    ],
  ),
};

class CmpysBook {
  const CmpysBook({
    required this.id,
    required this.title,
    required this.chapter,
    required this.author,
    required this.via,
    required this.minutes,
    required this.pages,
    required this.note,
  });
  final String id;
  final String title;
  final String chapter;
  final String author;
  final String via;
  final int minutes;
  final List<String> pages;
  final String note;
}

const cmpysBooks = <String, CmpysBook>{
  'r3': CmpysBook(
    id: 'r3',
    title: 'The Intelligent Investor',
    chapter: 'Chapter 8 — The Investor and Market Fluctuations',
    author: 'Benjamin Graham',
    via: 'Annotated by Warren',
    minutes: 12,
    pages: [
      'Imagine that in some private business you own a small share that cost you \$1,000. One of your partners, named Mr. Market, is very obliging indeed.',
      'Every day he tells you what he thinks your interest is worth and offers either to buy you out or to sell you an additional interest on that basis.',
      'Sometimes his idea of value seems plausible and justified. Often, however, Mr. Market lets his enthusiasm or his fears run away with him, and the value he proposes seems a little short of silly.',
      'The intelligent investor is a realist who sells to optimists and buys from pessimists. You are neither right nor wrong because the crowd disagrees with you. You are right because your data and reasoning are right.',
      'The investor who permits himself to be stampeded by the unjustified market declines of his holdings is perversely transforming his basic advantage into a basic disadvantage.',
    ],
    note:
        'Warren read this chapter as a young man and called it the best thing ever written about investing. The lesson is temperament: the market is there to serve you, not instruct you.',
  ),
  'd2': CmpysBook(
    id: 'd2',
    title: 'The Snowball',
    chapter: 'On the Inner Scorecard',
    author: 'Alice Schroeder',
    via: 'On Warren’s life',
    minutes: 8,
    pages: [
      'The big question about how people behave is whether they’ve got an Inner Scorecard or an Outer Scorecard.',
      'It helps if you can be satisfied with how you act, even when the world is keeping score differently.',
      'Warren’s father gave him this: it’s better to be judged by your own standard than to chase the approval of a crowd whose standard keeps moving.',
      'Would you rather be the best lover in the world and known as the worst, or the worst lover and known as the best? An Inner Scorecard person doesn’t hesitate.',
      'Most failures of discipline are really failures of scorekeeping — measuring yourself against the wrong audience.',
    ],
    note:
        'Discipline gets easier when you stop performing for an audience and start keeping your own promises.',
  ),
};

class CmpysVideoInfo {
  const CmpysVideoInfo({
    required this.id,
    required this.title,
    required this.minutes,
    required this.channel,
    required this.desc,
    required this.chapters,
  });
  final String id;
  final String title;
  final int minutes;
  final String channel;
  final String desc;
  final List<String> chapters;
}

const cmpysVideos = <String, CmpysVideoInfo>{
  'm2': CmpysVideoInfo(
    id: 'm2',
    title: 'The eighth wonder: compound interest',
    minutes: 9,
    channel: 'CMPYS Learn',
    desc:
        'A nine-minute walk through the single idea behind every great fortune — including Warren’s.',
    chapters: [
      'Why your intuition is wrong about growth',
      'The snowball, visualized',
      'Time vs. amount: which wins',
      'Starting small, starting now',
    ],
  ),
};

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding draft (collected as the user moves through personalize → intake)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysOnboardingDraft {
  CmpysOnboardingDraft({
    this.name = '',
    this.age = 24,
    Set<String>? interests,
    this.goalId,
    Map<String, String>? intakeAnswers,
  })  : interests = interests ?? <String>{},
        intakeAnswers = intakeAnswers ?? <String, String>{};

  String name;
  int age;
  Set<String> interests;
  String? goalId;
  Map<String, String> intakeAnswers;

  /// Backend agentic-session id, set once discovery creates one. Reused so
  /// re-entering discovery doesn't spawn duplicate sessions, and so a later
  /// select-idol / interview call can target the same session.
  String? sessionId;

  /// LLM-generated results from /generate-results (markdown). The analysis
  /// step streams these in; the plan-gen step waits on [blueprintMd]; both are
  /// persisted into the store at onboarding completion.
  String? comparisonMd;
  String? blueprintMd;

  /// Set when the generate-results stream fails, so the plan-gen step can
  /// surface a retry instead of waiting forever.
  bool resultsFailed = false;

  /// 12-week-plan generation job id from the `plan_job` SSE event. Persisted
  /// into the store at onboarding completion so the app can poll the job and
  /// surface the plan once the Celery worker finishes.
  String? planJobId;
}
