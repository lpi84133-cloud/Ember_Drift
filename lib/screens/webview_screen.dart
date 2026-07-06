import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_colors.dart';
import '../core/asset_paths.dart';

/// Generic in-app browser used for both Privacy Policy and Support pages.
///
/// The rest of the game runs fully offline, so this is the only screen that
/// ever needs a network connection. If the page can't be reached, it falls
/// back to the bundled "no wifi" artwork with a Retry button instead of
/// leaving a blank/broken WebView on screen.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.obsidianDark)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _failed = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidianDark,
      appBar: AppBar(
        backgroundColor: AppColors.obsidianPanel,
        foregroundColor: AppColors.textPrimary,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          if (!_failed) WebViewWidget(controller: _controller),
          if (_loading && !_failed)
            const ColoredBox(
              color: AppColors.obsidianDark,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.emberOrange),
              ),
            ),
          if (_failed) _NoConnectionView(onRetry: _retry),
        ],
      ),
    );
  }
}

class _NoConnectionView extends StatelessWidget {
  const _NoConnectionView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final asset = isLandscape ? AssetPaths.horizontalNoWifi : AssetPaths.verticalNoWifi;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.obsidianDark),
        Image.asset(asset, fit: BoxFit.cover),
        Container(color: AppColors.obsidianDark.withValues(alpha: 0.35)),
        Align(
          alignment: const Alignment(0, 0.78),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't reach the page",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check your internet connection and try again.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emberOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
