import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../bridge/insight.dart';
import '../ignition/agent_mask.dart';
import '../ignition/alert_center.dart';
import '../ignition/stash_hold.dart';
import '../ignition/wire_watch.dart';
import 'offline_scene.dart';

// ============================================================
// StreamScene — full-bleed WebView (gray content)
// ============================================================
// Hosts the destination URL with:
//   • Real device UA (via MaskedClient.agent)
//   • Both orientations, immersive system UI
//   • Handoff of non-http(s) schemes to the OS
//   • Redirect-loop recovery (max 3 retries)
//   • Live connectivity guard (700 ms debounce)
//   • Warm push URL delivery
//   • Native file upload (via MethodChannel to MainActivity.kt)
//   • Third-party cookies + media autoplay
//   • Safe-area CSS neutralisation + keyboard scroll fix
//   • Landscape safe zone that covers the camera cutout on both edges
// ============================================================

class StreamScene extends StatefulWidget {
  const StreamScene({
    super.key,
    required this.streamUrl,
    required this.stash,
    required this.alertCenter,
    required this.wireWatch,
  });

  final String streamUrl;
  final StashHold stash;
  final AlertCenter alertCenter;
  final WireWatch wireWatch;

  @override
  State<StreamScene> createState() => _StreamSceneState();
}

class _StreamSceneState extends State<StreamScene>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _spinnerOn = true;
  bool _offlineShown = false;
  String? _lastMainFrameUrl;
  int _redirectHits = 0;
  StreamSubscription<List<ConnectivityResult>>? _wireSub;
  Timer? _wireDebounce;

  // Clarity funnel state.
  bool _offerReached = false;
  bool _pageHadError = false;

  // Matches the channel name declared in MainActivity.kt.
  static const MethodChannel _uploadBridge =
      MethodChannel('emberdrift.volcano/pickfile');

  // Funnel regex patterns.
  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();
    _buildController();
    Insight.screen('web');
    Insight.event('web_open');

    widget.alertCenter.onOpenUrl = (String url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    _wireSub = widget.wireWatch.pulses.listen(_onWireChange);
  }

  void _onWireChange(List<ConnectivityResult> states) {
    final bool blank =
        states.isNotEmpty && states.every((ConnectivityResult r) => r == ConnectivityResult.none);
    if (!blank) {
      _wireDebounce?.cancel();
      return;
    }
    // Debounce: VPN handshake flicker briefly reports "none".
    _wireDebounce?.cancel();
    _wireDebounce = Timer(const Duration(milliseconds: 700), _showOffline);
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      Insight.event('web_background');
    }
  }

  void _buildController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(maskedClient.agent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..addJavaScriptChannel(
        'AegisInsight',
        onMessageReceived: (JavaScriptMessage m) => _onWebSignal(m.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _pageHadError = false;
          if (mounted) setState(() => _spinnerOn = true);
        },
        onPageFinished: (String url) {
          if (mounted) setState(() => _spinnerOn = false);
          _redirectHits = 0;
          _neutraliseSiteSafeArea();
          _injectKeyboardScroll();
          _installInsightProbe();
          _trackWebPage(url);
        },
        onWebResourceError: (WebResourceError err) {
          if (err.isForMainFrame != true) return;
          final String desc = err.description.toLowerCase();

          final bool loop = desc.contains('too_many_redirects') ||
              desc.contains('too many redirects') ||
              err.errorCode == -1007 ||
              err.errorCode == -9;
          if (loop && _lastMainFrameUrl != null && _redirectHits < 3) {
            _redirectHits++;
            _controller.loadRequest(Uri.parse(_lastMainFrameUrl!));
            return;
          }

          // Immediately mask the native error page (see pitfalls §4).
          if (mounted) setState(() => _spinnerOn = true);

          _pageHadError = true;
          final String reason = _classifyWebError(err);
          final String failed = _lastMainFrameUrl ?? widget.streamUrl;
          final String host = Uri.tryParse(failed)?.host ?? '';
          Insight.event('web_error');
          Insight.tag('web_error_reason', reason);
          Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
          if (host.isNotEmpty) Insight.tag('web_error_host', host);
          if (!_offerReached) {
            Insight.event('web_offer_unreachable');
            Insight.tag('offer_reached', 'false');
            Insight.tag('offer_unreachable_reason', reason);
          } else {
            Insight.event('web_error_after_load');
          }

          final bool dnsOrDown = desc.contains('name_not_resolved') ||
              desc.contains('err_name_not_resolved') ||
              desc.contains('internet_disconnected') ||
              desc.contains('network_changed') ||
              err.errorCode == -105 ||
              err.errorCode == -106 ||
              err.errorCode == -21;
          if (dnsOrDown) {
            _showOffline();
          } else {
            _probeAndMaybeShowOffline();
          }
        },
        onNavigationRequest: (NavigationRequest req) {
          final Uri? uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          const Set<String> inApp = <String>{
            'http', 'https', 'about', 'data', 'blob',
          };
          if (inApp.contains(uri.scheme)) {
            if (req.isMainFrame) _lastMainFrameUrl = req.url;
            return NavigationDecision.navigate;
          }
          Insight.event('web_external');
          Insight.tag('web_external_scheme', uri.scheme);
          _handoffToOs(uri);
          return NavigationDecision.prevent;
        },
      ));

    _tuneAndroid();
    _controller.loadRequest(Uri.parse(widget.streamUrl));
  }

  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    Insight.screenName(
        'web:${uri == null ? url : '${uri.host}${uri.path}'}');
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') ||
        d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') ||
        d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) { return 'connection_reset'; }
    if (d.contains('connection_closed') ||
        d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) { return 'ssl_error'; }
    if (d.contains('blocked')) { return 'blocked'; }
    return 'other';
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
      case 'form_submit':
        Insight.event('web_form_submit');
    }
  }

  void _installInsightProbe() {
    _controller.runJavaScript(r'''
(function(){
  if (window.__aegisInsight) return; window.__aegisInsight = true;
  function send(t){ try { AegisInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _tuneAndroid() {
    if (!Platform.isAndroid) return;
    if (_controller.platform is! AndroidWebViewController) return;
    final AndroidWebViewController a =
        _controller.platform as AndroidWebViewController;

    // Inline autoplay video (no full-screen takeover, no tap-to-start).
    a.setMediaPlaybackRequiresUserGesture(false);

    // Auto-grant Protected Media ID / MIDI-sysex so partner video
    // streams (Widevine, EME) play without an extra modal prompt.
    a.setOnPlatformPermissionRequest(
      (PlatformWebViewPermissionRequest req) => req.grant(),
    );

    // Wire the site's <input type="file"> to the native chooser.
    a.setOnShowFileSelector(_pickFiles);

    // Third-party cookies for OAuth / payment redirects.
    final AndroidWebViewCookieManager cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(a, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final List<Object?>? picked = await _uploadBridge
          .invokeMethod<List<Object?>>('pick', <String, Object>{
        'multiple': params.mode == FileSelectorMode.openMultiple,
        'mimeTypes': params.acceptTypes
            .where((String t) => t.trim().isNotEmpty)
            .toList(),
      });
      if (picked == null) return const <String>[];
      return picked.whereType<String>().toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _handoffToOs(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // Confirms via DNS probe before swapping — for transient load errors.
  Future<void> _probeAndMaybeShowOffline() async {
    if (_offlineShown) return;
    final bool live = await widget.wireWatch.canReach();
    if (live) return;
    _showOffline();
  }

  void _showOffline() {
    if (_offlineShown || !mounted) return;
    _offlineShown = true;
    final String resumeUrl = _lastMainFrameUrl ?? widget.streamUrl;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineScene(
          rebuilder: (_) => StreamScene(
            streamUrl: resumeUrl,
            stash: widget.stash,
            alertCenter: widget.alertCenter,
            wireWatch: widget.wireWatch,
          ),
        ),
      ),
    );
  }

  // Auto-scrolls focused inputs above the keyboard using a single
  // delayed pass. NEVER use behavior:'smooth' — see pitfalls §3.
  void _injectKeyboardScroll() {
    _controller.runJavaScript(r'''
(function(){
  if (window.__edKbFix) return; window.__edKbFix = true;
  function isField(el){ return el && (el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable); }
  function raise(){
    var el = document.activeElement; if (!isField(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var r = el.getBoundingClientRect();
      var bottom = vp.offsetTop + vp.height;
      if (r.bottom > bottom - 20 || r.top < vp.offsetTop) {
        el.scrollIntoView({behavior:'auto', block:'nearest'});
      }
    } else {
      el.scrollIntoView({behavior:'auto', block:'nearest'});
    }
  }
  document.addEventListener('focusin', function(e){
    if (isField(e.target)) setTimeout(raise, 350);
  });
  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function(){
      var h = window.visualViewport.height;
      if (h < prev) setTimeout(raise, 120);
      prev = h;
    });
  }
})();
''');
  }

  // Neutralises the site's safe-area insets so notched Android devices
  // don't render white gutters. Only overrides the site's CSS variables
  // and top-spacer classes — never touches html/body/#app padding (see
  // pitfalls guide / webview_safe_area_injection.mdc).
  void _neutraliseSiteSafeArea() {
    _controller.runJavaScript(r'''
(function(){
  if (window.__edSa) return; window.__edSa = true;
  var ID = '__ed_sa';
  var CSS = ':root{'
    + '--safe-area-inset-top:0px!important;--safe-area-inset-right:0px!important;'
    + '--safe-area-inset-bottom:0px!important;--safe-area-inset-left:0px!important;'
    + '--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;'
    + '--safe-top:0px!important;--safe-bottom:0px!important;'
    + '--safe-left:0px!important;--safe-right:0px!important;'
    + '}'
    + '.gameview-mobile-header,.app-header,.js-safe-top{padding-top:0!important;margin-top:0!important;}';
  function kbOpen(){ if (!window.visualViewport) return false; return window.visualViewport.height < window.innerHeight * 0.75; }
  function apply(){
    if (kbOpen()) return;
    var head = document.head || document.documentElement; if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m && !/viewport-fit\s*=\s*contain/i.test(m.getAttribute('content') || '')) {
      var c = (m.getAttribute('content') || '').replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      m.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var s = document.getElementById(ID);
    if (!s) { s = document.createElement('style'); s.id = ID; head.appendChild(s); }
    if (s.textContent !== CSS) s.textContent = CSS;
  }
  apply();
  ['pushState','replaceState'].forEach(function(fn){
    var o = history[fn];
    history[fn] = function(){
      var r = o.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 400);
      return r;
    };
  });
  window.addEventListener('popstate', function(){ setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  Future<void> _goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wireSub?.cancel();
    _wireDebounce?.cancel();
    widget.alertCenter.onOpenUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea handles cutouts on ALL edges except the bottom — the
    // bottom stays flush because the keyboard is handled by the JS
    // scroll fix, and any bottom inset would clip site content. In
    // landscape this yields a black gutter next to the punch-hole
    // camera on both long edges (per pitfalls §14).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (!didPop) await _goBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF140A08),
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: WebViewWidget(controller: _controller),
            ),
            // Fully opaque overlay while the WebView is loading OR
            // errored. Covers the native black error page in BOTH
            // orientations (see pitfalls §4). Using an opaque brand
            // colour instead of a translucent black so the underlying
            // native error text never bleeds through.
            if (_spinnerOn)
              const ColoredBox(
                color: Color(0xFF140A08),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF7A18)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
