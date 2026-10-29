import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Marks the pushed page it wraps as one the book-narration dock shows over.
///
/// The design shows the dock on the tab roots and on the book, library,
/// mission and record pages (v3/app.jsx), not on lessons, practice, web or
/// video. Those pages wrap their content in this; the tab shell asks
/// [allows] about the page on top of the current branch. The mark lasts only
/// while the wrapper is mounted, so a page that swaps it out (a mission that
/// turns out to be a habit) drops the dock.
class NarrationDockPage extends StatefulWidget {
  const NarrationDockPage({super.key, required this.child});

  final Widget child;

  /// Mounted markers per route.
  static final Expando<int> _marks = Expando<int>('narration dock pages');
  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Whether [route] currently holds a mounted [NarrationDockPage].
  static bool allows(Route<dynamic> route) => (_marks[route] ?? 0) > 0;

  /// Bumps when a page is marked or unmarked, so the shell can look again.
  static Listenable get changes => _revision;

  /// After the frame: marks change while the tree builds or unmounts, when
  /// the shell may not rebuild.
  static void _changed() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _revision.value++)
      ..ensureVisualUpdate();
  }

  @override
  State<NarrationDockPage> createState() => _NarrationDockPageState();
}

class _NarrationDockPageState extends State<NarrationDockPage> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _unmark();
    _route = route;
    if (route == null) return;
    NarrationDockPage._marks[route] =
        (NarrationDockPage._marks[route] ?? 0) + 1;
    NarrationDockPage._changed();
  }

  void _unmark() {
    final route = _route;
    if (route == null) return;
    final marks = (NarrationDockPage._marks[route] ?? 1) - 1;
    NarrationDockPage._marks[route] = marks > 0 ? marks : null;
    _route = null;
    NarrationDockPage._changed();
  }

  @override
  void dispose() {
    _unmark();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
