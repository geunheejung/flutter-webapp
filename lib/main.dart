import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter + Next.js',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Next.js in InAppWebView'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  InAppWebViewController? _controller;

  late final String _devUrl =
      Platform.isIOS ? "http://localhost:3000" : "http://10.0.2.2:3000";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.resumed) {
      _dispatchToWeb("app:foreground");
    } else if (state == AppLifecycleState.paused) {
      _dispatchToWeb("app:background");
    }
  }

  Future<void> _dispatchToWeb(String eventName) async {
    try {
      await _controller?.evaluateJavascript(
        source: "window.dispatchEvent(new Event('$eventName'));",
      );
    } catch (_) {}
  }

  InAppWebViewSettings _baseSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        isInspectable: true,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller?.reload()),
        ],
      ),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_devUrl)),
          initialSettings: _baseSettings(),
          onWebViewCreated: (c) => _controller = c,

          // ✅ window.open → 새 라우트로 푸시
          onCreateWindow: (parent, req) async {
            final target = req.request.url;
            if (target == null) return false;

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PopupWebView(
                  initialUrl: target,
                  // 팝업에서도 같은 기본 설정 사용 (필요하면 별도로 생성해서 override)
                  settings: _baseSettings(),
                ),
                fullscreenDialog: true,
              ),
            );
            return true;
          },

          // 비-HTTP(s) 스킴은 외부 앱으로 위임
          shouldOverrideUrlLoading: (c, nav) async {
            final url = nav.request.url;
            if (url == null) return NavigationActionPolicy.ALLOW;

            final scheme = url.scheme.toLowerCase();
            final isHttp = scheme == 'http' || scheme == 'https';
            if (!isHttp) {
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },

          onLoadStart: (c, url) => debugPrint("➡️ main start: $url"),
          onLoadStop: (c, url) async {
            debugPrint("✅ main stop: $url");
            await _dispatchToWeb("app:foreground");
          },

          // ❌ error.code → ✅ error.errorCode
          onReceivedError: (c, request, error) {
  // 버전마다 code/errorCode가 달라서 동적으로 안전하게 접근
            final dyn = error as dynamic;
            final code = (dyn.errorCode ?? dyn.code) ?? 'n/a';
            final type = error.type;           // 이건 공통으로 제공됨
            final desc = error.description;    // 이건 공통으로 제공됨
            debugPrint("❌ main web error: $code $type $desc");
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _controller?.evaluateJavascript(
          source: "console.log('Hello from Flutter!')",
        ),
        child: const Icon(Icons.code),
      ),
    );
  }
}

/// 새 창(팝업) 전용 WebView
class PopupWebView extends StatefulWidget {
  final WebUri initialUrl;
  final InAppWebViewSettings settings;

  const PopupWebView({
    super.key,
    required this.initialUrl,
    required this.settings,
  });

  @override
  State<PopupWebView> createState() => _PopupWebViewState();
}

class _PopupWebViewState extends State<PopupWebView> {
  InAppWebViewController? _controller;
  double _progress = 0;

  Future<void> _injectCloseBridge(InAppWebViewController c) async {
    // ❌ addJavaScriptHandler는 void 반환 → await 제거
    c.addJavaScriptHandler(
      handlerName: 'popupClose',
      callback: (_) async {
        if (mounted) Navigator.of(context).maybePop();
      },
    );

    await c.evaluateJavascript(source: """
      (function() {
        try {
          const _close = window.close;
          window.close = function() {
            if (window.flutter_inappwebview) {
              window.flutter_inappwebview.callHandler('popupClose');
            } else {
              try { _close && _close(); } catch (e) {}
            }
          };
        } catch (e) {}
      })();
    """);
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ copyWith가 없으므로, 필요 override가 있으면 새 Settings를 만들어 전달합니다.
    final popupSettings = InAppWebViewSettings(
      javaScriptEnabled: widget.settings.javaScriptEnabled,
      mediaPlaybackRequiresUserGesture: widget.settings.mediaPlaybackRequiresUserGesture,
      allowsInlineMediaPlayback: widget.settings.allowsInlineMediaPlayback,
      javaScriptCanOpenWindowsAutomatically: true, // 팝업 안 팝업 대응
      supportMultipleWindows: true,
      sharedCookiesEnabled: widget.settings.sharedCookiesEnabled,
      thirdPartyCookiesEnabled: widget.settings.thirdPartyCookiesEnabled,
      isInspectable: widget.settings.isInspectable,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Popup"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '닫기',
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller?.reload()),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: widget.initialUrl),
              initialSettings: popupSettings,
              onWebViewCreated: (c) async {
                _controller = c;
                await _injectCloseBridge(c);
              },

              // 팝업 내부의 window.open → 또 새 화면으로
              onCreateWindow: (parent, req) async {
                final target = req.request.url;
                if (target == null) return false;

                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PopupWebView(
                      initialUrl: target,
                      settings: popupSettings,
                    ),
                    fullscreenDialog: true,
                  ),
                );
                return true;
              },

              shouldOverrideUrlLoading: (c, nav) async {
                final url = nav.request.url;
                if (url == null) return NavigationActionPolicy.ALLOW;

                final scheme = url.scheme.toLowerCase();
                final isHttp = scheme == 'http' || scheme == 'https';
                if (!isHttp) {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },

              onProgressChanged: (c, progress) {
                setState(() => _progress = progress / 100.0);
              },
              onLoadStart: (c, url) => debugPrint("➡️ popup start: $url"),
              onLoadStop: (c, url) => debugPrint("✅ popup stop: $url"),

              // ❌ error.code → ✅ error.errorCode
              onReceivedError: (c, request, error) {
  final dyn = error as dynamic;
  final code = (dyn.errorCode ?? dyn.code) ?? 'n/a';
  final type = error.type;
  final desc = error.description;
  debugPrint("❌ popup web error: $code $type $desc");
},
            ),
            if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          ],
        ),
      ),
    );
  }
}