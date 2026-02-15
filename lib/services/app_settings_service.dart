import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';

/// Service für die App-Einstellungen
class AppSettingsService {
  static const String _imageQualityKey = 'image_quality';
  static const String _updateIntervalKey = 'update_interval_minutes';
  static const String _autoTranslateKey = 'auto_translate';
  static const String _accentColorKey = 'accent_color';
  static const String _notificationDelayKey = 'notification_delay_seconds';
  static const String _showRefreshMessageKey = 'show_refresh_message';
  static const String _autoMinimizeCalendarKey = 'auto_minimize_calendar';
  static const String _autoMinimizeScrollThresholdKey =
      'auto_minimize_scroll_threshold';
  static const String _hideDuplicateReleasesKey = 'hide_duplicate_releases';
  static const String _hiddenAnimeKey = 'hidden_anime';
  static const String _searchHistoryKey = 'search_history';
  static const String _watchlistSortModeKey = 'watchlist_sort_mode';
  static const String _episodeProviderKey = 'episode_provider';
  static const String _predictionEnabledKey = 'enable_next_episode_prediction';
  static const String _preferCrunchyrollEpisodeCountKey =
      'prefer_crunchyroll_episode_count';
  static const String _fullDateInPillKey = 'full_date_in_pill';
  static const String _watchlistOnlySimulcastKey = 'watchlist_only_simulcast';
  static const String _watchlistOnlyCatchUpKey = 'watchlist_only_catchup';

  // Backup Settings Keys
  static const String _backupPathKey = 'backup_path';
  static const String _backupFrequencyKey = 'backup_frequency_days';
  static const String _backupMaxCountKey = 'backup_max_count';
  static const String _lastBackupTimestampKey = 'last_backup_timestamp';

  /// Verfügbare Bildqualitäten
  static const Map<String, String> imageQualities = {
    'original': 'Original (Höchste Qualität, ~2000x3000)',
    'large': 'Groß (~550x780)',
    'medium': 'Mittel (~390x554)',
    'small': 'Klein (~284x402)',
  };

  /// Verfügbare Update-Intervalle in Minuten
  static const Map<int, String> updateIntervals = {
    1: '1 Minute',
    2: '2 Minuten',
    5: '5 Minuten',
    10: '10 Minuten',
    15: '15 Minuten',
    20: '20 Minuten',
    30: '30 Minuten',
    60: '1 Stunde',
  };

  /// Verfügbare Verzögerungen für Benachrichtigungen in Sekunden
  static const Map<int, String> notificationDelays = {
    0: 'Sofort',
    10: '10 Sekunden',
    30: '30 Sekunden',
    60: '1 Minute',
    300: '5 Minuten',
    600: '10 Minuten',
  };

  /// Vordefinierte Accent-Farben
  static const List<Color> accentColors = [
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.amber,
  ];

  static Future<String> getImageQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_imageQualityKey) ?? 'original';
  }

  static Future<void> setImageQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageQualityKey, quality);
  }

  static Future<int> getUpdateIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_updateIntervalKey) ?? 20;
  }

  static Future<void> setUpdateIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_updateIntervalKey, minutes);
  }

  static Future<Duration> getUpdateInterval() async {
    final minutes = await getUpdateIntervalMinutes();
    return Duration(minutes: minutes);
  }

  static Future<bool> getAutoTranslate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoTranslateKey) ?? true;
  }

  static Future<void> setAutoTranslate(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoTranslateKey, enabled);
  }

  static Future<Color> getAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue =
        prefs.getInt(_accentColorKey) ?? Colors.orange.toARGB32();
    return Color(colorValue);
  }

  static Future<void> setAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.toARGB32());
  }

  static Future<int> getNotificationDelaySeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notificationDelayKey) ?? 0;
  }

  static Future<void> setNotificationDelaySeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationDelayKey, seconds);
  }

  static bool _showRefreshMessageCached = true;

  /// Globaler Status für In-App Benachrichtigungen (Snackbars)
  static bool get inAppNotificationsEnabled => _showRefreshMessageCached;

  /// Initialisiert die Einstellungen beim App-Start
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _showRefreshMessageCached = prefs.getBool(_showRefreshMessageKey) ?? true;

    // Migration: "Prefer Crunchyroll Episode Count" standardmäßig auf AUS setzen
    // (Einmaliger Trigger für bestehende Nutzer)
    const migrationKey = 'migration_force_meta_v1';
    if (!(prefs.getBool(migrationKey) ?? false)) {
      await prefs.setBool(_preferCrunchyrollEpisodeCountKey, false);
      await prefs.setBool(migrationKey, true);
    }
  }

  static Future<bool> getShowRefreshMessage() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_showRefreshMessageKey) ?? true;
    _showRefreshMessageCached = value;
    return value;
  }

  static Future<void> setShowRefreshMessage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRefreshMessageKey, enabled);
    _showRefreshMessageCached = enabled;
  }

  static Future<bool> getAutoMinimizeCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoMinimizeCalendarKey) ?? true;
  }

  static Future<void> setAutoMinimizeCalendar(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoMinimizeCalendarKey, enabled);
  }

  static Future<double> getAutoMinimizeScrollThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_autoMinimizeScrollThresholdKey) ?? 200.0;
  }

  static Future<void> setAutoMinimizeScrollThreshold(double pixels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_autoMinimizeScrollThresholdKey, pixels);
  }

  static Future<bool> getHideDuplicateReleases() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideDuplicateReleasesKey) ?? true;
  }

  static Future<void> setHideDuplicateReleases(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideDuplicateReleasesKey, enabled);
  }

  // Hidden Anime Logic
  static Future<List<String>> getHiddenAnime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_hiddenAnimeKey) ?? [];
  }

  static Future<void> setHiddenAnime(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenAnimeKey, list);
  }

  static Future<void> hideAnime(String normalizedTitle) async {
    final list = await getHiddenAnime();
    final lower = normalizedTitle.toLowerCase();
    if (!list.contains(lower)) {
      list.add(lower);
      await setHiddenAnime(list);
    }
  }

  static Future<void> unhideAnime(String normalizedTitle) async {
    final list = await getHiddenAnime();
    final lower = normalizedTitle.toLowerCase();
    // Remove case-insensitively
    list.removeWhere((item) => item.toLowerCase() == lower);
    await setHiddenAnime(list);
  }

  static Future<bool> isHidden(String normalizedTitle) async {
    final list = await getHiddenAnime();
    final lower = normalizedTitle.toLowerCase();
    return list.any((item) => item.toLowerCase() == lower);
  }

  static Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_searchHistoryKey)?.toList() ?? <String>[];
  }

  static Future<void> addToSearchHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = term.trim();
    if (normalized.isEmpty) return;
    final list = prefs.getStringList(_searchHistoryKey)?.toList() ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == normalized.toLowerCase());
    list.insert(0, normalized);
    if (list.length > 20) list.removeRange(20, list.length);
    await prefs.setStringList(_searchHistoryKey, list);
  }

  static Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }

  static Future<int> getWatchlistSortModeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_watchlistSortModeKey) ?? 0;
  }

  static Future<void> setWatchlistSortModeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_watchlistSortModeKey, index);
  }

  static Future<String> getEpisodeProviderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_episodeProviderKey) ?? 'anilist';
  }

  static Future<void> setEpisodeProviderName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_episodeProviderKey, name);
  }

  static Future<bool> getPredictionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_predictionEnabledKey) ?? true;
  }

  static Future<void> setPredictionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_predictionEnabledKey, enabled);
  }

  static Future<bool> getPreferCrunchyrollEpisodeCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preferCrunchyrollEpisodeCountKey) ?? false;
  }

  static Future<void> setPreferCrunchyrollEpisodeCount(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferCrunchyrollEpisodeCountKey, enabled);
  }

  static Future<bool> getFullDateInPill() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fullDateInPillKey) ?? false;
  }

  static Future<void> setFullDateInPill(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullDateInPillKey, enabled);
  }

  static Future<bool> getWatchlistOnlySimulcast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_watchlistOnlySimulcastKey) ?? false;
  }

  static Future<void> setWatchlistOnlySimulcast(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_watchlistOnlySimulcastKey, enabled);
  }

  static Future<bool> getWatchlistOnlyCatchUp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_watchlistOnlyCatchUpKey) ?? false;
  }

  static Future<void> setWatchlistOnlyCatchUp(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_watchlistOnlyCatchUpKey, enabled);
  }

  // Backup Settings Methods

  /// Returns the configured backup path or null if not set.
  static Future<String?> getBackupPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_backupPathKey);
  }

  /// Returns the effective backup path.
  /// If a user-defined path exists, returns it.
  /// Otherwise returns the platform-specific default data directory.
  static Future<String> getEffectiveBackupPath() async {
    final userPath = await getBackupPath();
    if (userPath != null) return userPath;

    if (Platform.isAndroid) {
      // Use public Download directory for persistence
      return '/storage/emulated/0/Download/CrunchyrollBackup';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
  }

  static Future<void> setBackupPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backupPathKey, path);
  }

  /// Returns the backup frequency in days. 0 means disabled.
  static Future<int> getBackupFrequencyDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_backupFrequencyKey) ?? 0; // Default: 0 (Disabled)
  }

  static Future<void> setBackupFrequencyDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backupFrequencyKey, days);
  }

  /// Returns the maximum number of backups to keep.
  static Future<int> getBackupMaxCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_backupMaxCountKey) ?? 5; // Default: Keep 5
  }

  static Future<void> setBackupMaxCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backupMaxCountKey, count);
  }

  static const String _backupIncludeCacheKey = 'backup_include_cache';

  /// Returns whether auto-backups should include the cache (Full Backup).
  static Future<bool> getBackupIncludeCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backupIncludeCacheKey) ??
        false; // Default: Standard (False)
  }

  static Future<void> setBackupIncludeCache(bool include) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backupIncludeCacheKey, include);
  }

  /// Returns the timestamp of the last successful backup.
  static Future<DateTime?> getLastBackupTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_lastBackupTimestampKey);
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }

  static Future<void> setLastBackupTimestamp(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastBackupTimestampKey, timestamp.toIso8601String());
  }
}
