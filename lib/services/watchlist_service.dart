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
import 'dart:async';
import 'app_settings_service.dart';

import '../models/anime_metadata.dart';
import '../utils/watchlist_importer.dart';

class WatchlistService {
  static const _storageKey = 'watchlist_data';
  final Watchlist watchlist;

  WatchlistService(this.watchlist);

  Timer? _saveDebouncer;

  /// Debounced version of [saveWatchlist].
  /// Useful during batch updates like imports or auto-linking.
  void saveWatchlistDebounced() {
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 500), () {
      saveWatchlist();
    });
  }

  // JSON parsing moved to WatchlistImporter and Isolates

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
          notify: false,
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

    final entriesToProcess = watchlist.entries
        .where((e) => e.predictionsEnabled)
        .toList();

    if (entriesToProcess.isEmpty) return 0;

    int count = 0;
    const int concurrencyLimit = 3;

    for (int i = 0; i < entriesToProcess.length; i += concurrencyLimit) {
      final end = (i + concurrencyLimit < entriesToProcess.length)
          ? i + concurrencyLimit
          : entriesToProcess.length;
      final chunk = entriesToProcess.sublist(i, end);

      final results = await Future.wait(
        chunk.map((e) async {
          try {
            final pred = await predictor.predictNextForSeries(
              e.animeId,
              e.title,
              anilistId: e.anilistId,
              notify: false,
            );
            return pred != null;
          } catch (err) {
            if (kDebugMode) {
              print('❌ Error predicting for "${e.title}": $err');
            }
            return false;
          }
        }),
      );
      count += results.where((r) => r).length;
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

  Future<void> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      if (kDebugMode) print('📚 Loading watchlist from disk...');
      try {
        // Use parsing in stored format (same as export/import)
        final parsed = await WatchlistImporter.parseImportJson(jsonString);
        watchlist.replaceAll(parsed);
        if (kDebugMode) print('✅ Loaded ${parsed.length} entries.');
      } catch (e) {
        if (kDebugMode) print('❌ Error loading watchlist: $e');
        // Fallback legacy loading if needed or safe fail?
        // For now, if json is corrupt, we start empty or keep internal state empty.
      }
    }
  }

  Future<void> saveWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    // Use compute for serializing large lists
    final jsonString = await compute(_serializeWatchlist, watchlist.entries);
    await prefs.setString(_storageKey, jsonString);
  }

  // Static function for isolate serialization
  static String _serializeWatchlist(List<WatchlistEntry> entries) {
    final jsonList = entries
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
            'customTitle': e.customTitle,
          },
        )
        .toList();
    return json.encode(jsonList);
  }

  Future<String> exportToJson() async {
    return compute(_serializeWatchlist, watchlist.entries);
  }

  Future<void> importFromJson(String jsonString) async {
    if (kDebugMode) print('📥 Importing watchlist from JSON...');

    // Use Helper Class and Isolate
    final parsed = await WatchlistImporter.parseImportJson(jsonString);

    // Replace all
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
    List<WatchlistEntry> entries;
    try {
      entries = await WatchlistImporter.parseImportJson(jsonString);
    } catch (e) {
      if (kDebugMode) print('❌ Import Parse Error: $e');
      rethrow;
    }

    int importedCount = 0;
    for (var entry in entries) {
      final exists = watchlist.entries.any((x) => x.animeId == entry.animeId);
      if (!exists) {
        watchlist.addEntry(entry);
        importedCount++;
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

      const int concurrencyLimit = 3;
      for (int i = 0; i < candidates.length; i += concurrencyLimit) {
        final end = (i + concurrencyLimit < candidates.length)
            ? i + concurrencyLimit
            : candidates.length;
        final chunk = candidates.sublist(i, end);

        await Future.wait(
          chunk.map((entry) async {
            if (entry.anilistId != null) return;

            try {
              final match = await anilist.findBestMatch(entry.title);

              if (match != null) {
                // final oldId = entry.animeId; // Unused

                entry.anilistId = match.id;
                entry.airingStatus =
                    match.status; // Save status from auto-link match

                // Sync Crunchyroll URL logic REMOVED to prevent ID mismatch with Calendar
                // We trust the internal ID (Calendar URL) as the source of truth.

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

                // Use debounced save instead of periodic save to avoid collisions
                saveWatchlistDebounced();
              }
            } catch (e) {
              if (kDebugMode) {
                print('❌ Auto-Link failed for "${entry.title}": $e');
              }
            }
          }),
        );

        // Artificial delay between chunks to be gentle with API
        await Future.delayed(const Duration(milliseconds: 1000));
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
      meta = await anilist.fetchSeriesMetadata(
        entry.animeId,
        entry.customTitle ?? entry.title,
      );
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [SYNC] AniList failed for "${entry.title}": $e');
      }
    }

    // 2. Try Kitsu fallback
    if (meta == null || meta.status == null) {
      try {
        meta = await kitsu.fetchSeriesMetadata(
          entry.animeId,
          entry.customTitle ?? entry.title,
        );
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ [SYNC] Kitsu failed for "${entry.title}": $e');
        }
      }
    }

    // 3. Try Jikan/MAL fallback
    if (meta == null || meta.status == null) {
      try {
        meta = await jikan.fetchSeriesMetadata(
          entry.animeId,
          entry.customTitle ?? entry.title,
        );
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ [SYNC] Jikan failed for "${entry.title}": $e');
        }
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
      // Update total episodes if missing or auto-sync is on
      if (entry.totalEpisodes == 0 || entry.autoSyncTotal) {
        // Logik-Änderung: Wir holen uns erst die Anzahl der releasten Folgen aus dem Kalender (maxEp).
        // ABER wir überschreiben den Total-Wert nur, wenn maxEp > meta.totalEpisodes ist,
        // oder wenn meta.totalEpisodes gar nicht verfügbar ist.
        // Das fixt das Problem, dass bei Simulcasts mit 12 Folgen anfangs "1" steht,
        // weil erst 1 Folge released ist.

        // Logik-Änderung: Wir holen uns die höchste Episodennummer direkt via Service.
        // Der Service durchsucht alle Monate und beherrscht fuzzy matching.
        final int maxEp =
            await cr.getMaxEpisodeForSeries(entry.animeId, entry.title) ?? 0;

        // Determine the best source of truth for "Total Episodes"
        int? metaTotal = meta.totalEpisodes;

        final bool preferCrCount =
            await AppSettingsService.getPreferCrunchyrollEpisodeCount();

        int currentTotal = entry.totalEpisodes;
        int targetTotal = currentTotal;

        if (preferCrCount) {
          // If enabled, we strictly prefer the Crunchyroll count (maxEp)
          // UNLESS maxEp is 0 (no data), then we might fallback or keep current
          if (maxEp > 0) {
            targetTotal = maxEp;
          } else if (metaTotal != null && metaTotal > 0 && currentTotal == 0) {
            // Fallback to meta only if we have NOTHING and CR is empty
            targetTotal = metaTotal;
          }
        } else {
          // New behavior: If "Prefer CR count" is OFF, we TRUST the Metadata count.
          // The user explicitly requested to "read out generally all max episodes per meta".
          if (metaTotal != null && metaTotal > 0) {
            targetTotal = metaTotal;
          } else if (maxEp > 0 && maxEp > targetTotal) {
            // Fallback to calendar if meta is empty but calendar has something
            targetTotal = maxEp;
          }
        }

        // Only update if changed (handling the case where we might reduce the count if preferCrCount is on)
        if (targetTotal > 0 && entry.totalEpisodes != targetTotal) {
          entry.totalEpisodes = targetTotal;
          changed = true;
          if (kDebugMode) {
            print(
              '✓ [SYNC] Updated "${entry.title}" episodes to $targetTotal (Mode: ${preferCrCount ? 'CR-Only' : 'Max-All'}, Meta: $metaTotal, Cal: $maxEp)',
            );
          }
        }
      }

      // AUTO-DEACTIVATION LOGIC 1: Metadata Providers
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

      // AUTO-DEACTIVATION LOGIC 2: Calendar Stale Check (User requested)
      // If last release was > 4 weeks ago or not found, deactivate.
      if (!isFinished) {
        try {
          final cachedReleases = await cr.getReleasesForSeriesCached(
            entry.animeId,
            entry.title,
          );
          // Filter out predictions to get actual airing history
          final actualReleases = cachedReleases
              .where((r) => !r.isPredicted)
              .toList();

          if (actualReleases.isEmpty) {
            if (kDebugMode) {
              print(
                '🛑 [SYNC] No past releases found for "${entry.title}" - Deactivating',
              );
            }
            entry.airingStatus = 'FINISHED';
            entry.notificationsEnabled = false;
            entry.predictionsEnabled = false;
            cr.removePredictedReleasesForSeries(entry.animeId, entry.title);
            changed = true;
          } else {
            // Find latest actual release
            actualReleases.sort(
              (a, b) => b.releaseTime.compareTo(a.releaseTime),
            );
            final latest = actualReleases.first.releaseTime;
            final diff = DateTime.now().difference(latest).inDays;

            if (diff > 28) {
              // 4 weeks
              if (kDebugMode) {
                print(
                  '🛑 [SYNC] Last release for "${entry.title}" was $diff days ago - Deactivating',
                );
              }
              entry.airingStatus = 'FINISHED';
              entry.notificationsEnabled = false;
              entry.predictionsEnabled = false;
              cr.removePredictedReleasesForSeries(entry.animeId, entry.title);
              changed = true;
            }
          }
        } catch (e) {
          if (kDebugMode) print('⚠️ [SYNC] Calendar stale check failed: $e');
        }
      }

      if (changed) {
        watchlist.updateEntry(entry);
        saveWatchlistDebounced();
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

    const int concurrencyLimit = 2;
    for (int i = 0; i < activeEntries.length; i += concurrencyLimit) {
      final end = (i + concurrencyLimit < activeEntries.length)
          ? i + concurrencyLimit
          : activeEntries.length;
      final chunk = activeEntries.sublist(i, end);

      await Future.wait(
        chunk.map((entry) => refreshMetadataWithFallback(entry)),
      );

      // Gentleness delay between chunks
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    await saveWatchlist();
  }

  /// Refreshes metadata ONLY for active series that match the provided release titles.
  /// This optimizes background sync by avoiding unnecessary API calls for series
  /// that haven't had a new release this week.
  Future<void> refreshMetadataForSpecificSeries(
    List<String> releaseTitles,
  ) async {
    // 1. Filter active entries that match the release titles
    final relevantEntries = watchlist.entries.where((e) {
      if (e.status != WatchStatus.watching) return false;

      // Check if title is in the release list (fuzzy match could be better but strict is safer for sync)
      // We use a simple case-insensitive containment check
      final title = e.title.toLowerCase();
      // Also check custom title if exists
      final customTitle = e.customTitle?.toLowerCase();

      return releaseTitles.any((r) {
        final rLower = r.toLowerCase();
        return rLower == title ||
            (customTitle != null && rLower == customTitle);
      });
    }).toList();

    if (relevantEntries.isEmpty) {
      if (kDebugMode) {
        print(
          '✓ [WATCHLIST-SYNC] No active series match the current releases - nothing to refresh.',
        );
      }
      return;
    }

    if (kDebugMode) {
      print(
        '🔄 [WATCHLIST-SYNC] Targeted refresh for ${relevantEntries.length} series (out of ${releaseTitles.length} releases)',
      );
    }

    // 2. Refresh only the relevant entries
    await refreshEntries(relevantEntries);
  }

  /// Refreshes metadata for the provided list of entries.
  Future<void> refreshEntries(List<WatchlistEntry> entries) async {
    if (kDebugMode) {
      print('🔄 [WATCHLIST-SYNC] Batch refresh for ${entries.length} entries');
    }
    const int concurrencyLimit = 1;
    for (int i = 0; i < entries.length; i += concurrencyLimit) {
      final end = (i + concurrencyLimit < entries.length)
          ? i + concurrencyLimit
          : entries.length;
      final chunk = entries.sublist(i, end); // sublist is safe here

      await Future.wait(
        chunk.map((entry) => refreshMetadataWithFallback(entry)),
      );

      // Gentleness delay between chunks (1.5s per request/chunk)
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    await saveWatchlist();
  }
}
