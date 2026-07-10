// CMPYS pushed detail screens: Notes, Saved, Settings, EditProfile,
// MentorPicker, TaskDetail. All read/write the shared CmpysStore so counts and
// toggles stay consistent with the tabs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/design_tokens.dart';
import '../../../app/router.dart';
import '../../../core/ui/app_shell.dart';
import '../../../core/ui/cmpys/cmpys_primitives.dart';
import '../../../core/ui/motion/page_transition.dart';
import '../data/cmpys_seed.dart';
import '../state/cmpys_store.dart';
import 'idol_detail_screen.dart';
import 'readers/article_reader_screen.dart';
import 'readers/book_reader_screen.dart';
import 'readers/video_lesson_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared scaffolding
// ─────────────────────────────────────────────────────────────────────────────

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.title,
    required this.kicker,
    required this.child,
  });
  final String title;
  final String? kicker;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
              child: Row(children: [_backBtn(context)]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (kicker != null) ...[
                    CmpysKicker(kicker!),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    title,
                    style: AppTypography.h1.copyWith(
                        fontSize: 30, letterSpacing: -0.4, height: 1.3),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

Widget _backBtn(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hair),
          ),
          child: const Icon(Icons.chevron_left_rounded,
              size: 22, color: AppColors.ink),
        ),
      ),
    );

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.cta,
    this.onCta,
  });
  final IconData icon;
  final String title;
  final String body;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.hair),
              ),
              child: Icon(icon, size: 28, color: AppColors.ink3),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTypography.h3.copyWith(fontSize: 21)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.bodyDim.copyWith(fontSize: 14.5),
              ),
            ),
            if (cta != null) ...[
              const SizedBox(height: 18),
              CmpysButton(
                variant: CmpysBtnVariant.soft,
                onTap: onCta,
                child: Text(cta!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes
// ─────────────────────────────────────────────────────────────────────────────

class CmpysNotesScreen extends ConsumerWidget {
  const CmpysNotesScreen({super.key});

  Color _kindColor(String kind) {
    switch (kind) {
      case 'chat':
        return AppColors.green;
      case 'read':
        return AppColors.blue;
      case 'book':
        return AppColors.ochre2;
      default:
        return AppColors.ink3;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(cmpysStoreProvider.select((s) => s.notes));
    return _DetailScaffold(
      title: 'Notes',
      kicker: '${notes.length} saved',
      child: notes.isEmpty
          ? _EmptyState(
              icon: PhosphorIconsRegular.note,
              title: 'No notes yet',
              body:
                  'Save a line from your mentor or a reading, and it lands here. Tap any message in chat to keep it.',
              cta: 'Open chat',
              onCta: () {
                Navigator.of(context).pop();
                context.go(AppRoutes.chat);
              },
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(18, 4, 18, AppShell.bottomNavClearance(context)),
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final n = notes[i];
                return CmpysCardSurface(
                  onTap: () => _openSheet(context, ref, n.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            (n.kind == 'chat' ? 'From mentor' : n.kind)
                                .toUpperCase(),
                            style: AppTypography.kicker.copyWith(
                              color: _kindColor(n.kind),
                              fontSize: 10.5,
                            ),
                          ),
                          const Spacer(),
                          Text(n.when,
                              style: AppTypography.caption
                                  .copyWith(color: AppColors.ink3, fontSize: 11.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.readingQuote
                            .copyWith(fontSize: 16, height: 1.4, fontStyle: FontStyle.normal),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n.from != null ? '${n.title} · ${n.from}' : n.title,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.ink3, fontSize: 12.5),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, String id) {
    final note =
        ref.read(cmpysStoreProvider).notes.firstWhere((n) => n.id == id);
    showCmpysSheet(
      context,
      title: note.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(note.body,
              style: AppTypography.reading.copyWith(fontSize: 17, height: 1.5)),
          if (note.from != null) ...[
            const SizedBox(height: 10),
            Text('— ${note.from}',
                style: AppTypography.captionMedium.copyWith(color: AppColors.ink2)),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: CmpysButton(
                  variant: CmpysBtnVariant.outline,
                  leadingIcon: PhosphorIconsRegular.shareNetwork,
                  onTap: () {
                    Navigator.of(context).pop();
                    showCmpysToast(context, 'Note copied',
                        icon: Icons.ios_share_rounded, tone: AppColors.ink3);
                  },
                  child: const Text('Share'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CmpysButton(
                  variant: CmpysBtnVariant.danger,
                  leadingIcon: Icons.close_rounded,
                  onTap: () {
                    ref.read(cmpysStoreProvider.notifier).deleteNote(id);
                    Navigator.of(context).pop();
                    showCmpysToast(context, 'Note deleted',
                        icon: Icons.delete_outline_rounded, tone: AppColors.danger);
                  },
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved
// ─────────────────────────────────────────────────────────────────────────────

class CmpysSavedScreen extends ConsumerWidget {
  const CmpysSavedScreen({super.key});

  ({IconData icon, Color color}) _meta(String kind) {
    switch (kind) {
      case 'task':
        return (icon: PhosphorIconsRegular.target, color: AppColors.green);
      case 'read':
        return (icon: PhosphorIconsRegular.fileText, color: AppColors.blue);
      case 'video':
        return (icon: PhosphorIconsFill.playCircle, color: AppColors.clay);
      case 'book':
        return (icon: PhosphorIconsRegular.bookOpen, color: AppColors.ochre2);
      default:
        return (icon: PhosphorIconsRegular.quotes, color: AppColors.ink2);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(cmpysStoreProvider.select((s) => s.saved));
    return _DetailScaffold(
      title: 'Saved',
      kicker: '${saved.length} item${saved.length == 1 ? "" : "s"}',
      child: saved.isEmpty
          ? _EmptyState(
              icon: PhosphorIconsRegular.bookmarkSimple,
              title: 'Nothing saved yet',
              body:
                  'Bookmark readings, lessons, or idea cards to build your own library. The bookmark icon keeps them here.',
              cta: 'Browse ideas',
              onCta: () {
                Navigator.of(context).pop();
                context.go(AppRoutes.vault);
              },
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(18, 4, 18, AppShell.bottomNavClearance(context)),
              itemCount: saved.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = saved[i];
                final m = _meta(s.kind);
                return CmpysCardSurface(
                  pad: const EdgeInsets.fromLTRB(13, 13, 13, 13),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: m.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(m.icon, size: 19, color: m.color),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _open(context, s.kind, s.id),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyMedium
                                      .copyWith(fontSize: 15)),
                              if (s.sub != null) ...[
                                const SizedBox(height: 2),
                                Text(s.sub!,
                                    style: AppTypography.caption.copyWith(
                                        color: AppColors.ink3, fontSize: 12.5)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          ref.read(cmpysStoreProvider.notifier).unsave(s.id);
                          showCmpysToast(context, 'Removed from saved',
                              icon: Icons.bookmark_remove_outlined,
                              tone: AppColors.ink3);
                        },
                        icon: const Icon(PhosphorIconsFill.bookmarkSimple,
                            size: 19, color: AppColors.green),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _open(BuildContext context, String kind, String id) {
    if (kind == 'idea') {
      Navigator.of(context).pop();
      context.go(AppRoutes.vault);
      return;
    }
    // Resolve plan-item readers by id.
    final reading = cmpysReadings[id];
    if (reading != null) {
      Navigator.of(context).push(CmpysPageRoute(
          builder: (_) => CmpysArticleReaderScreen(reading: reading)));
      return;
    }
    final book = cmpysBooks[id];
    if (book != null) {
      Navigator.of(context).push(
          CmpysPageRoute(builder: (_) => CmpysBookReaderScreen(book: book)));
      return;
    }
    final video = cmpysVideos[id];
    if (video != null) {
      Navigator.of(context).push(CmpysPageRoute(
          builder: (_) => CmpysVideoLessonScreen(video: video)));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

class CmpysSettingsScreen extends ConsumerWidget {
  const CmpysSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(cmpysStoreProvider.select((s) => s.settings));
    final store = ref.read(cmpysStoreProvider.notifier);
    return _DetailScaffold(
      title: 'Settings',
      kicker: null,
      child: ListView(
        padding: EdgeInsets.fromLTRB(18, 4, 18, AppShell.bottomNavClearance(context)),
        children: [
          _group('Notifications', [
            _toggleRow(PhosphorIconsRegular.bellSimple, 'Daily reminder',
                'A nudge to keep your streak alive', settings.reminder,
                () => store.toggleSetting('reminder')),
            _staticRow(PhosphorIconsRegular.clock, 'Reminder time', '8:00 AM'),
            _toggleRow(PhosphorIconsRegular.chatTeardrop, 'Mentor messages',
                'Let your mentor check in', settings.mentorPing,
                () => store.toggleSetting('mentorPing'),
                last: true),
          ]),
          _group('Experience', [
            _toggleRow(PhosphorIconsRegular.sparkle, 'Weekly comparison digest',
                null, settings.digest, () => store.toggleSetting('digest')),
            _toggleRow(PhosphorIconsRegular.target, 'Sound & haptics', null,
                settings.haptics, () => store.toggleSetting('haptics'),
                last: true),
          ]),
          _group('Account', [
            _navRow(context, PhosphorIconsRegular.user, 'Edit profile', null,
                () => Navigator.of(context).push(CmpysPageRoute(
                    builder: (_) => const CmpysEditProfileScreen()))),
            _navRow(context, PhosphorIconsRegular.lock, 'Privacy & data', null,
                () => showCmpysToast(context, 'Privacy center',
                    icon: Icons.lock_outline_rounded, tone: AppColors.ink3)),
            _navRow(context, PhosphorIconsRegular.info, 'About CMPYS',
                'Version 1.0',
                () => showCmpysToast(context, 'CMPYS v1.0',
                    icon: Icons.info_outline_rounded, tone: AppColors.ink3),
                last: true),
          ]),
        ],
      ),
    );
  }

  Widget _group(String header, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: CmpysKicker(header),
          ),
          CmpysCardSurface(
            pad: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _rowFrame(IconData icon, String label, String? sub, Widget trailing,
      {bool last = false, Color? color}) {
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.paper2,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: color ?? AppColors.ink2),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.bodyMedium.copyWith(fontSize: 15)),
                if (sub != null) ...[
                  const SizedBox(height: 1),
                  Text(sub,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink3, fontSize: 12)),
                ],
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _toggleRow(IconData icon, String label, String? sub, bool on,
      VoidCallback onTap,
      {bool last = false}) {
    return _rowFrame(icon, label, sub, _Toggle(on: on, onTap: onTap),
        last: last);
  }

  Widget _staticRow(IconData icon, String label, String value) {
    return _rowFrame(
        icon,
        label,
        null,
        Text(value,
            style: AppTypography.caption
                .copyWith(color: AppColors.ink3, fontSize: 13.5)));
  }

  Widget _navRow(BuildContext context, IconData icon, String label, String? sub,
      VoidCallback onTap,
      {bool last = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _rowFrame(icon, label, sub,
          const Icon(Icons.chevron_right_rounded, color: AppColors.ink3, size: 22),
          last: last),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? AppColors.green : AppColors.hair2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit profile (dirty-tracking + discard sheet)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysEditProfileScreen extends ConsumerStatefulWidget {
  const CmpysEditProfileScreen({super.key});

  @override
  ConsumerState<CmpysEditProfileScreen> createState() =>
      _CmpysEditProfileScreenState();
}

class _CmpysEditProfileScreenState
    extends ConsumerState<CmpysEditProfileScreen> {
  late TextEditingController _name;
  late int _age;
  late Set<String> _interests;
  late String _initialName;
  late int _initialAge;
  late Set<String> _initialInterests;

  @override
  void initState() {
    super.initState();
    final u = ref.read(cmpysStoreProvider).user;
    _name = TextEditingController(text: u.name);
    _age = u.age > 0 ? u.age : 16;
    _interests = {...u.interests};
    _initialName = u.name;
    _initialAge = _age;
    _initialInterests = {...u.interests};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text != _initialName ||
      _age != _initialAge ||
      !_setEq(_interests, _initialInterests);

  bool _setEq(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  void _save() {
    ref.read(cmpysStoreProvider.notifier).updateUser(
        name: _name.text.trim(), age: _age, interests: _interests.toList());
    showCmpysToast(context, 'Profile saved',
        icon: Icons.check_rounded, tone: AppColors.green);
    Navigator.of(context).pop();
  }

  Future<void> _tryBack() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    await showCmpysSheet(
      context,
      title: 'Discard changes?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('You have unsaved edits to your profile. Leave without saving?',
              style: AppTypography.bodyDim.copyWith(fontSize: 14.5)),
          const SizedBox(height: 16),
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            full: true,
            onTap: () {
              Navigator.of(context).pop();
              _save();
            },
            child: const Text('Save and leave'),
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.danger,
            full: true,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Discard'),
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.ghost,
            full: true,
            onTap: () => Navigator.of(context).pop(),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _tryBack,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.hair),
                          ),
                          child: const Icon(Icons.chevron_left_rounded,
                              size: 22, color: AppColors.ink),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _dirty ? _save : null,
                      child: Text(
                        'Save',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _dirty ? AppColors.green : AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(22, 4, 22, AppShell.bottomNavClearance(context)),
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.ochre, Color(0xFFE57C00)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              (_name.text.isNotEmpty ? _name.text[0] : 'Y')
                                  .toUpperCase(),
                              style: AppTypography.h2.copyWith(
                                  color: Colors.white, fontSize: 30),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Change photo',
                              style: AppTypography.captionMedium.copyWith(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const CmpysKicker('Name'),
                    const SizedBox(height: 8),
                    _field(_name),
                    const SizedBox(height: 18),
                    const CmpysKicker('Age'),
                    const SizedBox(height: 8),
                    _ageStepper(),
                    const SizedBox(height: 18),
                    const CmpysKicker('Interests'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: cmpysInterests.map((x) {
                        final on = _interests.contains(x);
                        return CmpysChipPill(
                          label: x,
                          active: on,
                          onTap: () => setState(() {
                            if (on) {
                              _interests.remove(x);
                            } else {
                              _interests.add(x);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    if (_dirty) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.ochre, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 7),
                            Text('Unsaved changes',
                                style: AppTypography.caption.copyWith(
                                    color: AppColors.ochre2, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: TextField(
        controller: c,
        onChanged: (_) => setState(() {}),
        style: AppTypography.body.copyWith(fontSize: 16),
        cursorColor: AppColors.green,
        // The 52px pill gives the field tight constraints; without this the
        // decorator top-aligns the text (InputBorder.none ⇒ non-outline).
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          hintText: 'Your name',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _ageStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair2, width: 1.5),
      ),
      child: Row(
        children: [
          _stepBtn('−', AppColors.paper2, AppColors.ink,
              () => setState(() => _age = _age > 16 ? _age - 1 : 16)),
          Expanded(
            child: Center(
              child: Text('$_age',
                  style: AppTypography.display.copyWith(fontSize: 30, height: 1)),
            ),
          ),
          _stepBtn('+', AppColors.greenSoft, AppColors.green,
              () => setState(() => _age = _age < 80 ? _age + 1 : 80)),
        ],
      ),
    );
  }

  Widget _stepBtn(String s, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: Text(s,
              style: AppTypography.h2
                  .copyWith(fontSize: 20, color: fg, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mentor picker (change mentor)
// ─────────────────────────────────────────────────────────────────────────────

class CmpysMentorPickerScreen extends ConsumerWidget {
  const CmpysMentorPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(cmpysStoreProvider.select((s) => s.idol));
    return _DetailScaffold(
      title: 'Change mentor',
      kicker: 'Switch who you measure against',
      child: ListView(
        padding: EdgeInsets.fromLTRB(18, 4, 18, AppShell.bottomNavClearance(context)),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ochreSoft,
              borderRadius: AppRadii.card,
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.info,
                    size: 20, color: AppColors.ochre2),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Switching keeps your progress, but your comparison and plan are tuned to ${active.short}. This is a demo — your plan stays as is.',
                    style:
                        AppTypography.caption.copyWith(fontSize: 13.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final idol in cmpysIdols) ...[
            _idolRow(context, ref, idol, idol.id == active.id),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _idolRow(
      BuildContext context, WidgetRef ref, CmpysIdol idol, bool isActive) {
    return GestureDetector(
      onTap: isActive ? null : () => _confirm(context, ref, idol),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadii.card,
          border: Border.all(
            color: isActive ? AppColors.green : AppColors.hair,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CmpysMentorAvatar(
              slug: idol.slug,
              initials: idol.initials,
              color: idol.color,
              tint: idol.tint,
              size: 46,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(idol.name,
                      style: AppTypography.h4.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('${idol.title} · ${idol.era}',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.ink2, fontSize: 12.5)),
                ],
              ),
            ),
            if (isActive)
              Text('Active',
                  style: AppTypography.captionMedium.copyWith(
                      color: AppColors.green, fontWeight: FontWeight.w700))
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.ink3, size: 20),
          ],
        ),
      ),
    );
  }

  void _confirm(BuildContext context, WidgetRef ref, CmpysIdol idol) {
    showCmpysSheet(
      context,
      title: 'Switch to ${idol.short}?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${idol.name} will become your active mentor. In a full build we’d regenerate your comparison and plan.',
            style: AppTypography.bodyDim.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 16),
          CmpysButton(
            variant: CmpysBtnVariant.primary,
            full: true,
            onTap: () {
              ref.read(cmpysStoreProvider.notifier).switchMentor(idol);
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              showCmpysToast(context, '${idol.short} is now your mentor',
                  icon: Icons.check_rounded, tone: AppColors.green);
            },
            child: const Text('Switch mentor'),
          ),
          const SizedBox(height: 10),
          CmpysButton(
            variant: CmpysBtnVariant.ghost,
            full: true,
            onTap: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task detail
// ─────────────────────────────────────────────────────────────────────────────

class CmpysTaskDetailScreen extends ConsumerWidget {
  const CmpysTaskDetailScreen(
      {super.key, required this.item, required this.pillar});
  final CmpysPlanItem item;
  final CmpysPillar pillar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(cmpysStoreProvider.select((s) => s.tasks[item.id] ?? false));
    final isSaved =
        ref.watch(cmpysStoreProvider.select((s) => s.saved.any((x) => x.id == item.id)));
    final idol = ref.watch(cmpysStoreProvider.select((s) => s.idol));
    final store = ref.read(cmpysStoreProvider.notifier);

    final repeatLabel = item.repeat == CmpysRepeat.daily
        ? 'Daily habit'
        : item.repeat == CmpysRepeat.weekly
            ? 'Weekly'
            : 'One-time';

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
              child: Row(
                children: [
                  _backBtn(context),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      final nowSaved = store.toggleSave(
                          id: item.id,
                          kind: 'task',
                          title: item.title,
                          sub: pillar.title);
                      showCmpysToast(context, nowSaved ? 'Saved' : 'Removed from saved',
                          icon: nowSaved
                              ? Icons.bookmark_added_outlined
                              : Icons.bookmark_remove_outlined,
                          tone: nowSaved ? AppColors.green : AppColors.ink3);
                    },
                    icon: Icon(
                      isSaved
                          ? PhosphorIconsFill.bookmarkSimple
                          : PhosphorIconsRegular.bookmarkSimple,
                      color: isSaved ? AppColors.green : AppColors.ink2,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 30),
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: pillar.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_kindIcon(item.kind), size: 15, color: pillar.accent),
                        const SizedBox(width: 6),
                        Text(
                          item.minutes > 0
                              ? '$repeatLabel · ${item.minutes} min'
                              : repeatLabel,
                          style: AppTypography.captionMedium.copyWith(
                              color: pillar.accent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(item.title,
                      style: AppTypography.h1
                          .copyWith(fontSize: 28, letterSpacing: -0.4, height: 1.25)),
                  const SizedBox(height: 14),
                  Text(item.desc,
                      style: AppTypography.reading
                          .copyWith(fontSize: 16, height: 1.6, color: AppColors.ink2)),
                  const SizedBox(height: 22),
                  CmpysCardSurface(
                    color: pillar.accent.withValues(alpha: 0.08),
                    border: false,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CmpysMentorAvatar(
                          slug: idol.slug,
                          initials: idol.initials,
                          color: idol.color,
                          tint: idol.tint,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Why ${idol.short} put this in your plan',
                                  style: AppTypography.captionMedium.copyWith(
                                      color: AppColors.ink2,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(pillar.why,
                                  style: AppTypography.readingQuote.copyWith(
                                      fontSize: 15.5, height: 1.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  22, 12, 22, AppShell.bottomNavClearance(context)),
              child: CmpysButton(
                variant: done ? CmpysBtnVariant.soft : CmpysBtnVariant.primary,
                size: CmpysBtnSize.lg,
                full: true,
                leadingIcon: done ? Icons.check_rounded : null,
                onTap: () {
                  store.toggleTask(item.id);
                  if (!done) {
                    showCmpysToast(context, 'Nice. Kept your word.',
                        icon: Icons.check_rounded, tone: AppColors.green);
                  }
                },
                child: Text(done
                    ? 'Completed — tap to undo'
                    : (item.repeat == CmpysRepeat.daily
                        ? 'Mark done for today'
                        : 'Mark complete')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(CmpysItemKind kind) {
    switch (kind) {
      case CmpysItemKind.read:
        return PhosphorIconsRegular.fileText;
      case CmpysItemKind.video:
        return PhosphorIconsFill.playCircle;
      case CmpysItemKind.book:
        return PhosphorIconsRegular.bookOpen;
      case CmpysItemKind.task:
        return PhosphorIconsRegular.target;
    }
  }
}

// Helper so other screens can open the active idol's detail.
void openIdolDetail(BuildContext context, CmpysIdol idol) {
  Navigator.of(context)
      .push(CmpysPageRoute(builder: (_) => CmpysIdolDetailScreen(idol: idol)));
}

/// Routes a plan item to the right detail screen by kind:
/// read → article, book → book lesson, video → video, task → task detail.
void openCmpysPlanItem(
  BuildContext context,
  CmpysPlanItem item, {
  required CmpysPillar pillar,
}) {
  switch (item.kind) {
    case CmpysItemKind.read:
      final reading = cmpysReadings[item.id];
      if (reading != null) {
        Navigator.of(context).push(CmpysPageRoute(
            builder: (_) => CmpysArticleReaderScreen(reading: reading)));
        return;
      }
      break;
    case CmpysItemKind.book:
      final book = cmpysBooks[item.id];
      if (book != null) {
        Navigator.of(context).push(
            CmpysPageRoute(builder: (_) => CmpysBookReaderScreen(book: book)));
        return;
      }
      break;
    case CmpysItemKind.video:
      final video = cmpysVideos[item.id];
      if (video != null) {
        Navigator.of(context).push(CmpysPageRoute(
            builder: (_) => CmpysVideoLessonScreen(video: video)));
        return;
      }
      break;
    case CmpysItemKind.task:
      break;
  }
  // Tasks (and any item without bound reader content) open the task detail.
  Navigator.of(context).push(CmpysPageRoute(
      builder: (_) => CmpysTaskDetailScreen(item: item, pillar: pillar)));
}
