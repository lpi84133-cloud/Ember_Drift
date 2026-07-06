import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/asset_paths.dart';
import '../core/daily_tasks.dart';
import '../core/storage_service.dart';
import '../widgets/volcanic_background.dart';

class DailyTasksScreen extends StatefulWidget {
  const DailyTasksScreen({super.key});

  @override
  State<DailyTasksScreen> createState() => _DailyTasksScreenState();
}

class _DailyTasksScreenState extends State<DailyTasksScreen> {
  DailyTasksManager? _manager;
  List<DailyTask> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = await StorageService.getInstance();
    final manager = DailyTasksManager(storage);
    final tasks = manager.loadOrGenerate();
    if (!mounted) return;
    setState(() {
      _manager = manager;
      _tasks = tasks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VolcanicBackground(
        assetPath: AssetPaths.bg2,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    const Text(
                      'Daily Tasks',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.emberOrange))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) => _TaskCard(
                          task: _tasks[i],
                          manager: _manager!,
                          onChanged: () => setState(() {}),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.manager, required this.onChanged});

  final DailyTask task;
  final DailyTasksManager manager;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final progress = manager.progressFor(task);
    final complete = manager.isComplete(task);
    final ratio = (progress / task.target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.obsidianPanel.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.obsidianPanelLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.local_fire_department, color: AppColors.emberYellow, size: 16),
                  const SizedBox(width: 4),
                  Text('+${task.reward}',
                      style: const TextStyle(color: AppColors.emberYellow, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.obsidianDark,
              valueColor: AlwaysStoppedAnimation(complete ? Colors.greenAccent : AppColors.emberOrange),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            complete ? 'Complete!' : '$progress / ${task.target}',
            style: TextStyle(
              color: complete ? Colors.greenAccent : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
