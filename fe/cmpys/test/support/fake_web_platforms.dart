import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Installs a [FakeWebViewPlatform] for the current test and restores the
/// previous platform when the test ends.
///
/// The platform interface refuses `null`, so when there was no platform
/// before (the normal case under `flutter test`), [UnsetWebViewPlatform] goes
/// back in its place: building a web view fails again as it would have.
FakeWebViewPlatform useFakeWebViewPlatform() {
  final previous = WebViewPlatform.instance;
  final fake = FakeWebViewPlatform();
  WebViewPlatform.instance = fake;
  addTearDown(
    () => WebViewPlatform.instance = previous ?? UnsetWebViewPlatform(),
  );
  return fake;
}

/// Stands for "no web view platform": every web view it is asked for fails
/// with the same message as an unset `WebViewPlatform.instance`.
class UnsetWebViewPlatform extends WebViewPlatform {
  static Never _unset() => throw AssertionError(
    'A platform implementation for `webview_flutter` has not been set.',
  );

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _unset();

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _unset();

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _unset();
}

/// A [WebViewPlatform] for widget tests. The real `WebViewController` and
/// `NavigationDelegate` run on top of it, so a test drives the screen through
/// the delegate callbacks the platform would fire.
class FakeWebViewPlatform extends WebViewPlatform {
  final controllers = <FakeWebViewController>[];

  FakeWebViewController get controller => controllers.last;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  FakeNavigationDelegate? delegate;
  final loaded = <Uri>[];
  final scripts = <String>[];
  final scrolls = <int>[];
  String? url;
  bool canGoBackValue = false;
  bool canGoForwardValue = false;
  int goBackCalls = 0;
  int goForwardCalls = 0;
  int reloadCalls = 0;

  /// Fires the platform's "page started → URL change → page finished"
  /// sequence for [to], as a real navigation would.
  void navigate(String to, {bool finish = true}) {
    url = to;
    delegate?.onPageStarted?.call(to);
    delegate?.onUrlChange?.call(UrlChange(url: to));
    if (finish) delegate?.onPageFinished?.call(to);
  }

  /// Fires what iOS fires when a main-frame navigation to [to] fails: page
  /// started, then a main-frame resource error, and no page finished. The
  /// web view stays on the page it had.
  void failNavigation(String to) {
    delegate?.onPageStarted?.call(to);
    delegate?.onWebResourceError?.call(
      WebResourceError(
        errorCode: -1003,
        description: 'A server with the specified hostname could not be found.',
        isForMainFrame: true,
        url: to,
      ),
    );
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded.add(params.uri);
    url = params.uri.toString();
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<String?> currentUrl() async => url;

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<bool> canGoForward() async => canGoForwardValue;

  @override
  Future<void> goBack() async => goBackCalls++;

  @override
  Future<void> goForward() async => goForwardCalls++;

  @override
  Future<void> reload() async => reloadCalls++;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) async =>
      scripts.add(javaScript);

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}

  @override
  Future<void> scrollBy(int x, int y) async => scrolls.add(y);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  UrlChangeCallback? onUrlChange;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async => this.onNavigationRequest = onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async =>
      this.onPageStarted = onPageStarted;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      this.onPageFinished = onPageFinished;

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async =>
      this.onProgress = onProgress;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async =>
      this.onUrlChange = onUrlChange;

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async => this.onWebResourceError = onWebResourceError;

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  static const pageKey = ValueKey('fake-web-view');

  /// Taps that reached the page itself (not a cover above it).
  static int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => taps++,
    child: const ColoredBox(key: pageKey, color: Color(0xFFFFFFFF)),
  );
}

/// A [UrlLauncherPlatform] that records what the app asked to open.
class FakeUrlLauncher extends UrlLauncherPlatform {
  final launched = <({String url, PreferredLaunchMode mode})>[];
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url: url, mode: options.mode));
    return result;
  }

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
}

/// Taps that reached the fake page itself, under any cover the screen draws.
int get fakeWebViewTaps => _FakeWebViewWidget.taps;
set fakeWebViewTaps(int value) => _FakeWebViewWidget.taps = value;
