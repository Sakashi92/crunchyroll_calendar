import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watchlist.dart';
import '../repositories/favorites_repository.dart';

class WatchlistService {
  static const _storageKey = 'watchlist_data';
  final Watchlist watchlist;

  WatchlistService(this.watchlist);

  Future<void> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      final parsed = jsonList.map((e) => WatchlistEntry(
        animeId: e['animeId'],
        title: e['title'],
        imageUrl: e['imageUrl'],
        episodesWatched: e['episodesWatched'],
        totalEpisodes: e['totalEpisodes'],
        status: WatchStatus.values[e['status']],
        notificationsEnabled: (e['notificationsEnabled'] as bool?) ?? false,
        note: e['note'],
        rating: (e['rating'] as num?)?.toDouble(),
        addedAt: e['addedAt'] != null ? DateTime.tryParse(e['addedAt']) : DateTime.now(),
      )).toList();
      watchlist.replaceAll(parsed);
    }
  }

  Future<void> saveWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = watchlist.entries.map((e) => {
      'animeId': e.animeId,
      'title': e.title,
      'imageUrl': e.imageUrl,
      'episodesWatched': e.episodesWatched,
      'totalEpisodes': e.totalEpisodes,
      'status': e.status.index,
      'notificationsEnabled': e.notificationsEnabled,
      'note': e.note,
      'rating': e.rating,
      'addedAt': e.addedAt?.toIso8601String(),
    }).toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }

  Future<String> exportToJson() async {
    final jsonList = watchlist.entries.map((e) => {
      'animeId': e.animeId,
      'title': e.title,
      'imageUrl': e.imageUrl,
      'episodesWatched': e.episodesWatched,
      'totalEpisodes': e.totalEpisodes,
      'status': e.status.index,
      'notificationsEnabled': e.notificationsEnabled,
      'note': e.note,
      'rating': e.rating,
      'addedAt': e.addedAt?.toIso8601String(),
    }).toList();
    return json.encode(jsonList);
  }

  Future<void> importFromJson(String jsonString) async {
    final List<dynamic> jsonList = json.decode(jsonString);
    final parsed = jsonList.map((e) => WatchlistEntry(
      animeId: e['animeId'],
      title: e['title'],
      imageUrl: e['imageUrl'],
      episodesWatched: e['episodesWatched'],
      totalEpisodes: e['totalEpisodes'],
      status: WatchStatus.values[e['status']],
      notificationsEnabled: (e['notificationsEnabled'] as bool?) ?? false,
      note: e['note'],
      rating: (e['rating'] as num?)?.toDouble(),
      addedAt: e['addedAt'] != null ? DateTime.tryParse(e['addedAt']) : DateTime.now(),
    )).toList();
    watchlist.replaceAll(parsed);
    await saveWatchlist();
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
    final List<dynamic> jsonList = json.decode(jsonString);

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
          note: e['note'],
          rating: (e['rating'] as num?)?.toDouble(),
          addedAt: e['addedAt'] != null ? DateTime.tryParse(e['addedAt']) : DateTime.now(),
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

    if (importedCount > 0) await saveWatchlist();
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
      final fileName = 'watchlist_backup_${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonString);
      if (kDebugMode) print('💾 Watchlist backup written to ${file.path}');
      return file.path;
    } catch (e) {
      if (kDebugMode) print('❌ Failed to backup watchlist: $e');
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
        if (!fav.notificationsEnabled) continue;

        // Versuche Match per seriesUrl, fallback auf Titel-Vergleich
        final matches = watchlist.entries.where((e) {
          if (fav.seriesUrl != null && fav.seriesUrl!.isNotEmpty) {
            if (e.animeId == fav.seriesUrl) return true;
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

    if (changes > 0) await saveWatchlist();
    return changes;
  }
}
