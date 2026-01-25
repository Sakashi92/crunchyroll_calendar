import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watchlist.dart';
import '../repositories/favorites_repository.dart';
import 'crunchyroll_service.dart';
import 'next_episode_predictor.dart';
import 'anilist_service.dart';
import 'prediction_notifier.dart';
import 'anilist_cache.dart';
import 'kitsu_service.dart';
import 'jikan_service.dart';
import '../utils/title_utils.dart';
import '../models/anime_metadata.dart';

class WatchlistService {
  static const _storageKey = 'watchlist_data';
  final Watchlist watchlist;

  WatchlistService(this.watchlist);

  // Extrahiere das erste vollständig-balancierte JSON-Array aus `input`.
  // Behandelt verschachtelte Arrays und ignoriert Zeichen innerhalb von Strings.
  String? _extractJsonArray(String input) {
    final start = input.indexOf('[');
    if (start == -1) {
      return null;
    }

    int depth = 0;
    bool inString = false;
    bool escape = false;

    for (int i = start; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == 92) {
          // backslash
          escape = true;
        } else if (ch == 34) {
          // '"'
          inString = false;
        }
        continue;
      }

      if (ch == 34) {
        // '"'
        inString = true;
        continue;
      }

      if (ch == 91) {
        // '['
        depth++;
      } else if (ch == 93) {
        // ']'
        depth--;
        if (depth == 0) {
          return input.substring(start, i + 1);
        }
      }
    }

    return null;
  }

  /// Für alle Watchlist-Einträge, die in den letzten 7 Tagen hinzugefügt wurden,
  /// versuche eine AniList-gestützte Vorhersage der nächsten Folge zu erstellen
  /// und in den Crunchyroll-Cache als predicted release einzufügen.
  /// Gibt die Anzahl erfolgreicher Vorhersagen zurück.
  Future<int> generateForecastForRecentEntries() async {
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 7));
    final crunch = CrunchyrollService();
    final anilist = AnilistService();
    final predictor = NextEpisodePredictor(crunch, anilist);

    // ensure cache loaded
    await crunch.loadCacheOnStartup();

    int count = 0;
    for (final e in watchlist.entries) {
      try {
        if (e.addedAt == null) {
          continue;
        }
        if (e.addedAt!.isBefore(since)) {
          continue;
        }
        if (!e.predictionsEnabled) continue;
        final pred = await predictor.predictNextForSeries(
          e.animeId,
          e.title,
          anilistId: e.anilistId,
        );
        if (pred != null) {
          count++;
        }
      } catch (_) {
        // ignore
      }
    }

    return count;
  }

  /// Erstelle Vorhersagen für alle Einträge in der Watchlist.
  /// Gibt die Anzahl erfolgreicher Vorhersagen zurück.
  Future<int> generateForecastForAllEntries() async {
    final crunch = CrunchyrollService();
    final anilist = AnilistService();
    final predictor = NextEpisodePredictor(crunch, anilist);

    // ensure cache loaded
    await crunch.loadCacheOnStartup();

    int count = 0;
    for (final e in watchlist.entries) {
      if (!e.predictionsEnabled) continue;
      try {
        final pred = await predictor.predictNextForSeries(
          e.animeId,
          e.title,
          anilistId: e.anilistId,
        );
        if (pred != null) {
          count++;
        }
      } catch (_) {
        // ignore individual failures
      }
    }

    // Trigger UI notification after ALL predictions are done
    try {
      predictionsUpdated.value = true;
      if (kDebugMode) {
        print(
          '🔔 generateForecastForAllEntries: done, $count predictions, triggering UI update',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error triggering predictionsUpdated: $e');
      }
    }

    return count;
  }

  bool _parseBool(dynamic v) {
    if (v == null) {
      return false;
    }
    if (v is bool) {
      return v;
    }
    if (v is num) {
      return v != 0;
    }
    if (v is String) {
      return v.toLowerCase() == 'true' || v == '1';
    }
    return false;
  }

  Future<void> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      final parsed = jsonList
          .map(
            (e) => WatchlistEntry(
              animeId: e['animeId'],
              title: e['title'],
              imageUrl: e['imageUrl'],
              episodesWatched: e['episodesWatched'],
              totalEpisodes: e['totalEpisodes'],
              status: WatchStatus.values[e['status']],
              notificationsEnabled:
                  (e['notificationsEnabled'] as bool?) ?? false,
              autoSyncTotal: (e['autoSyncTotal'] as bool?) ?? true,
              note: e['note'],
              rating: (e['rating'] as num?)?.toDouble(),
              anilistId: e['anilistId'] is int
                  ? e['anilistId'] as int
                  : (e['anilistId'] != null
                        ? int.tryParse(e['anilistId'].toString())
                        : null),
              addedAt: e['addedAt'] != null
                  ? DateTime.tryParse(e['addedAt'])
                  : DateTime.now(),
              isCrunchyroll: e['isCrunchyroll'] as bool?,
              predictionsEnabled: (e['predictionsEnabled'] as bool?) ?? true,
              airingStatus: e['airingStatus'] as String?,
            ),
          )
          .toList();
      watchlist.replaceAll(parsed);
    }
  }

  Future<void> saveWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = watchlist.entries
        .map(
          (e) => {
            'animeId': e.animeId,
            'title': e.title,
            'imageUrl': e.imageUrl,
            'episodesWatched': e.episodesWatched,
            'totalEpisodes': e.totalEpisodes,
            'status': e.status.index,
            'notificationsEnabled': e.notificationsEnabled,
            'autoSyncTotal': e.autoSyncTotal,
            'note': e.note,
            'rating': e.rating,
            'anilistId': e.anilistId,
            'addedAt': e.addedAt?.toIso8601String(),
            'isCrunchyroll': e.isCrunchyroll,
            'predictionsEnabled': e.predictionsEnabled,
            'airingStatus': e.airingStatus,
          },
        )
        .toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }

  Future<String> exportToJson() async {
    final jsonList = watchlist.entries
        .map(
          (e) => {
            'animeId': e.animeId,
            'title': e.title,
            'imageUrl': e.imageUrl,
            'episodesWatched': e.episodesWatched,
            'totalEpisodes': e.totalEpisodes,
            'status': e.status.index,
            'notificationsEnabled': e.notificationsEnabled,
            'autoSyncTotal': e.autoSyncTotal,
            'note': e.note,
            'rating': e.rating,
            'anilistId': e.anilistId,
            'addedAt': e.addedAt?.toIso8601String(),
            'isCrunchyroll': e.isCrunchyroll,
            'predictionsEnabled': e.predictionsEnabled,
            'airingStatus': e.airingStatus,
          },
        )
        .toList();
    return json.encode(jsonList);
  }

  Future<void> importFromJson(String jsonString) async {
    dynamic decoded;
    try {
      decoded = json.decode(jsonString);
    } catch (e) {
      final extracted = _extractJsonArray(jsonString);
      if (extracted != null) {
        try {
          decoded = json.decode(extracted);
          if (kDebugMode) {
            print('Watchlist import: used extracted JSON array fallback');
          }
        } catch (e2) {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    List<dynamic> jsonList;
    if (decoded is List) {
      jsonList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final map = decoded;
      if (map['watchlist'] is List) {
        jsonList = map['watchlist'] as List<dynamic>;
      } else if (map['favorites'] is List) {
        // Map favorites export format to watchlist entries
        final favs = map['favorites'] as List<dynamic>;
        jsonList = favs.map((f) {
          final m = f as Map<String, dynamic>;
          return {
            'animeId': (m['seriesUrl'] ?? m['title'])?.toString(),
            'title': m['title'],
            'imageUrl': m['imageUrl'],
            'episodesWatched': 0,
            'totalEpisodes': 0,
            'status': 0,
            'notificationsEnabled': _parseBool(m['notificationsEnabled']),
            'note': null,
            'rating': null,
            'anilistId':
                m['anilistId'], // Try to forward ID if present in newer exports
            'addedAt': m['addedDate'],
          };
        }).toList();
      } else {
        // fallback: try to find the first list value in the object
        final candidates = map.values.whereType<List>().toList();
        if (candidates.isNotEmpty) {
          jsonList = candidates.first as List<dynamic>;
        } else {
          throw const FormatException(
            'Unsupported JSON structure for watchlist import',
          );
        }
      }
    } else {
      throw const FormatException(
        'Unsupported JSON structure for watchlist import',
      );
    }

    final parsed = jsonList
        .map(
          (e) => WatchlistEntry(
            animeId: e['animeId'],
            title: e['title'],
            imageUrl: e['imageUrl'],
            episodesWatched: e['episodesWatched'],
            totalEpisodes: e['totalEpisodes'],
            status: WatchStatus.values[e['status']],
            notificationsEnabled: (e['notificationsEnabled'] as bool?) ?? false,
            autoSyncTotal: (e['autoSyncTotal'] as bool?) ?? true,
            note: e['note'],
            rating: (e['rating'] as num?)?.toDouble(),
            anilistId: e['anilistId'] is int
                ? e['anilistId'] as int
                : (e['anilistId'] != null
                      ? int.tryParse(e['anilistId'].toString())
                      : null),
            addedAt: e['addedAt'] != null
                ? DateTime.tryParse(e['addedAt'])
                : DateTime.now(),
            isCrunchyroll: e['isCrunchyroll'] as bool?,
            predictionsEnabled: (e['predictionsEnabled'] as bool?) ?? true,
            airingStatus: e['airingStatus'] as String?,
          ),
        )
        .toList();
    watchlist.replaceAll(parsed);
    await saveWatchlist();

    // Trigger auto-link for newly imported entries
    _triggerAutoLinkBackground();
  }

  Future<File> exportToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/watchlist_export.json');
    final jsonString = await exportToJson();
    return file.writeAsString(jsonString);
  }

  Future<void> importFromFile(File file) async {
    final jsonString = await file.readAsString();
    await importFromJson(jsonString);
  }

  /// Importiert eine Watchlist-JSON-Datei und merged Einträge.
  /// Überspringt Einträge mit derselben `animeId` und gibt die Anzahl
  /// der neu hinzugefügten Einträge zurück.
  Future<int> importFromJsonFilePath(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Datei nicht gefunden: $filePath');
    }

    final jsonString = await file.readAsString();
    dynamic decoded;
    try {
      decoded = json.decode(jsonString);
    } catch (e) {
      final extracted = _extractJsonArray(jsonString);
      if (extracted != null) {
        try {
          decoded = json.decode(extracted);
          if (kDebugMode) {
            print(
              'Watchlist importFromJsonFilePath: used extracted JSON array fallback',
            );
          }
        } catch (e2) {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    List<dynamic> jsonList;
    if (decoded is List) {
      jsonList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final map = decoded;
      if (map['watchlist'] is List) {
        jsonList = map['watchlist'] as List<dynamic>;
      } else if (map['favorites'] is List) {
        final favs = map['favorites'] as List<dynamic>;
        jsonList = favs.map((f) {
          final m = f as Map<String, dynamic>;
          return {
            'animeId': (m['seriesUrl'] ?? m['title'])?.toString(),
            'title': m['title'],
            'imageUrl': m['imageUrl'],
            'episodesWatched': 0,
            'totalEpisodes': 0,
            'status': 0,
            'notificationsEnabled': _parseBool(m['notificationsEnabled']),
            'note': null,
            'rating': null,
            'anilistId': m['anilistId'],
            'addedAt': m['addedDate'],
          };
        }).toList();
      } else {
        final candidates = map.values.whereType<List>().toList();
        if (candidates.isNotEmpty) {
          jsonList = candidates.first as List<dynamic>;
        } else {
          throw const FormatException(
            'Unsupported JSON structure for watchlist import',
          );
        }
      }
    } else {
      throw const FormatException(
        'Unsupported JSON structure for watchlist import',
      );
    }

    int importedCount = 0;
    for (var e in jsonList) {
      try {
        final entry = WatchlistEntry(
          animeId: e['animeId'],
          title: e['title'],
          imageUrl: e['imageUrl'],
          episodesWatched: e['episodesWatched'] ?? 0,
          totalEpisodes: e['totalEpisodes'] ?? 0,
          status: WatchStatus.values[(e['status'] as int?) ?? 0],
          notificationsEnabled: (e['notificationsEnabled'] as bool?) ?? false,
          autoSyncTotal: (e['autoSyncTotal'] as bool?) ?? true,
          note: e['note'],
          rating: (e['rating'] as num?)?.toDouble(),
          anilistId: e['anilistId'] is int
              ? e['anilistId'] as int
              : (e['anilistId'] != null
                    ? int.tryParse(e['anilistId'].toString())
                    : null),
          addedAt: e['addedAt'] != null
              ? DateTime.tryParse(e['addedAt'])
              : DateTime.now(),
          isCrunchyroll: e['isCrunchyroll'] as bool?,
          predictionsEnabled: (e['predictionsEnabled'] as bool?) ?? true,
          airingStatus: e['airingStatus'] as String?,
        );

        final exists = watchlist.entries.any((x) => x.animeId == entry.animeId);
        if (!exists) {
          watchlist.addEntry(entry);
          importedCount++;
        }
      } catch (_) {
        // ignore individual parse errors and continue
      }
    }

    if (importedCount > 0) {
      await saveWatchlist();
      // Trigger auto-link for newly imported entries
      _triggerAutoLinkBackground();
    }
    return importedCount;
  }

  /// Erstellt eine Backup-Datei der aktuellen Watchlist im Anwendungsdokumenten-Verzeichnis.
  /// Gibt den Pfad zur erstellten Datei zurück oder `null` bei Fehlern.
  Future<String?> backupWatchlistToFile() async {
    try {
      // Stelle sicher, dass wir die aktuellste Watchlist haben
      await loadWatchlist();
      final jsonString = await exportToJson();
      final directory = await getApplicationDocumentsDirectory();
      final ts = DateTime.now();
      final fileName =
          'watchlist_backup_${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonString);
      if (kDebugMode) {
        print('💾 Watchlist backup written to ${file.path}');
      }
      return file.path;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to backup watchlist: $e');
      }
      return null;
    }
  }

  /// Migriere Benachrichtigungseinstellungen aus der Favoritenliste in die Watchlist.
  ///
  /// Für jeden Favoriten mit `notificationsEnabled == true` wird versucht,
  /// ein passendes Watchlist-Entry zu finden (matching by `seriesUrl` or title).
  /// Falls kein Eintrag existiert, wird ein neuer Watchlist-Eintrag mit aktivierter
  /// Notification angelegt.
  /// Gibt die Anzahl der geänderten oder hinzugefügten Watchlist-Einträge zurück.
  Future<int> migrateNotificationSettingsFromFavorites() async {
    final favRepo = FavoritesRepository();
    final favorites = await favRepo.getAllFavorites();

    int changes = 0;

    for (final fav in favorites) {
      try {
        if (!fav.notificationsEnabled) {
          continue;
        }

        // Versuche Match per seriesUrl, fallback auf Titel-Vergleich
        final matches = watchlist.entries.where((e) {
          if (fav.seriesUrl != null && fav.seriesUrl!.isNotEmpty) {
            if (e.animeId == fav.seriesUrl) {
              return true;
            }
          }
          return e.title.toLowerCase() == fav.title.toLowerCase();
        }).toList();

        if (matches.isNotEmpty) {
          for (final m in matches) {
            if (!m.notificationsEnabled) {
              m.notificationsEnabled = true;
              changes++;
            }
          }
        } else {
          // Erstelle neuen Watchlist-Eintrag nur mit minimalen Daten
          final newEntry = WatchlistEntry(
            animeId: fav.seriesUrl ?? fav.title,
            title: fav.title,
            imageUrl: fav.imageUrl,
            episodesWatched: 0,
            totalEpisodes: 0,
            notificationsEnabled: true,
            addedAt: DateTime.now(),
          );
          watchlist.addEntry(newEntry);
          changes++;
        }
      } catch (e) {
        // ignore single failures
      }
    }

    if (changes > 0) {
      await saveWatchlist();
    }
    return changes;
  }

  /// Triggers a background process to attempt auto-linking for entries missing an AniList ID.
  /// Used after imports to resolve IDs without blocking the UI.
  void _triggerAutoLinkBackground() {
    // Run unawaited in microtask to not block caller
    Future.microtask(() async {
      if (kDebugMode) {
        print(
          '🔄 Auto-Link: Starting background check for unlinked entries...',
        );
      }

      final candidates = watchlist.entries
          .where((e) => e.anilistId == null)
          .toList();
      if (candidates.isEmpty) {
        if (kDebugMode) {
          print('✅ Auto-Link: No unlinked entries found.');
        }
        return;
      }

      int linkedCount = 0;
      final anilist = AnilistService();

      for (final entry in candidates) {
        // Double check if it was linked in the meantime
        if (entry.anilistId != null) {
          continue;
        }

        try {
          final match = await anilist.findBestMatch(entry.title);

          if (match != null) {
            final oldId = entry.animeId;
            entry.anilistId = match.id;
            entry.airingStatus =
                match.status; // Save status from auto-link match

            // Sync Crunchyroll URL if available from AniList
            if (match.hasCrunchyroll == true &&
                match.bannerImage != null &&
                match.bannerImage!.contains('crunchyroll.com')) {
              final newUrl = match.bannerImage!;
              if (newUrl != oldId) {
                watchlist.renameEntry(oldId, newUrl);
              }
            }

            // Save to cache so predictor can find it
            // Use current animeId (might be updated)
            final cacheKey = normalizeTitle(entry.animeId);
            try {
              final cache = AnilistCache();
              await cache.save(cacheKey, match);
            } catch (_) {}

            // Update the entry in the central list
            watchlist.updateEntry(entry);
            linkedCount++;

            // Save periodically every 5 updates to persist progress
            if (linkedCount % 5 == 0) {
              await saveWatchlist();
            }

            // Artificial delay to be gentle with API even with rate limiter
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Auto-Link failed for "${entry.title}": $e');
          }
        }
      }

      if (linkedCount > 0) {
        await saveWatchlist();
        if (kDebugMode) {
          print(
            '✅ Auto-Link: Completed. Successfully linked $linkedCount entries.',
          );
        }
      } else {
        if (kDebugMode) {
          print('ℹ️ Auto-Link: Completed. No confident matches found.');
        }
      }
    });
  }

  /// Refreshes metadata for a single entry using multiple providers as fallback.
  /// Checks for "FINISHED" status and deactivates notifications if not in CR calendar.
  Future<void> refreshMetadataWithFallback(WatchlistEntry entry) async {
    final anilist = AnilistService();
    final kitsu = KitsuService();
    final jikan = JikanService();
    final cr = CrunchyrollService();

    if (kDebugMode) {
      print('🔄 [WATCHLIST-SYNC] Refreshing metadata for "${entry.title}"...');
    }

    AnimeMetadata? meta;

    // 1. Try AniList (most comprehensive)
    try {
      meta = await anilist.fetchSeriesMetadata(entry.animeId, entry.title);
    } catch (e) {
      if (kDebugMode)
        print('⚠️ [SYNC] AniList failed for "${entry.title}": $e');
    }

    // 2. Try Kitsu fallback
    if (meta == null || meta.status == null) {
      try {
        meta = await kitsu.fetchSeriesMetadata(entry.animeId, entry.title);
      } catch (e) {
        if (kDebugMode)
          print('⚠️ [SYNC] Kitsu failed for "${entry.title}": $e');
      }
    }

    // 3. Try Jikan/MAL fallback
    if (meta == null || meta.status == null) {
      try {
        meta = await jikan.fetchSeriesMetadata(entry.animeId, entry.title);
      } catch (e) {
        if (kDebugMode)
          print('⚠️ [SYNC] Jikan failed for "${entry.title}": $e');
      }
    }

    if (meta != null) {
      bool changed = false;

      // Update airing status
      if (meta.status != null && meta.status != entry.airingStatus) {
        entry.airingStatus = meta.status;
        changed = true;
      }

      // Update total episodes if missing or auto-sync is on
      if (meta.totalEpisodes != null &&
          (entry.totalEpisodes == 0 || entry.autoSyncTotal)) {
        if (entry.totalEpisodes != meta.totalEpisodes) {
          entry.totalEpisodes = meta.totalEpisodes!;
          changed = true;
        }
      }

      // AUTO-DEACTIVATION LOGIC
      // If finished/cancelled AND not in Crunchyroll calendar
      final isFinished =
          meta.status?.toUpperCase() == 'FINISHED' ||
          meta.status?.toUpperCase() == 'CANCELLED';
      if (isFinished) {
        final inCalendar = cr.isTitleInCalendar(entry.title);
        if (!inCalendar) {
          if (entry.notificationsEnabled || entry.predictionsEnabled) {
            if (kDebugMode) {
              print(
                '🛑 [SYNC] Deactivating "${entry.title}" - Finished and NOT in CR calendar',
              );
            }
            entry.notificationsEnabled = false;
            entry.predictionsEnabled = false;
            // Clean up predictions
            cr.removePredictedReleasesForSeries(entry.animeId, entry.title);
            changed = true;
          }
        }
      }

      if (changed) {
        watchlist.updateEntry(entry);
      }
    }
  }

  /// Refreshes all active (Watching) entries in the watchlist.
  Future<void> refreshActiveSeriesMetadata() async {
    final activeEntries = watchlist.entries
        .where((e) => e.status == WatchStatus.watching)
        .toList();
    if (kDebugMode) {
      print(
        '🔄 [WATCHLIST-SYNC] Starting batch refresh for ${activeEntries.length} active entries',
      );
    }

    for (final entry in activeEntries) {
      await refreshMetadataWithFallback(entry);
      // Gentleness delay for APIs
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    await saveWatchlist();
  }
}
