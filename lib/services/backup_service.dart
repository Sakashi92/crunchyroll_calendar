import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../repositories/custom_series_title_repository.dart';

class BackupService {
  static const int exportVersion = 1;

  // Categories for selective import
  static const String catSettings = 'settings';
  static const String catWatchlist = 'watchlist';
  static const String catCustomTitles = 'customTitles';
  static const String catSeenReleases = 'seenReleases';
  static const String catHistory = 'history';
  static const String catCalendarCache = 'calendarCache';

  /// Generates the complete backup as a JSON string.
  /// [includeCache] - If true, includes the monthly calendar cache in the backup.
  Future<String> generateBackupJson({bool includeCache = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final Map<String, dynamic> data = {};

      // 1. Settings
      data[catSettings] = <String, dynamic>{
        'image_quality': prefs.getString('image_quality'),
        'update_interval_minutes': prefs.getInt('update_interval_minutes'),
        'auto_translate': prefs.getBool('auto_translate'),
        'accent_color': prefs.getInt('accent_color'),
        'notification_delay_seconds': prefs.getInt(
          'notification_delay_seconds',
        ),
        'show_refresh_message': prefs.getBool('show_refresh_message'),
        'auto_minimize_calendar': prefs.getBool('auto_minimize_calendar'),
        'auto_minimize_scroll_threshold': prefs.getDouble(
          'auto_minimize_scroll_threshold',
        ),
        'hide_duplicate_releases': prefs.getBool('hide_duplicate_releases'),
        'episode_provider': prefs.getString('episode_provider'),
        'enable_next_episode_prediction': prefs.getBool(
          'enable_next_episode_prediction',
        ),
        'watchlist_sort_mode': prefs.getInt('watchlist_sort_mode'),
        'prefer_crunchyroll_episode_count': prefs.getBool(
          'prefer_crunchyroll_episode_count',
        ),
      };

      // 2. Watchlist
      final watchlistJson = prefs.getString('watchlist_data');
      if (watchlistJson != null) {
        try {
          data[catWatchlist] = json.decode(watchlistJson);
        } catch (_) {}
      }

      // 3. Custom Titles
      final customTitlesJson = prefs.getString('custom_series_titles');
      if (customTitlesJson != null) {
        try {
          final decoded = json.decode(customTitlesJson);
          if (decoded is Map) {
            data[catCustomTitles] = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      // 4. Seen Releases
      data[catSeenReleases] = prefs.getStringList('seen_releases');

      // 5. Search History
      data[catHistory] = prefs.getStringList('search_history');

      // 6. Calendar Cache (Optional)
      if (includeCache) {
        final Map<String, dynamic> cacheData = {};
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.startsWith('cached_anime_releases_month_')) {
            final value = prefs.getString(key);
            if (value != null) {
              cacheData[key] = value;
            }
          }
        }
        if (cacheData.isNotEmpty) {
          data[catCalendarCache] = cacheData;
        }
      }

      Map<String, dynamic> backup = {
        'version': exportVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'data': data,
      };

      return json.encode(backup);
    } catch (e) {
      if (kDebugMode) print('❌ Error generating backup JSON: $e');
      rethrow;
    }
  }

  /// Exports all relevant app data to a JSON file and shares it (Legacy/Quick share).
  Future<void> exportData({bool includeCache = false}) async {
    try {
      final jsonString = await generateBackupJson(includeCache: includeCache);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/crunchyroll_calendar_backup.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Crunchyroll Kalender Backup');
    } catch (e) {
      if (kDebugMode) print('❌ Error exporting data: $e');
      rethrow;
    }
  }

  /// Picks a file and returns the parsed backup data.
  Future<Map<String, dynamic>?> pickAndParseBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.single.path == null) return null;

    final file = File(result.files.single.path!);
    final jsonString = await file.readAsString();
    final decoded = json.decode(jsonString);

    if (decoded is! Map) {
      throw Exception('Ungültiges Backup-Format (kein Objekt)');
    }

    final backup = Map<String, dynamic>.from(decoded);
    if (backup['version'] == null) {
      throw Exception('Ungültiges Backup-Format (Version fehlt)');
    }

    return backup;
  }

  /// Imports specific categories from backup data.
  Future<void> importData(
    Map<String, dynamic> backup,
    List<String> categories,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawData = backup['data'];
      if (rawData is! Map) return;

      final data = Map<String, dynamic>.from(rawData);

      if (categories.contains(catSettings) && data.containsKey(catSettings)) {
        final settingsRaw = data[catSettings];
        if (settingsRaw is Map) {
          final settings = Map<String, dynamic>.from(settingsRaw);
          settings.forEach((key, value) {
            if (value == null) {
              prefs.remove(key);
            } else if (value is String) {
              prefs.setString(key, value);
            } else if (value is int) {
              prefs.setInt(key, value);
            } else if (value is bool) {
              prefs.setBool(key, value);
            } else if (value is double) {
              prefs.setDouble(key, value);
            }
          });
        }
      }

      if (categories.contains(catWatchlist) && data.containsKey(catWatchlist)) {
        final watchlistData = data[catWatchlist];
        await prefs.setString('watchlist_data', json.encode(watchlistData));
      }

      if (categories.contains(catCustomTitles) &&
          data.containsKey(catCustomTitles)) {
        final customTitles = data[catCustomTitles];
        await prefs.setString(
          'custom_series_titles',
          json.encode(customTitles),
        );
        // Refresh the repository
        await CustomSeriesTitleRepository().reload();
      }

      if (categories.contains(catSeenReleases) &&
          data.containsKey(catSeenReleases)) {
        final seen = (data[catSeenReleases] as List?)?.cast<String>();
        if (seen != null) {
          await prefs.setStringList('seen_releases', seen);
        }
      }

      if (categories.contains(catHistory) && data.containsKey(catHistory)) {
        final history = (data[catHistory] as List?)?.cast<String>();
        if (history != null) {
          await prefs.setStringList('search_history', history);
        }
      }

      // 6. Import Calendar Cache (if present and selected)
      if (categories.contains(catCalendarCache) &&
          data.containsKey(catCalendarCache)) {
        final cacheRaw = data[catCalendarCache];
        if (cacheRaw is Map) {
          final cache = Map<String, dynamic>.from(cacheRaw);
          cache.forEach((key, value) {
            if (value is String) {
              prefs.setString(key, value);
            }
          });
          if (kDebugMode) {
            print('✅ Restored ${cache.length} calendar months from backup.');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error importing data: $e');
      rethrow;
    }
  }
}
