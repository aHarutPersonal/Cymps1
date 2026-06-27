// CMPYS record / achievements data + helpers — ported verbatim from
// record-data.jsx so the dual timeline, classifier, and idol reactions behave
// exactly like the prototype.

import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The five comparison dimensions, as life areas for wins.
// id ≠ label for `habits` (shown as "Discipline").
// ─────────────────────────────────────────────────────────────────────────────

class CmpysDim {
  const CmpysDim({
    required this.id,
    required this.label,
    required this.color,
    required this.tint,
    required this.deep,
  });
  final String id;
  final String label;
  final Color color;
  final Color tint;
  final Color deep;
}

const cmpysDims = <CmpysDim>[
  CmpysDim(
    id: 'capital',
    label: 'Capital',
    color: AppColors.green,
    tint: AppColors.greenSoft,
    deep: AppColors.green2,
  ),
  CmpysDim(
    id: 'knowledge',
    label: 'Knowledge',
    color: AppColors.lilac,
    tint: AppColors.lilacSoft,
    deep: Color(0xFF4C3FD6),
  ),
  CmpysDim(
    id: 'habits',
    label: 'Discipline',
    color: AppColors.ochre,
    tint: AppColors.ochreSoft,
    deep: AppColors.ochre2,
  ),
  CmpysDim(
    id: 'network',
    label: 'Network',
    color: AppColors.blue,
    tint: AppColors.blueSoft,
    deep: Color(0xFF1D5FD6),
  ),
  CmpysDim(
    id: 'clarity',
    label: 'Clarity',
    color: AppColors.pink,
    tint: AppColors.pinkSoft,
    deep: Color(0xFFD63E84),
  ),
];

CmpysDim dimOf(String id) =>
    cmpysDims.firstWhere((d) => d.id == id, orElse: () => cmpysDims[1]);

class CmpysImpact {
  const CmpysImpact(this.v, this.label, this.sub);
  final int v;
  final String label;
  final String sub;
}

const cmpysImpacts = <CmpysImpact>[
  CmpysImpact(1, 'Quiet win', 'A small kept promise'),
  CmpysImpact(2, 'Solid win', 'Real, measurable progress'),
  CmpysImpact(3, 'Big move', 'Changed your trajectory'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Idol ledgers, by age (for the dual timeline)
// ─────────────────────────────────────────────────────────────────────────────

typedef LedgerEntry = ({int age, String text});

const Map<String, List<LedgerEntry>> cmpysIdolLedgers = {
  'buffett': [
    (age: 11, text: 'Bought his first stock — three shares of Cities Service preferred.'),
    (age: 16, text: 'Had saved \$5,000 from paper routes and small ventures — about \$60k today.'),
    (age: 19, text: 'Read The Intelligent Investor. Called it the best book on investing ever written.'),
    (age: 20, text: 'Rejected by Harvard. Found Benjamin Graham at Columbia instead.'),
    (age: 21, text: 'Earned the only A+ Graham ever gave in his security analysis class.'),
    (age: 22, text: 'Worked as a stockbroker in Omaha, teaching a night class on investing.'),
    (age: 23, text: 'Kept writing to Graham with ideas until the answer changed.'),
    (age: 24, text: 'Hired by Graham-Newman in New York — the only job he ever wanted.'),
    (age: 25, text: 'Returned to Omaha and started the Buffett Partnership with \$105,100.'),
    (age: 26, text: 'Net worth: \$174,000. The snowball was rolling.'),
  ],
  'curie': [
    (age: 15, text: 'Graduated secondary school first in her class, with a gold medal.'),
    (age: 18, text: 'Worked as a governess to fund her sister’s studies — a pact they’d honor in turn.'),
    (age: 24, text: 'Arrived in Paris with almost nothing, enrolled at the Sorbonne, lived on bread and tea.'),
    (age: 26, text: 'Finished first in her physics degree — often forgetting to eat while studying.'),
    (age: 28, text: 'Married Pierre Curie; their lab partnership began.'),
  ],
  'jobs': [
    (age: 13, text: 'Cold-called HP’s co-founder for spare parts — and got a summer job.'),
    (age: 17, text: 'Audited a calligraphy course that later shaped the Mac’s typography.'),
    (age: 19, text: 'Worked nights at Atari to fund a pilgrimage to India.'),
    (age: 21, text: 'Co-founded Apple in his parents’ garage with Wozniak.'),
    (age: 25, text: 'Worth over \$100M after Apple’s IPO — and still restless.'),
  ],
  'rockefeller': [
    (age: 16, text: 'Took his first bookkeeping job at 50 cents a day — and tracked every cent in Ledger A.'),
    (age: 20, text: 'Borrowed \$1,000 from his father at 10% to start his first produce firm.'),
    (age: 23, text: 'Bet on oil refining in Cleveland while others chased the drilling boom.'),
    (age: 25, text: 'Bought out his partners and built the refinery that became Standard Oil.'),
  ],
  'rothschild': [
    (age: 13, text: 'Apprenticed at a banking house in Hanover, learning coins and credit.'),
    (age: 20, text: 'Returned to Frankfurt and dealt rare coins to a prince — earning trust, not just profit.'),
    (age: 25, text: 'Became court agent, managing the finances of powerful patrons.'),
  ],
  'musk': [
    (age: 17, text: 'Left South Africa alone for Canada with little money, working odd jobs.'),
    (age: 24, text: 'Dropped out of a Stanford PhD after two days to build Zip2.'),
    (age: 28, text: 'Sold Zip2 for \$307M; put almost everything into the next bet.'),
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// Win model + seed achievements
// ─────────────────────────────────────────────────────────────────────────────

class CmpysWin {
  CmpysWin({
    required this.id,
    required this.title,
    required this.dim,
    required this.age,
    required this.impact,
    required this.source,
    required this.assessed,
    this.note = '',
    this.idolNote,
    this.photo = false,
  });

  final String id;
  final String title;
  final String dim;
  final int age;
  final int impact; // 1..3
  final String source; // manual | auto | chat | milestone | intake
  bool assessed;
  final String note;
  final String? idolNote;
  final bool photo;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dim': dim,
        'age': age,
        'impact': impact,
        'source': source,
        'assessed': assessed,
        'note': note,
        'idolNote': idolNote,
        'photo': photo,
      };

  factory CmpysWin.fromJson(Map<String, dynamic> j) => CmpysWin(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        dim: j['dim'] as String? ?? 'knowledge',
        age: (j['age'] as num?)?.toInt() ?? 24,
        impact: (j['impact'] as num?)?.toInt() ?? 1,
        source: j['source'] as String? ?? 'manual',
        assessed: j['assessed'] as bool? ?? false,
        note: j['note'] as String? ?? '',
        idolNote: j['idolNote'] as String?,
        photo: j['photo'] as bool? ?? false,
      );
}



// ─────────────────────────────────────────────────────────────────────────────
// Idol reactions, classifier, milestone mapping, source meta
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<String>> _winReactions = {
  'capital': [
    'Money you keep is worth more than money you make. This is the right kind of boring.',
    'Every dollar you put to work is an employee that never sleeps. Good hire.',
  ],
  'knowledge': [
    'Knowledge compounds quietly, then all at once. Keep feeding it.',
    'That’s another brick in the library. Nobody can take it from you.',
  ],
  'habits': [
    'Small promises, kept daily — that’s the whole secret. I mean it.',
    'Discipline is choosing what you want most over what you want now. Well chosen.',
  ],
  'network': [
    'Associate with people better than you and you’ll drift in that direction. You just did.',
    'Trust builds at the speed of kept commitments. That was one.',
  ],
  'clarity': [
    'Knowing what you’re trying to do puts you ahead of most people twice your age.',
    'A decision written down is worth ten kept in your head. Good.',
  ],
};

String idolReaction(String dim, String seed) {
  final arr = _winReactions[dim] ?? _winReactions['knowledge']!;
  return arr[seed.length % arr.length];
}

/// Naive keyword classifier — order matters, default = clarity.
String classifyWin(String text) {
  final t = text.toLowerCase();
  final tests = <(String, RegExp)>[
    ('capital', RegExp(r'sav(e|ed|ing)|invest|money|\$|salary|paid|debt|budget|stock|fund')),
    ('habits', RegExp(r'streak|every day|daily|habit|woke|gym|routine|quit|discipline|consisten')),
    ('network', RegExp(r'mentor|met |coffee|reached out|message|friend|boss|team|network|talk')),
    ('clarity', RegExp(r'decid|plan|goal|wrote down|philosophy|direction|clarit|vision')),
    ('knowledge', RegExp(r'read|book|course|learn|stud|finish|chapter|article|class')),
  ];
  for (final (dim, re) in tests) {
    if (re.hasMatch(t)) return dim;
  }
  return 'clarity';
}

const Map<String, String> cmpysMilestoneDim = {
  'm1': 'clarity',
  'm2': 'capital',
  'm3': 'knowledge',
  'm4': 'network',
  'm5': 'habits',
};

class CmpysSourceMeta {
  const CmpysSourceMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const Map<String, CmpysSourceMeta> cmpysSourceMeta = {
  'auto': CmpysSourceMeta('Auto-captured', Icons.auto_awesome_rounded),
  'chat': CmpysSourceMeta('Told to your mentor', Icons.chat_bubble_outline_rounded),
  'milestone': CmpysSourceMeta('Milestone claimed', Icons.check_rounded),
  'intake': CmpysSourceMeta('From your intake', Icons.chat_bubble_outline_rounded),
  'manual': CmpysSourceMeta('Logged by you', Icons.edit_outlined),
};
