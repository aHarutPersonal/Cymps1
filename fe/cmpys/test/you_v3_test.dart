import 'dart:async';

import 'package:cmpys/app/router.dart';
import 'package:cmpys/core/ui/v3/v3.dart';
import 'package:cmpys/features/auth/controllers/auth_controller.dart';
import 'package:cmpys/features/auth/controllers/session_controller.dart';
import 'package:cmpys/features/cmpys/data/cmpys_ideas_provider.dart';
import 'package:cmpys/features/cmpys/data/cmpys_record_data.dart';
import 'package:cmpys/features/cmpys/data/cmpys_seed.dart';
import 'package:cmpys/features/cmpys/presentation/detail_screens.dart';
import 'package:cmpys/features/cmpys/presentation/idol_detail_screen.dart';
import 'package:cmpys/features/cmpys/presentation/record_screen.dart';
import 'package:cmpys/features/cmpys/presentation/you_screen.dart';
import 'package:cmpys/features/cmpys/state/cmpys_store.dart';
import 'package:cmpys/features/cmpys/state/plan_data.dart';
import 'package:cmpys/features/cmpys/state/today_data.dart';
import 'package:cmpys/features/plan/data/plan_repository.dart';
import 'package:cmpys/features/plan/models/plan_models.dart';
import 'package:cmpys/features/plan/presentation/reading_library_screen.dart';
import 'package:cmpys/features/plan/state/current_plan_provider.dart';
import 'package:cmpys/features/session/data/content_resources_repository.dart';
import 'package:cmpys/features/session/data/session_repository.dart';
import 'package:cmpys/features/session/models/content_resource.dart';
import 'package:cmpys/features/session/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// F4 (`v3/you.jsx` YouTab and EditProfile): the profile header with the edit
// sheet and its unsaved-changes guard, the three stat cards, the mentor
// portrait (Mentor context only; no device mentor switch), Library rows,
// device-only settings toggles, "Privacy & data", "About CMPYS" and the
// Log out sheet.

class _Store extends CmpysStore {
  _Store({int wins = 2, int notes = 1, int age = 27, String? sessionId}) {
    state = state.copyWith(
      sessionId: sessionId,
      user: CmpysUser(
        name: 'Ana',
        age: age,
        interests: ['Investing', 'Writing'],
      ),
      idol: cmpysIdols.first,
      achievements: [
        for (var i = 0; i < wins; i++)
          CmpysWin(
            id: 'w$i',
            title: 'Win $i',
            dim: 'practice',
            age: 27,
            impact: 1,
            source: 'manual',
            assessed: false,
          ),
      ],
      notes: [
        for (var i = 0; i < notes; i++)
          CmpysNote(
            id: 'n$i',
            kind: 'chat',
            title: 'Note $i',
            body: 'Body',
            when: 'Today',
          ),
      ],
    );
  }

  int resets = 0;

  @override
  Future<void> reset() async {
    resets++;
    await super.reset();
  }
}

/// A store whose state a test can set directly (an older build's data).
class _DriftStore extends CmpysStore {
  void force(CmpysState next) => state = next;
}

class _Auth extends StateNotifier<AuthState> implements AuthController {
  _Auth() : super(const AuthUnauthenticated());
  int logouts = 0;

  @override
  Future<void> logout() async => logouts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends StateNotifier<SessionState>
    implements SessionController {
  _Session() : super(const SessionUnauthenticated());
  int logouts = 0;

  @override
  Future<void> onLogout() async => logouts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serves [_plan] to the REAL [currentPlanProvider] and records every other
/// call (a job check, a generation request), so a refresh or a paid
/// `/plans/generate` would show up.
class _Plans implements PlanRepository {
  int gets = 0;
  final other = <String>[];

  @override
  Future<BackendPlan?> getCurrentPlan() async {
    gets++;
    return _plan;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    other.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

/// Records the plan provider's recovery path (`getLatestSession` before a
/// generation request).
class _Sessions implements SessionRepository {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return super.noSuchMethod(invocation);
  }
}

class _Content implements ContentResourcesRepository {
  @override
  Future<List<ContentResource>> listLibraryResources({
    String? kind,
    String? query,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async => const [];

  @override
  Future<ContentResource?> getContinueReading() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BackendPlanItem _item(
  String id, {
  String type = 'project',
  String status = 'not_started',
  int progress = 0,
}) => BackendPlanItem(
  id: id,
  title: id,
  type: type,
  description: '',
  weekStart: 1,
  weekEnd: 1,
  successMetric: '',
  estimatedHours: 2,
  status: status,
  progressPercent: progress,
);

/// Missions: one done, one at 40 %, two untouched → (1 + .4) / 4 = 35 %.
/// The server's own figure (77) must not be what the card shows. The plan
/// names the store's mentor, so the real plan provider accepts it.
final _plan = BackendPlan(
  id: 'plan-1',
  durationWeeks: 12,
  weeklyHours: 5,
  overallProgress: 77,
  idolName: cmpysIdols.first.name,
  items: [
    _item('m1', status: 'completed', progress: 100),
    _item('m2', status: 'in_progress', progress: 40),
    _item('m3'),
    _item('m4'),
    _item('h1', type: 'habit', status: 'completed', progress: 100),
  ],
);

late _Store _store;
late _Auth _auth;
late _Session _session;
late _Plans _plans;
late _Sessions _sessions;

Future<void> _mount(
  WidgetTester tester, {
  _Store? store,
  Future<StreakSummary?> Function()? streak,
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _store = store ?? _Store();
  _auth = _Auth();
  _session = _Session();
  _plans = _Plans();
  _sessions = _Sessions();
  final router = GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const CmpysYouScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (_, _) => const Scaffold(body: Text('AUTH SCREEN')),
      ),
      GoRoute(
        path: AppRoutes.ideas,
        builder: (_, _) => const Scaffold(body: Text('IDEA REELS')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cmpysStoreProvider.overrideWith((ref) => _store),
        authControllerProvider.overrideWith((ref) => _auth),
        sessionControllerProvider.overrideWith((ref) => _session),
        // The real currentPlanProvider over fake repositories.
        planRepositoryProvider.overrideWithValue(_plans),
        sessionRepositoryProvider.overrideWithValue(_sessions),
        contentResourcesRepositoryProvider.overrideWithValue(_Content()),
        cmpysIdeasProvider.overrideWith((ref) async => const []),
        idolTimelineProvider.overrideWith((ref, name) async => const []),
        todayStreakProvider.overrideWith(
          (ref) =>
              streak?.call() ??
              Future.value(const StreakSummary(current: 6, longest: 9)),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _iconButton(String label) =>
    find.byWidgetPredicate((w) => w is V3IconButton && w.label == label);

Finder _editFields() => find.descendant(
  of: find.byType(CmpysEditProfileScreen),
  matching: find.byType(TextField),
);

V3Button _button(WidgetTester tester, String label) => tester.widget<V3Button>(
  find.ancestor(of: find.text(label), matching: find.byType(V3Button)),
);

Future<void> _openEditDirty(WidgetTester tester) async {
  await tester.tap(_iconButton('Edit profile'));
  await tester.pumpAndSettle();
  expect(find.text('Edit profile'), findsOneWidget);
  await tester.enterText(_editFields().first, 'Ana Lu');
  await tester.pump();
}

const _guardCopy = 'You have unsaved changes.';
const _ageHint = 'Enter an age from 14 to 80';

Session _sessionFor(String id, {required int age, List<String>? interests}) =>
    Session(
      id: id,
      phase: SessionPhase.completed,
      userAge: age,
      userFinancialStatus: '',
      userInterests: interests ?? const ['History'],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('edit_profile_guard_on_dirty_close', (tester) async {
    await _mount(tester);

    // A clean sheet closes straight away.
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
    expect(find.text(_guardCopy), findsNothing);

    // Dirty: the close button, the scrim, a drag and system back all stop
    // at the guard instead of closing.
    await _openEditDirty(tester);

    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_guardCopy), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(195, 20)); // scrim
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    expect(find.text(_guardCopy), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    expect(find.text(_guardCopy), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // system back
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    expect(find.text(_guardCopy), findsOneWidget);
    expect(_store.state.user.name, 'Ana');
    expect(tester.takeException(), isNull);
  });

  testWidgets('guard: Keep editing returns to the form with the edits', (
    tester,
  ) async {
    await _mount(tester);
    await _openEditDirty(tester);
    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text(_guardCopy), findsNothing);
    expect(find.text('Ana Lu'), findsOneWidget);
    expect(find.byType(CmpysEditProfileScreen), findsOneWidget);
    expect(_store.state.user.name, 'Ana');
  });

  testWidgets('guard: Discard closes without saving', (tester) async {
    await _mount(tester);
    await _openEditDirty(tester);
    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
    expect(_store.state.user.name, 'Ana');
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('guard: Save changes runs the profile save and closes', (
    tester,
  ) async {
    await _mount(tester);
    await _openEditDirty(tester);
    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Profile updated on this device'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
    expect(_store.state.user.name, 'Ana Lu');
    expect(_store.state.user.age, 27);
    expect(find.text('Ana Lu'), findsOneWidget);
  });

  testWidgets('edit sheet saves age and interests; Save waits for a change', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    expect(_button(tester, 'Save').disabled, isTrue);
    await tester.enterText(_editFields().at(1), '31');
    await tester.tap(find.text('Science'));
    await tester.pump();
    expect(_button(tester, 'Save').disabled, isFalse);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_store.state.user.age, 31);
    expect(_store.state.user.interests, containsAll(['Investing', 'Science']));
  });

  testWidgets('re-selecting the same interests is not an unsaved change', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    // Remove and re-add: same set, different order.
    await tester.tap(find.text('Investing'));
    await tester.pump();
    await tester.tap(find.text('Investing'));
    await tester.pump();
    expect(_button(tester, 'Save').disabled, isTrue);
    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysEditProfileScreen), findsNothing);
  });

  testWidgets('an invalid age shows the range and disables Save, in the '
      'sheet and in the guard', (tester) async {
    await _mount(tester);
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(_editFields().at(1), '9');
    await tester.pump();
    expect(find.text(_ageHint), findsOneWidget);
    expect(_button(tester, 'Save').disabled, isTrue);

    await tester.tap(_iconButton('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_guardCopy), findsOneWidget);
    expect(find.text(_ageHint), findsOneWidget);
    expect(_button(tester, 'Save changes').onPressed, isNull);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text(_guardCopy), findsOneWidget);
    expect(_store.state.user.age, 27);
  });

  testWidgets('a stored age of 0 opens blank and explains the disabled Save', (
    tester,
  ) async {
    await _mount(tester, store: _Store(age: 0));
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    final age = tester.widget<TextField>(_editFields().at(1));
    expect(age.controller!.text, isEmpty);
    expect(find.text(_ageHint), findsNothing); // nothing to save yet
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.text(_ageHint), findsOneWidget);
    expect(_button(tester, 'Save').disabled, isTrue);
  });

  testWidgets('after intake the age is read-only, with why (owner decision '
      '3)', (tester) async {
    await _mount(tester, store: _Store(sessionId: 'session-1'));
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    final age = tester.widget<TextField>(_editFields().at(1));
    expect(age.controller!.text, '27');
    expect(age.enabled, isFalse);
    expect(
      find.text('Your age is set at intake so comparisons stay fair.'),
      findsOneWidget,
    );
    // The name and interests still save, and the age stays.
    await tester.enterText(_editFields().first, 'Ana Lu');
    await tester.pump();
    expect(_button(tester, 'Save').disabled, isFalse);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_store.state.user.name, 'Ana Lu');
    expect(_store.state.user.age, 27);
  });

  testWidgets('after intake an unknown age (0) still lets the name save', (
    tester,
  ) async {
    await _mount(tester, store: _Store(age: 0, sessionId: 'session-1'));
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_editFields().at(1)).enabled, isFalse);
    await tester.tap(find.text('History'));
    await tester.pump();
    expect(find.text(_ageHint), findsNothing);
    expect(_button(tester, 'Save').disabled, isFalse);
  });

  testWidgets('before intake the age is still editable, with no note', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(_iconButton('Edit profile'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_editFields().at(1)).enabled, isNot(false));
    expect(
      find.text('Your age is set at intake so comparisons stay fair.'),
      findsNothing,
    );
  });

  testWidgets('logout_sheet_confirms', (tester) async {
    await _mount(tester);
    await tester.tap(find.widgetWithText(V3Button, 'Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    expect(find.text('Stay signed in'), findsOneWidget);
    // The Record lives on this device and is cleared too, wins saved to the
    // account included (R3-I2): the copy never implies they stay.
    expect(
      find.text(
        'Your plan, practice and reading progress are saved to your '
        'account. Your record, notes and saved items on this device will '
        'be cleared.',
      ),
      findsOneWidget,
    );

    // Staying signed in closes the sheet and logs nothing out.
    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsNothing);
    expect(_auth.logouts, 0);
    expect(_session.logouts, 0);
    expect(_store.resets, 0);

    await tester.tap(find.widgetWithText(V3Button, 'Log out'));
    await tester.pumpAndSettle();
    final confirm = find.descendant(
      of: find.byKey(V3Sheet.panelKey),
      matching: find.text('Log out'),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(_store.resets, 1);
    expect(_auth.logouts, 1);
    expect(_session.logouts, 1);
    expect(find.text('AUTH SCREEN'), findsOneWidget);
  });

  testWidgets(
    'dismissing the Log out sheet by scrim or drag logs nothing out',
    (tester) async {
      await _mount(tester);
      await tester.tap(find.widgetWithText(V3Button, 'Log out'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 20)); // scrim
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsNothing);

      await tester.tap(find.widgetWithText(V3Button, 'Log out'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(V3Sheet.handleKey), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsNothing);

      expect(_store.resets, 0);
      expect(_auth.logouts, 0);
      expect(_session.logouts, 0);
      expect(find.text('AUTH SCREEN'), findsNothing);
    },
  );

  testWidgets('the You tab cannot change the session mentor; Mentor context '
      'leaves the plan provider alone', (tester) async {
    await _mount(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CmpysYouScreen)),
    );
    expect(container.read(currentPlanProvider).status, CurrentPlanStatus.ready);
    expect(_plans.gets, 1);

    // No mentor switch anywhere on the tab.
    expect(find.text('Your mentor'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Change mentor'), findsNothing);

    // The portrait opens Mentor context, and coming back changes nothing.
    await tester.tap(find.text('Your mentor'));
    await tester.pumpAndSettle();
    expect(find.byType(CmpysIdolDetailScreen), findsOneWidget);
    expect(find.text('Change mentor'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CmpysIdolDetailScreen), findsNothing);

    expect(_store.state.idol.id, cmpysIdols.first.id);
    final plan = container.read(currentPlanProvider);
    expect(plan.status, CurrentPlanStatus.ready);
    expect(plan.plan, same(_plan));
    expect(_plans.gets, 1); // no refresh
    expect(_plans.other, isEmpty); // no job check, no generatePlan
    expect(_sessions.calls, isEmpty); // the generation path never started
  });

  testWidgets('Privacy & data shows the coming-soon toast; About shows build', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.tap(find.text('Privacy & data'));
    await tester.pump();
    expect(find.text('Privacy center is coming soon'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('About CMPYS'));
    await tester.pump();
    expect(find.text('CMPYS 3.0 · build 2026.10'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('stat cards use planOverallProgress, the streak and wins', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    final pct = (planOverallProgress(_plan) * 100).round();
    expect(pct, 35);
    expect(find.text('$pct%'), findsOneWidget);
    expect(find.text('77%'), findsNothing);
    expect(find.text('plan complete'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('wins recorded'), findsOneWidget);
    // Each card is one stop for screen readers.
    expect(
      tester.getSemantics(find.text('plan complete')),
      containsSemantics(label: '35%\nplan complete'),
    );
    semantics.dispose();
  });

  testWidgets('the streak shows a dash while /streak loads or fails', (
    tester,
  ) async {
    final pending = Completer<StreakSummary?>();
    await _mount(tester, streak: () => pending.future);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    pending.complete(const StreakSummary(current: 3, longest: 3));
    // The count-up starts after its 100 ms stagger (a timer, not a frame).
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('a failed /streak also shows a dash', (tester) async {
    await _mount(tester, streak: () => Future.error(StateError('offline')));
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('only the working settings toggle shows, and reads as a toggle '
      '(owner decision 4)', (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    // The toggles that change nothing yet are hidden, with their footnote.
    for (final key in ['reminder', 'mentorPing', 'digest']) {
      expect(find.byKey(ValueKey<String>('you-toggle-$key')), findsNothing);
    }
    expect(find.text('Daily reminder'), findsNothing);
    expect(find.text('Mentor messages'), findsNothing);
    expect(find.text('Weekly comparison digest'), findsNothing);
    expect(find.textContaining('switched on'), findsNothing);
    expect(find.textContaining('Preferences are saved'), findsNothing);

    const haptics = ValueKey<String>('you-toggle-haptics');
    // One merged node per row: the label once, the toggled state, the tap.
    expect(
      tester.getSemantics(find.byKey(haptics)),
      containsSemantics(
        label: 'Sound & haptics',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byKey(haptics));
    await tester.pumpAndSettle();
    expect(_store.state.settings.haptics, isFalse);
    expect(
      tester.getSemantics(find.byKey(haptics)),
      containsSemantics(hasToggledState: true, isToggled: false),
    );
    // Privacy and About stay.
    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.text('About CMPYS'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('each Library row shows its count and opens its screen', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.text('Guides, originals, excerpts'), findsOneWidget);
    expect(find.text('1 on this device'), findsOneWidget); // notes
    expect(find.text('0 on this device'), findsOneWidget); // saved

    Future<void> opens(String row, Finder screen) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(screen, findsOneWidget, reason: row);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(screen, findsNothing, reason: row);
    }

    await opens('Reading', find.byType(ReadingLibraryScreen));
    await opens('Idea reels', find.text('IDEA REELS'));
    await opens('Your record', find.byType(CmpysRecordScreen));
    await opens('Notes', find.byType(CmpysNotesScreen));
    await opens('Saved', find.byType(CmpysSavedScreen));
    expect(tester.takeException(), isNull);
  });

  group('syncFromSession and the profile', () {
    test('the session’s age is the source of truth; edited interests stay '
        '(owner decision 3)', () async {
      final store = _DriftStore();
      await store.ready;
      store.syncFromSession(_sessionFor('s1', age: 24));
      expect(store.state.user.age, 24);
      expect(store.state.user.interests, ['History']);
      expect(store.state.ageLocked, isTrue);

      // A device edit can't change the age once an intake session exists.
      store.updateUser(name: 'Ana', age: 31, interests: ['Design']);
      expect(store.state.user.age, 24);
      expect(store.state.user.interests, ['Design']);

      // An age that drifted on this device (an older build's edit) is
      // replaced by the session's on the next sync.
      store.force(
        store.state.copyWith(
          user: CmpysUser(name: 'Ana', age: 31, interests: const ['Design']),
        ),
      );
      store.syncFromSession(_sessionFor('s1', age: 24));
      expect(store.state.user.age, 24);
      expect(store.state.user.interests, ['Design']);
      expect(store.state.user.name, 'Ana');

      // A new session still brings its own profile.
      store.syncFromSession(
        _sessionFor('s2', age: 26, interests: ['Business']),
      );
      expect(store.state.user.age, 26);
      expect(store.state.user.interests, ['Business']);
      expect(store.state.user.name, 'Ana');
    });

    test('before intake the age can be edited', () {
      final store = CmpysStore();
      expect(store.state.ageLocked, isFalse);
      store.updateUser(age: 31);
      expect(store.state.user.age, 31);
      store.dispose();
    });

    test(
      'an empty local age or interests is filled from the session',
      () async {
        final store = CmpysStore();
        await store.ready;
        store.syncFromSession(_sessionFor('s1', age: 24));
        store.updateUser(age: 0, interests: const []);
        store.syncFromSession(
          _sessionFor('s1', age: 25, interests: ['Writing']),
        );
        expect(store.state.user.age, 25);
        expect(store.state.user.interests, ['Writing']);
      },
    );
  });
}
