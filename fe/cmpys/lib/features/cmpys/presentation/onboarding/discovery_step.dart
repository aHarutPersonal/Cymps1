import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/design_tokens.dart';
import '../../../../core/network/api_error.dart';
import '../../../../core/ui/v3/v3.dart';
import '../../../session/data/session_repository.dart';
import '../../../session/models/session_models.dart';
import '../../data/cmpys_seed.dart';
import 'idol_preview_step.dart';
import 'mentor_image.dart';

/// Mentor discovery (`v3/onboard2.jsx` Discovery) — LLM-driven, interest-aware.
///
/// On entry, the screen creates a backend agentic session carrying the user's
/// age + interests, then calls the model-backed `/sessions/{id}/suggest-idols`
/// endpoint. While that is in flight a short narration of the match shows. The
/// LLM's `relevance_summary` becomes the "why" copy under the mentor's name.
///
/// There is **no client-side fallback**: if the backend is unreachable the
/// screen shows an explicit error with retry, never synthetic suggestions.
///
/// - the top result is the 330 pt "Best match" portrait card, the rest sit
///   under "ALSO RELEVANT" with 56 pt grey avatars
/// - tapping a card opens the mentor preview with a clip-path expand out of
///   that card ([V3ExpandRoute]); closing it returns here, still loaded
/// - a search that finds nobody offers "Prepare profile", which queues the
///   person through `POST /idols/import`
///
/// [onPick] fires when the user chooses "Begin intake with {mentor}" in the
/// preview.
class CmpysDiscoveryStep extends ConsumerStatefulWidget {
  const CmpysDiscoveryStep({
    super.key,
    required this.onPick,
    required this.interests,
    required this.age,
    this.goalId,
    this.goal = '',
    this.situation = const <String>{},
    this.situationNote = '',
    this.existingSessionId,
    this.onSessionCreated,
  });

  /// The mentor the user chose to begin intake with.
  final ValueChanged<CmpysIdol> onPick;
  final Set<String> interests;
  final int age;
  final String? goalId;

  /// The goal in the user's own words; empty falls back to [goalId]'s label.
  final String goal;

  /// Situation chips and the optional note, sent with the new session.
  final Set<String> situation;
  final String situationNote;
  final String? existingSessionId;
  final ValueChanged<String>? onSessionCreated;

  @override
  ConsumerState<CmpysDiscoveryStep> createState() => _CmpysDiscoveryStepState();
}

/// Where the "Prepare profile" card is.
enum _Import { idle, researching, queued }

class _CmpysDiscoveryStepState extends ConsumerState<CmpysDiscoveryStep> {
  String _query = '';
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  int _searchRevision = 0;
  bool _searching = false;
  String? _searchError;
  List<CmpysIdolSuggestion> _searchResults = [];

  _Import _import = _Import.idle;
  String _importName = '';
  String? _importError;
  double _importProgress = 0;
  Timer? _importTimer;
  int _importRevision = 0;

  /// Names (see [_importKey]) this screen has already queued: retyping one
  /// shows "Queued for review" instead of starting another paid research
  /// job.
  final Set<String> _queuedNames = {};

  /// Requests still running, by name: a second tap on the same name (after
  /// typing away and back) joins the first instead of sending another.
  final Map<String, Future<IdolImportResult>> _importFlights = {};

  static String _importKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  bool _previewing = false;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _importTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchTimer?.cancel();
    final revision = ++_searchRevision;
    _resetImport();
    setState(() {
      _query = value;
      _searchError = null;
      _searchResults = [];
      _searching = value.trim().length >= 2;
    });
    if (!_searching) return;
    _searchTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final rows = await ref
            .read(sessionRepositoryProvider)
            .discoverMentors(value.trim());
        if (!mounted || revision != _searchRevision) return;
        setState(() {
          _searchResults = rows
              .map(
                (m) => CmpysIdolSuggestion(
                  idol: cmpysIdolFromSuggestion(
                    name: m['name'] as String,
                    era: '',
                    summary: (m['description'] as String?) ?? '',
                    domains: ((m['occupations'] as List?) ?? []).cast<String>(),
                    wikidataId: m['externalId'] as String?,
                    imageUrl: m['imageUrl'] as String?,
                  ),
                  score: 0,
                  reason: (m['description'] as String?) ?? 'Name search result',
                ),
              )
              .toList();
          _searching = false;
        });
      } catch (_) {
        if (!mounted || revision != _searchRevision) return;
        setState(() {
          _searching = false;
          _searchError = 'Search could not finish. Try the name again.';
        });
      }
    });
  }

  // ─── Prepare profile (POST /idols/import) ───────────────────────────────

  /// Drop the import card back to its offer. A request still in flight is
  /// ignored when it lands: the user has moved on to another query.
  void _resetImport() {
    _importRevision++;
    _importTimer?.cancel();
    _import = _Import.idle;
    _importError = null;
  }

  Future<void> _prepareProfile() async {
    final name = _query.trim();
    if (name.length < 2 || _import == _Import.researching) return;
    final key = _importKey(name);
    final revision = ++_importRevision;
    if (_queuedNames.contains(key)) {
      setState(() {
        _import = _Import.queued;
        _importName = name;
        _importError = null;
        _importProgress = 1;
      });
      return;
    }
    setState(() {
      _import = _Import.researching;
      _importName = name;
      _importError = null;
      _importProgress = 0.08;
    });
    // The request reports no progress, so the bar only eases towards (never
    // reaches) full while it runs, and completes when the answer arrives.
    _importTimer?.cancel();
    _importTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (!mounted) return;
      setState(() => _importProgress += (0.9 - _importProgress) * 0.22);
    });
    try {
      final flight = _importFlights[key] ??= ref
          .read(sessionRepositoryProvider)
          .importIdol(name)
          .whenComplete(() {
            _importFlights.remove(key);
          });
      final result = await flight;
      // Queued is remembered even if the learner has moved on meanwhile; a
      // failed job never is, so the name can be prepared again.
      if (!result.isPublished && !result.isFailed) _queuedNames.add(key);
      if (!mounted || revision != _importRevision) return;
      _importTimer?.cancel();
      setState(() {
        if (result.isFailed) {
          // Honest: nothing was prepared. The offer comes back for a retry.
          _import = _Import.idle;
          _importError = 'Couldn’t prepare this profile. Try again later.';
        } else if (result.isPublished) {
          // Ready already: it joins the list like any other result.
          _import = _Import.idle;
          _searchResults = [
            CmpysIdolSuggestion(
              idol: cmpysIdolFromSuggestion(
                name: name,
                era: '',
                summary: '',
                domains: const [],
              ),
              score: 0,
              reason: 'Prepared from documented sources.',
            ),
          ];
        } else {
          _import = _Import.queued;
          _importProgress = 1;
        }
      });
    } catch (error) {
      if (!mounted || revision != _importRevision) return;
      _importTimer?.cancel();
      setState(() {
        _import = _Import.idle;
        _importError = _importMessage(error);
      });
    }
  }

  String _importMessage(Object error) {
    if (error is ApiError) {
      final status = error.statusCode;
      // The per-user daily cap on new profiles.
      if (status == 429) {
        return 'You’ve prepared today’s limit of new profiles. Pick a '
            'prepared mentor or try again tomorrow.';
      }
      if (status != null && status >= 400 && status < 500) {
        return 'We couldn’t prepare that profile. Check the name and try again.';
      }
    }
    return 'Couldn’t reach the library. Check your connection and try again.';
  }

  // ─── suggestions ────────────────────────────────────────────────────────

  bool _loading = true;
  String? _error;
  List<CmpysIdolSuggestion> _suggestions = const [];
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.existingSessionId;
    _loadSuggestions();
  }

  /// LLM suggestions via the backend — the only source. Errors surface with a
  /// retry; we never substitute synthetic content.
  Future<void> _loadSuggestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(sessionRepositoryProvider);

      // Reuse an existing session if we already made one this run; else start
      // clean: abandon any half-finished session from a previous run (which
      // would otherwise 409 createSession and push us to the offline ranker),
      // then create a fresh idol-selection session carrying the intake.
      String sessionId;
      if (_sessionId != null) {
        sessionId = _sessionId!;
      } else {
        await repo.abandonCurrentSession();
        final session = await repo.createSession(
          SessionCreateRequest(
            age: widget.age,
            financialStatus: _financialStatusForGoal(widget.goalId),
            interests: widget.interests.toList(),
            goal: widget.goal.trim().isNotEmpty
                ? widget.goal
                : _goalLabelForId(widget.goalId),
            situation: widget.situation.toList(),
            situationNote: widget.situationNote,
          ),
        );
        sessionId = session.id;
        _sessionId = sessionId;
        widget.onSessionCreated?.call(sessionId);
      }

      final llm = await repo.suggestIdols(sessionId);
      if (!mounted) return;

      if (llm.isEmpty) {
        throw StateError('no suggestions returned');
      }

      final mapped = llm.map(_mapSuggestion).toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      setState(() {
        _suggestions = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Couldn’t reach your mentor AI. Check your connection and try again.';
      });
    }
  }

  CmpysIdolSuggestion _mapSuggestion(IdolSuggestion s) {
    final idol = cmpysIdolFromSuggestion(
      name: s.name,
      era: s.era,
      summary: s.relevanceSummary,
      domains: s.domains,
      wikidataId: s.wikidataId,
      imageUrl: s.imageUrl,
    );
    final score = (s.confidence * 100).clamp(0, 99).round();
    final reason = s.relevanceSummary.trim().isEmpty
        ? 'Chosen by your mentor AI as a strong match for your goals.'
        : s.relevanceSummary.trim();
    return CmpysIdolSuggestion(idol: idol, score: score, reason: reason);
  }

  /// Human-readable goal label sent to the backend verbatim, so prompts see
  /// "Build wealth" rather than a lossy financial-status bucket.
  String? _goalLabelForId(String? goalId) {
    if (goalId == null) return null;
    for (final g in cmpysGoals) {
      if (g.id == goalId) return g.label;
    }
    return null;
  }

  String _financialStatusForGoal(String? goalId) {
    switch (goalId) {
      case 'wealth':
        return 'building_wealth';
      case 'career':
        return 'early_career';
      default:
        return 'not_specified';
    }
  }

  List<CmpysIdolSuggestion> get _filtered {
    if (_query.trim().isEmpty) return _suggestions;
    final q = _query.toLowerCase();
    final local = _suggestions
        .where(
          (s) => '${s.idol.name} ${s.idol.title} ${s.idol.field}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
    final names = local.map((s) => s.idol.name.toLowerCase()).toSet();
    return [
      ...local,
      ..._searchResults.where((s) => names.add(s.idol.name.toLowerCase())),
    ];
  }

  // ─── preview (the clip-path expand) ─────────────────────────────────────

  /// Open the mentor preview out of the tapped card. [cardContext] is the
  /// card's own context, so the expand starts exactly at its rect and a close
  /// returns into it. Choosing a mentor hands them to [CmpysDiscoveryStep.onPick]
  /// and removes the preview at once: the flow moves on behind it.
  void _preview(BuildContext cardContext, CmpysIdol idol) {
    if (_previewing) return;
    _previewing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    late final V3ExpandRoute<void> route;
    route = V3ExpandRoute<void>(
      from: V3ExpandRoute.rectOf(cardContext),
      builder: (_) => CmpysIdolPreviewStep(
        idol: idol,
        age: widget.age,
        onBack: () => navigator.pop(),
        onChoose: (chosen) {
          widget.onPick(chosen);
          if (route.isActive) navigator.removeRoute(route);
        },
      ),
    );
    unawaited(navigator.push(route).whenComplete(() => _previewing = false));
  }

  // ─── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: AppTypography.sans(16).copyWith(color: AppColors.ink),
      child: Column(
        children: [
          const V3TopBar(),
          Expanded(
            child: _loading
                ? _thinking()
                : _error != null
                ? _errorView()
                : _discoveryList(),
          ),
        ],
      ),
    );
  }

  double _gutter(double width) => math.max(20.0, (width - 520) / 2);

  // ─── error + retry (no synthetic fallback) ──────────────────────────────

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: V3Icon(
                  V3Icons.wifiOff,
                  size: 28,
                  color: AppColors.danger,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Your mentor AI is unreachable',
              textAlign: TextAlign.center,
              style: AppTypography.display(28),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.sans(
                14.5,
              ).copyWith(color: AppColors.ink2, height: 1.45),
            ),
            const SizedBox(height: 22),
            V3Button(
              icon: V3Icons.refresh,
              onPressed: _loadSuggestions,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── thinking (while the model suggests) ────────────────────────────────

  Widget _thinking() {
    final lines = cmpysSuggestionThoughts(
      interests: widget.interests,
      goalId: widget.goalId,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = _gutter(constraints.maxWidth);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              V3Rise(
                child: Text(
                  'MATCHING YOU WITH A MENTOR',
                  style: AppTypography.kick,
                ),
              ),
              const SizedBox(height: 10),
              V3Rise(
                delay: const Duration(milliseconds: 60),
                child: Text(
                  'Finding your matches…',
                  style: AppTypography.display(40),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.night2,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      V3Rise(
                        // Slow enough that real network latency is usually
                        // covered.
                        delay: Duration(milliseconds: 300 + i * 700),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            lines[i],
                            style: AppTypography.sans(
                              14.5,
                            ).copyWith(color: AppColors.nink2, height: 1.45),
                          ),
                        ),
                      ),
                    const V3Spinner(color: AppColors.nink3, size: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── discovery ──────────────────────────────────────────────────────────

  Widget _discoveryList() {
    final list = _filtered;
    final top = list.isEmpty ? null : list.first;
    final rest = list.length > 1
        ? list.sublist(1)
        : const <CmpysIdolSuggestion>[];
    final noResults =
        _query.trim().length >= 2 &&
        !_searching &&
        _searchError == null &&
        list.isEmpty;
    final interests = widget.interests.take(2).join(' and ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = _gutter(constraints.maxWidth);
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V3Rise(
                      child: Text(
                        'MENTOR DISCOVERY',
                        style: AppTypography.kick,
                      ),
                    ),
                    const SizedBox(height: 10),
                    V3Rise(
                      delay: const Duration(milliseconds: 60),
                      child: Semantics(
                        header: true,
                        label: 'Who would you like to learn from?',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Who would you',
                              style: AppTypography.display(40),
                            ),
                            Text(
                              'like to learn from?',
                              style: AppTypography.displayItalic(
                                40,
                              ).copyWith(color: AppColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    V3Rise(
                      delay: const Duration(milliseconds: 120),
                      child: Text(
                        'Suggested from ${interests.isEmpty ? 'your interests' : interests}.',
                        style: AppTypography.sans(
                          14,
                        ).copyWith(color: AppColors.ink2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    V3Rise(
                      delay: const Duration(milliseconds: 160),
                      child: _searchField(),
                    ),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: V3Spinner(
                          size: 16,
                          color: AppColors.ink3,
                          semanticLabel: 'Searching',
                        ),
                      ),
                  ],
                ),
              ),
              if (top != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 0),
                  child: V3Rise(
                    delay: const Duration(milliseconds: 220),
                    child: _bestMatch(top),
                  ),
                ),
              if (rest.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('ALSO RELEVANT', style: AppTypography.kick),
                      ),
                      for (var i = 0; i < rest.length; i++)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                          child: V3Rise(
                            delay: Duration(milliseconds: 280 + i * 60),
                            child: _row(rest[i]),
                          ),
                        ),
                    ],
                  ),
                ),
              if (noResults)
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 22),
                  child: V3Rise(child: _prepareCard()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return V3Field(
      controller: _searchController,
      onChanged: _search,
      placeholder: 'Search people or fields',
      textInputAction: TextInputAction.search,
      error: _searchError,
      right: _query.isEmpty
          ? const V3Icon(V3Icons.search, size: 18, color: AppColors.ink3)
          : V3Pressable(
              semanticLabel: 'Clear search',
              onTap: () {
                _searchController.clear();
                _search('');
              },
              child: const V3Icon(V3Icons.x, size: 18, color: AppColors.ink3),
            ),
    );
  }

  /// The top result: a 330 pt portrait card, "Best match" tag top-left and the
  /// mentor's field, name, why and "Preview mentor" over the bottom shade.
  Widget _bestMatch(CmpysIdolSuggestion suggestion) {
    final idol = suggestion.idol;
    return Builder(
      builder: (cardContext) => V3Pressable(
        onTap: () => _preview(cardContext, idol),
        focusRadius: AppRadii.brR2,
        semanticLabel:
            'Best match: ${idol.name}, ${idol.field}. ${suggestion.reason} Preview mentor',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadii.brR2,
            boxShadow: const [
              BoxShadow(
                color: Color(0x990E0C14),
                blurRadius: 40,
                offset: Offset(0, 24),
                spreadRadius: -24,
              ),
            ],
          ),
          child: V3Portrait(
            image: cmpysIdolImage(idol),
            height: 330,
            radius: AppRadii.r2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned(
                  top: 16,
                  left: 16,
                  child: V3Tag(
                    background: Color(0x24FFFFFF),
                    color: Colors.white,
                    icon: V3Icons.sparkle,
                    child: Text('Best match'),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idol.field,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          12,
                          FontWeight.w500,
                        ).copyWith(color: AppColors.nink2),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          idol.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.display(
                            40,
                          ).copyWith(color: Colors.white),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          suggestion.reason,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            13.5,
                          ).copyWith(color: AppColors.nink2, height: 1.45),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Preview mentor',
                              style: AppTypography.sans(
                                13.5,
                                FontWeight.w600,
                              ).copyWith(color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            const V3Icon(
                              V3Icons.arrowR,
                              size: 16,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(CmpysIdolSuggestion suggestion) {
    final idol = suggestion.idol;
    return Builder(
      builder: (cardContext) => V3Pressable(
        onTap: () => _preview(cardContext, idol),
        focusRadius: AppRadii.brR,
        semanticLabel: '${idol.name}, ${idol.field}',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: v3Card(),
          child: Row(
            children: [
              V3Avatar(
                image: cmpysIdolImage(idol),
                initials: idol.initials,
                tint: idol.tint,
                size: 56,
                gray: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idol.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sans(15.5, FontWeight.w600),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        idol.field,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          12.5,
                        ).copyWith(color: AppColors.ink3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const V3Icon(V3Icons.right, size: 18, color: AppColors.ink3),
            ],
          ),
        ),
      ),
    );
  }

  /// "“q” isn’t in the library yet" → Prepare profile → Researching →
  /// Queued for review.
  Widget _prepareCard() {
    // A name this screen already queued shows as queued straight away.
    final alreadyQueued =
        _import == _Import.idle &&
        _importError == null &&
        _queuedNames.contains(_importKey(_query));
    final working = _import != _Import.idle || alreadyQueued;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: v3Card(),
      child: working
          ? _importProgressBody(queued: alreadyQueued)
          : _importOffer(),
    );
  }

  Widget _importOffer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '“${_query.trim()}” isn’t in the library yet',
          style: AppTypography.sans(15.5, FontWeight.w600),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
          child: Text(
            'We can research this person and prepare a profile from documented sources.',
            style: AppTypography.sans(
              13.5,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
        ),
        if (_importError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: V3Icon(
                    V3Icons.alert,
                    size: 14,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _importError!,
                    style: AppTypography.sans(
                      12.5,
                    ).copyWith(color: AppColors.danger, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        V3Button(
          size: V3Size.md,
          kind: V3ButtonKind.dark,
          icon: V3Icons.plus,
          onPressed: _prepareProfile,
          child: const Text('Prepare profile'),
        ),
      ],
    );
  }

  Widget _importProgressBody({bool queued = false}) {
    final done = queued || _import == _Import.queued;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (done)
              const V3Icon(
                V3Icons.check,
                size: 16,
                strokeWidth: 2.5,
                color: AppColors.sage2,
              )
            else
              const V3Spinner(size: 16, semanticLabel: 'Researching'),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                done ? 'Queued for review' : 'Researching $_importName',
                style: AppTypography.sans(15, FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        V3Bar(value: done ? 1 : _importProgress, color: AppColors.iris),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            done
                ? 'Profiles are checked before publishing. Pick a suggested mentor to continue now.'
                : 'Finding sources · checking timeline · drafting domains',
            style: AppTypography.sans(12.5).copyWith(color: AppColors.ink3),
          ),
        ),
      ],
    );
  }
}
