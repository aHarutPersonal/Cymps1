// CMPYS record data: the win model, the old → v3 dimension mapping, the
// local-entry rule, the seeded mentors' documented ledgers (the Record's
// fallback timeline), the mentor's canned reactions to a win, and the
// dimension a claimed comparison milestone is filed under.

// ─────────────────────────────────────────────────────────────────────────────
// Dimensions. The record files every win under a v3 dimension id
// (`knowledge`, `practice`, `capital`, `network`, `judgment`; labels and
// tints are `winDims` in core/ui/v3/win_sheet.dart).
// ─────────────────────────────────────────────────────────────────────────────

/// The v3 dimension id for a win's stored dimension. This is the one mapping
/// from the ids older builds stored:
///
/// | Stored | v3 |
/// |---|---|
/// | `knowledge`, `capital`, `network` | unchanged |
/// | `habits` (shown as "Discipline") | `practice` |
/// | `clarity` | `judgment` |
/// | `practice`, `judgment` | unchanged |
/// | `know`, `prac`, `cap`, `net`, `judg` (design prototype) | the full id |
///
/// Case and outer whitespace are ignored. Anything else (or nothing) reads
/// as `knowledge`, the store's own default for a win without a dimension.
String recordDimId(String id) => switch (id.trim().toLowerCase()) {
  'knowledge' || 'know' => 'knowledge',
  'practice' || 'prac' || 'habits' => 'practice',
  'capital' || 'cap' => 'capital',
  'network' || 'net' => 'network',
  'judgment' || 'judg' || 'clarity' => 'judgment',
  _ => 'knowledge',
};

/// Whether a record win is a local entry the learner can delete from the
/// Record: an entry made on this device that has **no server copy**.
///
/// Local: `manual` (the v2 add-win sheet), `chat` and `milestone` (a claimed
/// milestone) wins that are not [CmpysWin.synced].
///
/// Not local:
/// - any [CmpysWin.synced] win: Log a win and Report a win (both saved as a
///   server achievement by `saveReportedWin`), and the tutorial's and the
///   mission's "Add to record" (`auto`). Deleting only the device copy would
///   leave the server's, so the Record deletes such a win only together with
///   its server achievement, when it has a [CmpysWin.serverId].
/// - `auto` ("Recorded from plan completion"), `intake` and any source this
///   build doesn't know, synced or not.
bool recordWinIsLocal(CmpysWin win) =>
    !win.synced && const {'manual', 'chat', 'milestone'}.contains(win.source);

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
// Win model
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
    this.synced = false,
    this.milestoneId,
    this.serverId,
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

  /// The win was also saved to the server as an achievement. It is not a
  /// local entry ([recordWinIsLocal]): the Record deletes it only together
  /// with its server copy, which needs [serverId]. False for wins stored
  /// before this flag existed.
  final bool synced;

  /// The comparison milestone a `milestone` (claim) win claims, so deleting
  /// the claim clears the milestone's claimed state. Null for older claims.
  final String? milestoneId;

  /// The server achievement's id (`POST /achievements` → `id`) for a
  /// [synced] win, so "Delete entry" can delete the server copy too. Null for
  /// device-only wins and for synced wins stored before the id was kept
  /// (those stay non-deletable).
  final String? serverId;

  /// A copy with the given fields replaced (null keeps the current value).
  CmpysWin copyWith({
    String? title,
    String? dim,
    int? age,
    int? impact,
    String? source,
    bool? assessed,
    String? note,
    String? idolNote,
    bool? photo,
    bool? synced,
    String? milestoneId,
    String? serverId,
  }) => CmpysWin(
    id: id,
    title: title ?? this.title,
    dim: dim ?? this.dim,
    age: age ?? this.age,
    impact: impact ?? this.impact,
    source: source ?? this.source,
    assessed: assessed ?? this.assessed,
    note: note ?? this.note,
    idolNote: idolNote ?? this.idolNote,
    photo: photo ?? this.photo,
    synced: synced ?? this.synced,
    milestoneId: milestoneId ?? this.milestoneId,
    serverId: serverId ?? this.serverId,
  );

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
        'synced': synced,
        'milestoneId': milestoneId,
        'serverId': serverId,
      };

  /// Parses a stored win. Every field but the id is read tolerantly (a
  /// wrong type reads as the default), so one odd field never loses the
  /// win; a win without a string id throws ([tryParse] skips it).
  factory CmpysWin.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) => v is String ? v : null;
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('A stored win has no id.');
    }
    return CmpysWin(
      id: id,
      title: text(j['title']) ?? '',
      dim: text(j['dim']) ?? 'knowledge',
      age: j['age'] is num ? (j['age'] as num).toInt() : 24,
      impact: j['impact'] is num ? (j['impact'] as num).toInt() : 1,
      source: text(j['source']) ?? 'manual',
      assessed: j['assessed'] == true,
      note: text(j['note']) ?? '',
      idolNote: text(j['idolNote']),
      photo: j['photo'] == true,
      synced: j['synced'] == true,
      milestoneId: text(j['milestoneId']),
      serverId: text(j['serverId']),
    );
  }

  /// A stored win, or null when it can't be read (not a map, or no id).
  static CmpysWin? tryParse(Object? raw) {
    if (raw is! Map) return null;
    try {
      return CmpysWin.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Idol reactions, milestone mapping
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
  'practice': [
    'Small promises, kept daily — that’s the whole secret. I mean it.',
    'Discipline is choosing what you want most over what you want now. Well chosen.',
  ],
  'network': [
    'Associate with people better than you and you’ll drift in that direction. You just did.',
    'Trust builds at the speed of kept commitments. That was one.',
  ],
  'judgment': [
    'Knowing what you’re trying to do puts you ahead of most people twice your age.',
    'A decision written down is worth ten kept in your head. Good.',
  ],
};

String idolReaction(String dim, String seed) {
  final arr = _winReactions[recordDimId(dim)] ?? _winReactions['knowledge']!;
  return arr[seed.length % arr.length];
}

/// The v3 dimension a claimed comparison milestone is filed under, by its
/// position id, when the Record couldn't match it to a categorised mentor
/// timeline event (the backend's milestones carry no dimension).
const Map<String, String> cmpysMilestoneDim = {
  'm1': 'judgment',
  'm2': 'capital',
  'm3': 'knowledge',
  'm4': 'network',
  'm5': 'practice',
};
