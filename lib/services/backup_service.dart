import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../repositories/custom_series_title_repository.dart';
import 'app_settings_service.dart';
import 'permission_service.dart';

class BackupService {
  static const int exportVersion = 1;

  // Categories for selective import
  static const String catSettings = 'settings';
  static const String catWatchlist = 'watchlist';
  static const String catCustomTitles = 'customTitles';
  static const String catSeenReleases = 'seenReleases';
  static const String catHistory = 'history';
  static const String catCalendarCache = 'calendarCache';
  static const String catHiddenAnime = 'hiddenAnime';

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
        'full_date_in_pill': prefs.getBool('full_date_in_pill'),
        'watchlist_only_simulcast': prefs.getBool('watchlist_only_simulcast'),
        'watchlist_only_catchup': prefs.getBool('watchlist_only_catchup'),
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

      // 7. Hidden Anime
      data[catHiddenAnime] = prefs.getStringList('hidden_anime');

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
    return parseBackupFromFile(file);
  }

  /// Parses backup data from a specific file.
  Future<Map<String, dynamic>> parseBackupFromFile(File file) async {
    final jsonString = await file.readAsString();
    final decoded = json.decode(jsonString);

    if (decoded is! Map) {
      throw Exception('Ungültiges Backup-Format (kein Objekt)');
    }

    final backup = Map<String, dynamic>.from(decoded);
    // Version check optional, but good practice
    // if (backup['version'] == null) ...

    return backup;
  }

  /// Returns a list of available backup files in the configured backup directory.
  /// Sorted by modification time (newest first).
  Future<List<File>> getAvailableBackups() async {
    final path = await AppSettingsService.getEffectiveBackupPath();
    // if (path == null) return []; // path is now non-nullable string, but check empty
    if (path.isEmpty) return [];

    final directory = Directory(path);
    if (!await directory.exists()) return [];

    List<File> files = [];
    try {
      final List<FileSystemEntity> entities = directory.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
          files.add(entity);
        }
      }

      // Sort by modification time (descending)
      files.sort((a, b) {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      });
    } catch (e) {
      if (kDebugMode) print('Error listing backups: $e');
    }
    return files;
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

      // 7. Import Hidden Anime
      if (categories.contains(catHiddenAnime) &&
          data.containsKey(catHiddenAnime)) {
        final hidden = (data[catHiddenAnime] as List?)?.cast<String>();
        if (hidden != null) {
          await prefs.setStringList('hidden_anime', hidden);
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error importing data: $e');
      rethrow;
    }
  }

  /// Triggers an automatic backup if conditions are met.
  Future<void> performAutoBackup() async {
    try {
      final frequency = await AppSettingsService.getBackupFrequencyDays();
      if (frequency <= 0) {
        if (kDebugMode) print('⚠️ Auto-backup skipped: Disabled (freq=0)');
        return;
      }

      if (Platform.isAndroid) {
        // In background, we can't request permission, only check.
        // If we really need to request, we might crash or hang.
        // Best to just check. But requestStoragePermission() implementation handles request.
        // Let's rely on the fact that if it returns false, we abort.
        // NOTE: Requesting in background might be ignored.
        final hasPermission = await PermissionService()
            .requestStoragePermission();
        if (!hasPermission) {
          if (kDebugMode)
            print('⚠️ Auto-backup skipped: No storage permission');
          return;
        }
      }

      final path = await AppSettingsService.getEffectiveBackupPath();
      // Path should generally not be null now, but good to keep sanity check if something fails completely
      if (path.isEmpty) {
        if (kDebugMode) print('⚠️ Auto-backup skipped: No path configured');
        return;
      }

      final lastBackup = await AppSettingsService.getLastBackupTimestamp();
      if (lastBackup != null) {
        final difference = DateTime.now().difference(lastBackup).inDays;
        if (difference < frequency) {
          if (kDebugMode) {
            print(
              'ℹ️ Auto-backup skipped: Not due yet (Last: $difference days ago, Freq: $frequency)',
            );
          }
          return;
        }
      }

      if (kDebugMode) print('🚀 Starting auto-backup to $path...');

      final includeCache = await AppSettingsService.getBackupIncludeCache();
      final jsonString = await generateBackupJson(includeCache: includeCache);

      final directory = Directory(path);
      if (!await directory.exists()) {
        try {
          await directory.create(recursive: true);
        } catch (e) {
          if (kDebugMode) print('❌ Error creating backup directory: $e');
          return;
        }
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];

      final typeSuffix = includeCache ? '_full' : '';
      final filename = 'backup_auto$typeSuffix\_$timestamp.json';

      String fullPath = directory.path;
      if (!fullPath.endsWith(Platform.pathSeparator)) {
        fullPath += Platform.pathSeparator;
      }
      fullPath += filename;

      final file = File(fullPath);

      await file.writeAsString(jsonString);
      await AppSettingsService.setLastBackupTimestamp(DateTime.now());

      if (kDebugMode) print('✅ Auto-backup created: ${file.path}');

      // Cleanup old backups
      await cleanupOldBackups(directory);
    } catch (e) {
      if (kDebugMode) print('❌ Error performing auto-backup: $e');
    }
  }

  /// Deletes old backups exceeding the max count.
  /// Made public so it can be called after manual backups too.
  Future<void> cleanupOldBackups(Directory directory) async {
    try {
      final maxCount = await AppSettingsService.getBackupMaxCount();
      if (maxCount <= 0) return; // Keep all if 0 (or handled as disabled)

      final List<FileSystemEntity> files = directory.listSync();
      final backupFiles = files.where((file) {
        if (file is! File) return false;
        final name = file.path.split(Platform.pathSeparator).last;
        return (name.startsWith('backup_auto_') ||
                name.startsWith('backup_manual')) &&
            file.path.endsWith('.json');
      }).toList();

      if (backupFiles.length <= maxCount) return;

      // Sort by modification time (oldest first)
      backupFiles.sort((a, b) {
        return a.statSync().modified.compareTo(b.statSync().modified);
      });

      final filesToDelete = backupFiles.length - maxCount;
      for (int i = 0; i < filesToDelete; i++) {
        try {
          await backupFiles[i].delete();
          if (kDebugMode) {
            print('🗑️ Deleted old backup: ${backupFiles[i].path}');
          }
        } catch (e) {
          if (kDebugMode) print('❌ Error deleting old backup: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error cleaning up old backups: $e');
    }
  }

  /// Migrates backups from the old app-specific directory to the new public folder.
  Future<void> migrateOldBackups() async {
    if (!Platform.isAndroid) return;

    try {
      final oldDir = await getExternalStorageDirectory();
      if (oldDir == null || !await oldDir.exists()) return;

      final newPath = '/storage/emulated/0/Download/CrunchyrollBackup';
      final newDir = Directory(newPath);

      if (!await newDir.exists()) {
        try {
          await newDir.create(recursive: true);
        } catch (e) {
          return;
        }
      }

      final files = oldDir.listSync();
      int movedCount = 0;
      for (final entity in files) {
        if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName.startsWith('backup_')) {
            final newFile = File('$newPath/$fileName');
            if (!await newFile.exists()) {
              await entity.copy(newFile.path);
              try {
                await entity.delete();
              } catch (_) {}
              movedCount++;
            }
          }
        }
      }

      if (movedCount > 0 && kDebugMode) {
        print('✅ Migrated $movedCount backups to $newPath');
      }
    } catch (e) {
      if (kDebugMode) print('Error migrating backups: $e');
    }
  }
}
