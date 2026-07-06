import 'dart:convert';
import 'dart:math';

import 'storage_service.dart';

enum DailyTaskKind {
  completeLevels,
  collectCrystals,
  flawlessLevel,
  makeMoves,
}

class DailyTask {
  DailyTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.target,
    required this.reward,
    this.claimed = false,
  });

  final String id;
  final DailyTaskKind kind;
  final String title;
  final int target;
  final int reward;
  bool claimed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.index,
        'title': title,
        'target': target,
        'reward': reward,
        'claimed': claimed,
      };

  factory DailyTask.fromJson(Map<String, dynamic> json) => DailyTask(
        id: json['id'] as String,
        kind: DailyTaskKind.values[json['kind'] as int],
        title: json['title'] as String,
        target: json['target'] as int,
        reward: json['reward'] as int,
        claimed: json['claimed'] as bool? ?? false,
      );
}

/// Generates and tracks a fresh trio of daily objectives, reset every
/// calendar day, entirely offline (backed by [StorageService]).
class DailyTasksManager {
  DailyTasksManager(this._storage);

  final StorageService _storage;

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<DailyTask> loadOrGenerate() {
    final today = _todayKey();
    final raw = _storage.readDailyTasksRaw();
    if (raw != null && raw.date == today) {
      final list = (jsonDecode(raw.json) as List)
          .map((e) => DailyTask.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    }

    if (raw != null) {
      final oldTasks = (jsonDecode(raw.json) as List)
          .map((e) => DailyTask.fromJson(e as Map<String, dynamic>))
          .toList();
      _storage.clearDailyProgress(oldTasks.map((t) => t.id).toList());
    }

    final tasks = _generate(today);
    _storage.writeDailyTasks(today, tasks.map((t) => t.toJson()).toList());
    return tasks;
  }

  List<DailyTask> _generate(String seedKey) {
    final rng = Random(seedKey.hashCode);
    final pool = <DailyTask>[
      DailyTask(
        id: 'levels_$seedKey',
        kind: DailyTaskKind.completeLevels,
        title: 'Clear ${3 + rng.nextInt(4)} levels',
        target: 3 + rng.nextInt(4),
        reward: 60,
      ),
      DailyTask(
        id: 'crystals_$seedKey',
        kind: DailyTaskKind.collectCrystals,
        title: 'Collect ${20 + rng.nextInt(30)} fire crystals',
        target: 20 + rng.nextInt(30),
        reward: 60,
      ),
      DailyTask(
        id: 'flawless_$seedKey',
        kind: DailyTaskKind.flawlessLevel,
        title: 'Finish a level with zero wasted moves',
        target: 1,
        reward: 50,
      ),
      DailyTask(
        id: 'moves_$seedKey',
        kind: DailyTaskKind.makeMoves,
        title: 'Make ${80 + rng.nextInt(120)} ember moves',
        target: 80 + rng.nextInt(120),
        reward: 40,
      ),
    ];
    pool.shuffle(rng);
    return pool.take(3).toList();
  }

  int progressFor(DailyTask task) => _storage.dailyProgressFor(task.id);

  Future<void> setProgress(DailyTask task, int value) =>
      _storage.setDailyProgressFor(task.id, value > task.target ? task.target : value);

  Future<void> incrementProgress(DailyTask task, int amount) async {
    final current = progressFor(task);
    await setProgress(task, current + amount);
  }

  bool isComplete(DailyTask task) => progressFor(task) >= task.target;
}
