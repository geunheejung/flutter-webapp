import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter + Next.js',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
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
  InAppWebViewController? _childController;

  late final String _devUrl = "http://10.0.2.2:3000";

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

  Future<void> _notifyParentOpened() async {
    try {
      await _controller?.evaluateJavascript(
        source: "window.dispatchEvent(new Event('app:childWindowOpened'));",
      );
    } catch (_) {}
  }

  Future<void> _notifyParentClosed() async {
    try {
      await _controller?.evaluateJavascript(
        source: "window.dispatchEvent(new Event('app:childWindowClosed'));",
      );
    } catch (_) {}
  }

  bool _isHttp(WebUri u) {
    final s = u.scheme.toLowerCase();
    return s == 'http' || s == 'https';
  }

  // ====== NEW: 풀스크린 + 좌/상 5% 비움 Dialog ======
  Future<void> openChildWebViewDialog(
    BuildContext context, {
    required CreateWindowAction req,
  }) async {
    await _notifyParentOpened();

    final mq = MediaQuery.of(context);
    final leftPad = mq.size.width * 0.05;  // 좌측 5%
    final topPad  = mq.size.height * 0.05; // 상단 5%

    Future<void> closeAndNotify() async {
      Navigator.of(context, rootNavigator: true).maybePop();
      await _notifyParentClosed();
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'child-webview',
      pageBuilder: (_, __, ___) {
        return Stack(
          children: [
            // 화면 전체를 덮는다
            Positioned.fill(
              // 좌/상 5%만 비우고 나머지 꽉 채움
              left: leftPad,
              top: topPad,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Scaffold(
                  backgroundColor: Theme.of(context).dialogBackgroundColor,
                  body: SafeArea(
                    child: Column(
                      children: [
                        // 상단 바: 그랩핸들 + 닫기
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 8, left: 12, right: 12, bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '닫기',
                                onPressed: closeAndNotify,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        // 자식 WebView (남은 영역을 정확히 차지)
                        Expanded(
                          child: InAppWebView(
                            windowId:
                                Platform.isAndroid ? req.windowId : null,
                            initialUrlRequest: (Platform.isIOS ||
                                    (Platform.isAndroid &&
                                        req.windowId == null))
                                ? req.request
                                : null,
                            initialSettings: InAppWebViewSettings(
                              javaScriptEnabled: true,
                              allowsInlineMediaPlayback: true,
                              javaScriptCanOpenWindowsAutomatically: true,
                              supportMultipleWindows: true,
                              isInspectable: true,
                            ),
                            // 자식 WebView임을 알리는 이벤트
                            initialUserScripts:
                                UnmodifiableListView<UserScript>([
                              UserScript(
                                source:
                                    "window.dispatchEvent(new Event('app:webviewIsChild'));",
                                injectionTime:
                                    UserScriptInjectionTime.AT_DOCUMENT_START,
                              ),
                            ]),
                            onWebViewCreated: (child) =>
                                _childController = child,
                            onLoadStop: (c, url) =>
                                debugPrint("🪟 Child loaded: $url"),
                            // 자식 팝업 체인 방지 → 같은 창에서 로드
                            onCreateWindow: (childCtrl, childReq) async {
                              final u = childReq.request.url;
                              if (u != null && _isHttp(u)) {
                                await childCtrl.loadUrl(
                                  urlRequest: URLRequest(url: u),
                                );
                                return false;
                              }
                              if (u != null && await canLaunchUrl(u)) {
                                await launchUrl(u,
                                    mode: LaunchMode.externalApplication);
                                return false;
                              }
                              return false;
                            },
                            onCloseWindow: (_) async => closeAndNotify(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    );
  }
  // ===============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_devUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            sharedCookiesEnabled: true,
            thirdPartyCookiesEnabled: true,
            javaScriptCanOpenWindowsAutomatically: true,
            supportMultipleWindows: true,
            isInspectable: true,
          ),
          onWebViewCreated: (c) => _controller = c,
          onConsoleMessage: (controller, m) =>
              debugPrint("📜 JS Console: ${m.message}"),

          // window.open 처리
          onCreateWindow: (controller, req) async {
            final target = req.request.url;

            // ANDROID: windowId가 없으면 부모에서 열기
            if (Platform.isAndroid && req.windowId == null) {
              if (target != null && _isHttp(target)) {
                await _controller?.loadUrl(urlRequest: URLRequest(url: target));
                return false;
              }
              if (target != null && await canLaunchUrl(target)) {
                await launchUrl(target, mode: LaunchMode.externalApplication);
                return false;
              }
              return false;
            }

            // iOS 또는 Android(windowId 있음): 커스텀 풀스크린 다이얼로그로 열기
            await openChildWebViewDialog(context, req: req);
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
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },

          onLoadStop: (c, url) async {
            await _dispatchToWeb("app:foreground");
          },
        ),
      ),
    );
  }
}