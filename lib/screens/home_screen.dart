import 'package:flutter/material.dart';

import '../bridge/insight.dart';
import '../core/app_colors.dart';
import '../core/app_urls.dart';
import '../core/asset_paths.dart';
import '../core/storage_service.dart';
import '../widgets/stat_chip.dart';
import '../widgets/volcanic_background.dart';
import 'daily_tasks_screen.dart';
import 'game_screen.dart';
import 'webview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StorageService? _storage;

  @override
  void initState() {
    super.initState();
    Insight.screen('menu');
    _load();
  }

  Future<void> _load() async {
    final storage = await StorageService.getInstance();
    if (!mounted) return;
    setState(() => _storage = storage);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storage = _storage;
    return Scaffold(
      body: VolcanicBackground(
        assetPath: AssetPaths.bg1,
        child: SafeArea(
          child: storage == null
              ? const Center(child: CircularProgressIndicator(color: AppColors.emberOrange))
              : Column(
                  children: [
                    const Spacer(flex: 2),
                    Image.asset(AssetPaths.gameNameLogo, width: 220),
                    const Spacer(flex: 1),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        StatChip(
                          icon: Icons.flag_rounded,
                          label: 'Level ${storage.unlockedLevel}',
                        ),
                        StatChip(
                          icon: Icons.diamond,
                          label: '${storage.totalCrystals}',
                          iconColor: AppColors.emberYellow,
                        ),
                        StatChip(
                          icon: Icons.emoji_events,
                          label: '${storage.totalLevelsCompleted} cleared',
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                    _PrimaryButton(
                      label: 'Play  \u2022  Level ${storage.unlockedLevel}',
                      onTap: () => Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (_) => GameScreen(level: storage.unlockedLevel),
                            ),
                          )
                          .then((_) => _refresh()),
                    ),
                    const SizedBox(height: 14),
                    _SecondaryButton(
                      label: 'Daily Tasks',
                      icon: Icons.checklist_rounded,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const DailyTasksScreen()))
                          .then((_) => _refresh()),
                    ),
                    const Spacer(flex: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LinkButton(
                          label: 'Privacy Policy',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WebViewScreen(
                                title: 'Privacy Policy',
                                url: AppUrls.privacyPolicy,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          height: 12,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                        ),
                        _LinkButton(
                          label: 'Support',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WebViewScreen(
                                title: 'Support',
                                url: AppUrls.support,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: AppColors.emberGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.emberOrange.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.obsidianPanel.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.obsidianPanelLight),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.emberOrange, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
