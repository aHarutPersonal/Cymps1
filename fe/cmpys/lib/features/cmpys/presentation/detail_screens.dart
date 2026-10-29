// CMPYS detail screens and sheets: Notes, Saved, the Edit profile sheet and
// TaskDetail. All read/write the shared CmpysStore so counts stay consistent
// with the tabs.

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../../../core/ui/v3/v3.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'idol_detail_screen.dart';
import 'onboarding/personalize_step.dart' show CmpysAgeWheel;

// ─────────────────────────────────────────────────────────────────────────────
// Notes and Saved (`v3/you.jsx` ListScreen): both live on this device in
// [CmpysStore]; each card can be removed, and an empty list points to where
// items come from.
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryEntry {
  const _LibraryEntry({
    required this.id,
    required this.kick,
    required this.text,
    this.sub,
    this.onTap,
  });
  final String id;
  final String kick;
  final String text;
  final String? sub;
  final VoidCallback? onTap;
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.title,
    required this.entries,
    required this.onRemove,
    required this.removeLabel,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyCta,
    required this.onEmptyCta,
  });

  final String title;
  final List<_LibraryEntry> entries;
  final ValueChanged<String> onRemove;

  /// The Remove button's accessible name ("Remove note").
  final String removeLabel;
  final V3Icons emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final String emptyCta;
  final VoidCallback onEmptyCta;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V3TopBar(onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                AppShell.bottomNavClearance(context),
              ),
              children: [
                Text(
                  'Library · on this device'.toUpperCase(),
                  style: AppTypography.kick,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTypography.display(
                    42,
                  ).copyWith(color: AppColors.ink),
                ),
                if (entries.isEmpty)
                  _empty()
                else ...[
                  const SizedBox(height: 18),
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    V3Rise(
                      key: ValueKey(entries[i].id),
                      delay: Duration(milliseconds: (i < 8 ? i : 8) * 50),
                      child: _card(entries[i]),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 60),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.paper2,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: V3Icon(emptyIcon, size: 26, color: AppColors.ink3),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            emptyTitle,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              17,
              FontWeight.w600,
            ).copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            emptyBody,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              14,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
          const SizedBox(height: 18),
          V3Button(
            kind: V3ButtonKind.dark,
            size: V3Size.md,
            onPressed: onEmptyCta,
            child: Text(emptyCta),
          ),
        ],
      ),
    );
  }

  /// The 44 pt Remove hit box sits in the card's top-right corner, over the
  /// padding and the header. The header is [_headerHeight] tall so the text
  /// starts below the box (border 1 + padding 16 + header 20 + gap 8 = 45),
  /// and the kick line stops short of it, so no tap on text deletes.
  static const double _headerHeight = 20;

  /// The design's card: a kick line with a 16 pt trash button, the text in
  /// Literata and an optional sub line.
  Widget _card(_LibraryEntry entry) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Padding(
            // The hit box spans the last 30 pt of the content width.
            padding: const EdgeInsets.only(right: 30),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                entry.kick.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.kick,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entry.text,
          style: AppTypography.read(
            15.5,
          ).copyWith(height: 1.55, color: AppColors.ink),
        ),
        if (entry.sub case final sub? when sub.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            sub,
            style: AppTypography.sans(12.5).copyWith(color: AppColors.ink3),
          ),
        ],
      ],
    );
    Widget card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: v3Card(),
      child: body,
    );
    final onTap = entry.onTap;
    if (onTap != null) {
      card = V3Pressable(
        onTap: onTap,
        pressedScale: 0.985,
        focusRadius: BorderRadius.circular(AppRadii.r),
        child: card,
      );
    }
    return Stack(
      children: [
        card,
        // The icon keeps the design's spot: 16 pt in from the card's right
        // edge, centred on the header (1 + 16 + 20 / 2 = 27 pt down).
        Positioned(
          top: 0,
          right: 2,
          child: V3Pressable(
            semanticLabel: removeLabel,
            minTapTarget: 0,
            onTap: () => onRemove(entry.id),
            child: const SizedBox(
              key: ValueKey('library-remove'),
              width: 44,
              height: 44,
              child: Padding(
                padding: EdgeInsets.only(top: 19),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: V3Icon(
                    V3Icons.trash,
                    size: 16,
                    color: AppColors.ink3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// When a note was saved, relative to [now]: "Just now" (under a minute,
/// or a clock that moved backwards), "N min ago", "N h ago" (the same day),
/// "Yesterday", a weekday within the last week ("Mon"), else a date
/// ("12 Oct", with the year when it isn't this one). A note stored before
/// the time was kept ([CmpysNote.at] null) shows its stored label.
String cmpysNoteWhen(CmpysNote note, {DateTime? now}) {
  final atMs = note.at;
  if (atMs == null) return note.when;
  final n = now ?? DateTime.now();
  final at = DateTime.fromMillisecondsSinceEpoch(atMs);
  final elapsed = n.difference(at);
  if (elapsed < const Duration(minutes: 1)) return 'Just now';
  if (elapsed < const Duration(hours: 1)) {
    return '${elapsed.inMinutes} min ago';
  }
  final days = DateTime(n.year, n.month, n.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return '${elapsed.inHours} h ago';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE', 'en_US').format(at);
  return DateFormat(
    at.year == n.year ? 'd MMM' : 'd MMM y',
    'en_US',
  ).format(at);
}

class CmpysNotesScreen extends ConsumerWidget {
  const CmpysNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(cmpysStoreProvider.select((s) => s.notes));
    final now = DateTime.now();
    return _LibraryList(
      title: 'Notes',
      entries: [
        for (final n in notes)
          _LibraryEntry(
            id: n.id,
            kick: [
              n.title.trim().isNotEmpty ? n.title : n.kind,
              if (cmpysNoteWhen(n, now: now) case final saved
                  when saved.trim().isNotEmpty)
                saved,
            ].join(' · '),
            text: n.body,
            sub: n.from != null && !n.title.contains(n.from!) ? n.from : null,
          ),
      ],
      onRemove: (id) {
        ref.read(cmpysStoreProvider.notifier).deleteNote(id);
        showV3Toast(context, 'Note deleted', icon: V3Icons.trash);
      },
      removeLabel: 'Remove note',
      emptyIcon: V3Icons.note,
      emptyTitle: 'No notes yet',
      emptyBody: 'Tap any mentor reply in Chat to save it here.',
      emptyCta: 'Open chat',
      onEmptyCta: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go(AppRoutes.chat);
      },
    );
  }
}

class CmpysSavedScreen extends ConsumerWidget {
  const CmpysSavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(cmpysStoreProvider.select((s) => s.saved));
    return _LibraryList(
      title: 'Saved',
      entries: [
        for (final s in saved)
          _LibraryEntry(
            id: s.id,
            kick: s.kind,
            text: s.title,
            sub: s.sub,
            // Only ideas are saved now (from the reels). An older build's
            // seed reading, book, video or task has no reader any more, so it
            // opens nothing; it can still be removed.
            onTap: s.kind == 'idea' ? () => context.goToIdeas() : null,
          ),
      ],
      onRemove: (id) {
        ref.read(cmpysStoreProvider.notifier).unsave(id);
        showV3Toast(context, 'Removed from saved', icon: V3Icons.trash);
      },
      removeLabel: 'Remove from saved',
      emptyIcon: V3Icons.bookmark,
      emptyTitle: 'Nothing saved yet',
      emptyBody: 'Save ideas from the reels. Saved books live in Reading.',
      emptyCta: 'Browse ideas',
      onEmptyCta: () => context.goToIdeas(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit profile (`v3/you.jsx` EditProfile): a sheet with an unsaved-changes
// guard.
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the "Edit profile" sheet.
Future<void> showCmpysEditProfileSheet(BuildContext context) =>
    showV3Sheet<void>(
      context,
      title: 'Edit profile',
      builder: (_) => const CmpysEditProfileScreen(),
    );

/// The body of the "Edit profile" sheet: name, age and interests, saved on
/// this device by [CmpysStore.updateUser]. Once an intake session exists
/// ([CmpysState.ageLocked]) the age is shown read-only with why.
///
/// While there are unsaved edits a [PopScope] vetoes every way of closing
/// the sheet (close button, scrim, drag, system back) and swaps the form for
/// the guard: "Save changes" runs the save, "Discard" closes without saving
/// and "Keep editing" returns to the form.
class CmpysEditProfileScreen extends ConsumerStatefulWidget {
  const CmpysEditProfileScreen({super.key});

  @override
  ConsumerState<CmpysEditProfileScreen> createState() =>
      _CmpysEditProfileScreenState();
}

class _CmpysEditProfileScreenState
    extends ConsumerState<CmpysEditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final List<String> _interests;
  late final String _initialName;
  late final String _initialAge;
  late final Set<String> _initialInterests;

  /// The age was set at intake and can't be edited here.
  late final bool _ageLocked;

  /// The design's interests plus any the profile already has outside them,
  /// so those can still be removed.
  late final List<String> _choices;
  bool _ask = false;

  @override
  void initState() {
    super.initState();
    final st = ref.read(cmpysStoreProvider);
    final u = st.user;
    _ageLocked = st.ageLocked;
    _initialName = u.name;
    _initialAge = u.age > 0 ? '${u.age}' : '';
    _initialInterests = {...u.interests};
    _interests = [...u.interests];
    _choices = [
      ...cmpysOnboardingInterests,
      for (final x in u.interests)
        if (!cmpysOnboardingInterests.contains(x)) x,
    ];
    _name = TextEditingController(text: _initialName)..addListener(_changed);
    _age = TextEditingController(text: _initialAge)..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  int? get _ageValue => int.tryParse(_age.text);

  bool get _ageOk {
    if (_ageLocked) return true;
    final v = _ageValue;
    return v != null && v >= CmpysAgeWheel.minAge && v <= CmpysAgeWheel.maxAge;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _ageOk;

  bool get _dirty =>
      _name.text != _initialName ||
      _age.text != _initialAge ||
      !setEquals(_interests.toSet(), _initialInterests);

  /// Why Save is disabled, shown once there is something to save (a stored
  /// age of 0 opens blank, so the hint appears as soon as the form is dirty).
  String? get _nameError =>
      _dirty && _name.text.trim().isEmpty ? 'Enter your name' : null;

  String? get _ageError => _ageOk || (_age.text.isEmpty && !_dirty)
      ? null
      : 'Enter an age from ${CmpysAgeWheel.minAge} to ${CmpysAgeWheel.maxAge}';

  void _save() {
    if (!_valid) return;
    ref
        .read(cmpysStoreProvider.notifier)
        .updateUser(
          name: _name.text.trim(),
          age: _ageLocked ? null : _ageValue,
          interests: List.of(_interests),
        );
    showV3Toast(context, 'Profile updated on this device');
    // A direct pop: the PopScope only vetoes maybePop and system back.
    Navigator.of(context).pop();
  }

  void _toggle(String x) => setState(() {
    if (!_interests.remove(x)) _interests.add(x);
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        FocusScope.of(context).unfocus();
        setState(() => _ask = true);
      },
      // Transparent Material so the fields also work outside a sheet.
      child: Material(
        type: MaterialType.transparency,
        child: _ask ? _guard() : _form(),
      ),
    );
  }

  Widget _guard() {
    return V3Rise(
      duration: const Duration(milliseconds: 400),
      offset: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You have unsaved changes.',
            style: AppTypography.sans(
              14.5,
            ).copyWith(color: AppColors.ink2, height: 1.5),
          ),
          // Why "Save changes" is disabled, since the form is hidden here.
          if ((_nameError ?? _ageError) case final problem?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                problem,
                style: AppTypography.sans(
                  13,
                ).copyWith(color: AppColors.danger, height: 1.4),
              ),
            ),
          const SizedBox(height: 16),
          V3Button(
            full: true,
            onPressed: _valid ? _save : null,
            child: const Text('Save changes'),
          ),
          const SizedBox(height: 8),
          V3Button(
            kind: V3ButtonKind.soft,
            full: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Discard'),
          ),
          const SizedBox(height: 8),
          V3Button(
            kind: V3ButtonKind.ghost,
            full: true,
            onPressed: () => setState(() => _ask = false),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        V3Field(
          label: 'Name',
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          error: _nameError,
        ),
        const SizedBox(height: 12),
        V3Field(
          label: 'Age',
          controller: _age,
          enabled: !_ageLocked,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          error: _ageError,
        ),
        if (_ageLocked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Your age is set at intake so comparisons stay fair.',
              style: AppTypography.sans(
                12.5,
              ).copyWith(color: AppColors.ink3, height: 1.4),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(
            'Interests',
            style: AppTypography.sans(
              12.5,
              FontWeight.w600,
            ).copyWith(color: AppColors.ink2),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final x in _choices)
              // A label wider than the sheet (large text, narrow phone)
              // ellipsizes inside the chip.
              V3Chip(
                on: _interests.contains(x),
                onPressed: () => _toggle(x),
                child: Text(x),
              ),
          ],
        ),
        const SizedBox(height: 18),
        V3Button(
          full: true,
          disabled: !_dirty || !_valid,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Helper so other screens can open the active idol's detail.
void openIdolDetail(BuildContext context, CmpysIdol idol) {
  Navigator.of(context)
      .push(CmpysPageRoute(builder: (_) => CmpysIdolDetailScreen(idol: idol)));
}
