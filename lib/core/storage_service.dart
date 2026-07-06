import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin persistence layer built on top of [SharedPreferences].
///
/// The whole game works fully offline: every piece of progress (unlocked
/// level, best scores, lifetime stats, daily tasks) lives only on the
/// device.
class StorageService {
  StorageService._(this._prefs);

  final SharedPreferences _prefs;

  static StorageService? _instance;

  static Future<StorageService> getInstance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = StorageService._(prefs);
    return _instance!;
  }

  static const _kUnlockedLevel = 'unlocked_level';
  static const _kTotalCrystals = 'total_crystals';
  static const _kTotalMoves = 'total_moves';
  static const _kTotalLevelsCompleted = 'total_levels_completed';
  static const _kPerfectStreak = 'perfect_streak';
  static const _kBestScorePrefix = 'best_score_level_';
  static const _kDailyTasksDate = 'daily_tasks_date';
  static const _kDailyTasksData = 'daily_tasks_data';
  static const _kDailyProgressPrefix = 'daily_progress_';

  int get unlockedLevel => _prefs.getInt(_kUnlockedLevel) ?? 1;
  Future<void> setUnlockedLevel(int value) => _prefs.setInt(_kUnlockedLevel, value);

  int get totalCrystals => _prefs.getInt(_kTotalCrystals) ?? 0;
  Future<void> addCrystals(int amount) =>
      _prefs.setInt(_kTotalCrystals, totalCrystals + amount);

  int get totalMoves => _prefs.getInt(_kTotalMoves) ?? 0;
  Future<void> addMoves(int amount) => _prefs.setInt(_kTotalMoves, totalMoves + amount);

  int get totalLevelsCompleted => _prefs.getInt(_kTotalLevelsCompleted) ?? 0;
  Future<void> incrementLevelsCompleted() =>
      _prefs.setInt(_kTotalLevelsCompleted, totalLevelsCompleted + 1);

  int get perfectStreak => _prefs.getInt(_kPerfectStreak) ?? 0;
  Future<void> setPerfectStreak(int value) => _prefs.setInt(_kPerfectStreak, value);

  int bestScoreForLevel(int level) => _prefs.getInt('$_kBestScorePrefix$level') ?? 0;

  Future<void> maybeUpdateBestScore(int level, int score) async {
    if (score > bestScoreForLevel(level)) {
      await _prefs.setInt('$_kBestScorePrefix$level', score);
    }
  }

  /// Returns the raw stored daily task JSON payload alongside the date it
  /// belongs to, or null when nothing has been generated yet.
  ({String date, String json})? readDailyTasksRaw() {
    final date = _prefs.getString(_kDailyTasksDate);
    final json = _prefs.getString(_kDailyTasksData);
    if (date == null || json == null) return null;
    return (date: date, json: json);
  }

  Future<void> writeDailyTasks(String date, List<Map<String, dynamic>> tasks) async {
    await _prefs.setString(_kDailyTasksDate, date);
    await _prefs.setString(_kDailyTasksData, jsonEncode(tasks));
  }

  int dailyProgressFor(String taskId) => _prefs.getInt('$_kDailyProgressPrefix$taskId') ?? 0;

  Future<void> setDailyProgressFor(String taskId, int value) =>
      _prefs.setInt('$_kDailyProgressPrefix$taskId', value);

  Future<void> clearDailyProgress(List<String> taskIds) async {
    for (final id in taskIds) {
      await _prefs.remove('$_kDailyProgressPrefix$id');
    }
  }
}
