import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/watchlist.dart';

/// Helper class to handle importing watchlists from various JSON formats.
class WatchlistImporter {
  /// Parses a JSON string into a list of [WatchlistEntry] objects.
  /// Supports standard exports and some legacy/third-party formats.
  ///
  /// Uses [compute] to parse JSON in a background isolate.
  static Future<List<WatchlistEntry>> parseImportJson(String jsonString) async {
    return compute(_parseJsonIsolate, jsonString);
  }

  /// The static function to run in the isolate.
  static List<WatchlistEntry> _parseJsonIsolate(String jsonString) {
    dynamic decoded;
    try {
      decoded = json.decode(jsonString);
    } catch (e) {
      // Fallback: try to find the first array in the string
      final extracted = _extractJsonArray(jsonString);
      if (extracted != null) {
        try {
          decoded = json.decode(extracted);
        } catch (_) {
          throw const FormatException('Invalid JSON format');
        }
      } else {
        throw const FormatException('Invalid JSON format');
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
        return favs.map((f) {
          final m = f as Map<String, dynamic>;
          return WatchlistEntry(
            animeId: (m['seriesUrl'] ?? m['title'])?.toString() ?? '',
            title: m['title'] ?? '',
            imageUrl: m['imageUrl'],
            episodesWatched: 0,
            totalEpisodes: 0,
            status: WatchStatus.watching,
            notificationsEnabled: _parseBool(m['notificationsEnabled']),
            anilistId: m['anilistId'],
            addedAt: m['addedDate'] != null
                ? DateTime.tryParse(m['addedDate'])
                : null,
          );
        }).toList();
      } else {
        // fallback: try to find the first list value in the object
        final candidates = map.values.whereType<List>().toList();
        if (candidates.isNotEmpty) {
          jsonList = candidates.first;
        } else {
          throw const FormatException('Unsupported JSON structure');
        }
      }
    } else {
      throw const FormatException('Unsupported JSON structure');
    }

    return jsonList.map((e) {
      return WatchlistEntry(
        animeId: e['animeId'] ?? '',
        title: e['title'] ?? '',
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
        customTitle: e['customTitle'] as String?,
        episodeCountSource:
            EpisodeCountSource.values[(e['episodeCountSource'] as int?) ??
                EpisodeCountSource.auto.index],
      );
    }).toList();
  }

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return false;
  }

  static String? _extractJsonArray(String input) {
    final start = input.indexOf('[');
    if (start == -1) return null;

    int depth = 0;
    bool inString = false;
    bool escape = false;

    for (int i = start; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == 92) {
          escape = true;
        } else if (ch == 34) {
          inString = false;
        }
        continue;
      }

      if (ch == 34) {
        inString = true;
        continue;
      }

      if (ch == 91) {
        depth++;
      } else if (ch == 93) {
        depth--;
        if (depth == 0) {
          return input.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}
