import 'dart:io'; // Platform 분기
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart'; // 외부 스킴 처리

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

/// 👇 WidgetsBindingObserver 추가: 앱 라이프사이클 감지
class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  InAppWebViewController? _controller;

  // 시뮬레이터/에뮬레이터 기본값 (실기기는 맥 IP로 바꾸세요)
  late final String _devUrl = Platform.isIOS
      ? "http://localhost:3000"   // iOS 시뮬레이터
      : "http://10.0.2.2:3000";   // Android 에뮬레이터

  @override
  void initState() {
    super.initState();
    // 👇 앱 라이프사이클 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 👇 Flutter 앱 상태 변화를 WebView(웹)로 통지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;

    // 커스텀 이벤트를 window 로 디스패치 (웹에서 addEventListener('app:foreground'…) 로 수신)
    if (state == AppLifecycleState.resumed) {
      _dispatchToWeb("app:foreground");
    } else if (state == AppLifecycleState.paused) {
      _dispatchToWeb("app:background");
    }
  }

  Future<void> _dispatchToWeb(String eventName) async {
    try {
      await _controller?.evaluateJavascript(
        source: "window.dispatchEvent(new Event('$eventName'));"
      );
    } catch (e) {
      debugPrint("JS dispatch error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
          ),
        ],
      ),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_devUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,

            // NextAuth / 팝업 / 디버깅 편의
            sharedCookiesEnabled: true,                 // iOS 쿠키 공유
            thirdPartyCookiesEnabled: true,             // (Android)
            javaScriptCanOpenWindowsAutomatically: true,
            supportMultipleWindows: true,
            isInspectable: true,                        // Safari/Chrome DevTools 허용
          ),

          onWebViewCreated: (c) {
            _controller = c;
          },

          // 팝업(window.open) → 같은 WebView로 열기
          onCreateWindow: (c, req) async {
            final target = req.request.url;
            if (target != null) {
              _controller?.loadUrl(urlRequest: URLRequest(url: target));
            }
            return true;
          },

          // 비-HTTP(s) 스킴은 외부 앱으로 넘김
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

          // 로드 시점에 한 번 foreground 신호를 보내 초기 연결 유도(선택)
          onLoadStop: (c, url) async {
            debugPrint("✅ stop: $url");
            await _dispatchToWeb("app:foreground");
          },

          onLoadStart: (c, url) => debugPrint("➡️ start: $url"),
          onReceivedError: (c, request, error) =>
              debugPrint("❌ web error: ${error.description}"),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _controller?.evaluateJavascript(
              source: "console.log('Hello from Flutter!')");
        },
        child: const Icon(Icons.code),
      ),
    );
  }
}