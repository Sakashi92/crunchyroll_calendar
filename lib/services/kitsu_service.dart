import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'episode_provider.dart';
import '../models/anime_release.dart';
import '../models/anime_metadata.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';

class KitsuService implements EpisodeProvider {
  static const String _baseUrl = 'https://kitsu.io/api/edge';

  @override
  Future<void> loadCacheOnStartup() async {
    return;
  }

  @override
  Future<void> clearImageCache() async {
    return;
  }

  @override
  Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate) async {
    if (kDebugMode) print('[KitsuService] getReleasesForWeek not implemented');
    return [];
  }

  @override
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth}) async {
    return [];
  }

  @override
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title) async {
    return null;
  }

  @override
  Future<AnimeMetadata?> fetchSeriesMetadata(
    String? seriesUrl,
    String? title,
  ) async {
    final searchTerm = title;
    if (searchTerm == null || searchTerm.isEmpty) return null;

    final results = await searchSeries(searchTerm);
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  @override
  Future<void> scheduleWatchlistEntryUpdate(
    WatchlistService watchlistService,
    WatchlistEntry entry,
  ) async {
    return;
  }

  @override
  Future<List<AnimeMetadata>> searchSeries(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = '$_baseUrl/anime?filter[text]=$encodedQuery&page[limit]=5';

      if (kDebugMode) {
        print('🔎 [KITSU] Searching: $url');
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final data = body['data'] as List?;

        if (data == null) return [];

        return data.map((item) {
          final attrs = item['attributes'];
          final poster = attrs['posterImage'];
          String? imageUrl;
          if (poster != null) {
            imageUrl =
                poster['large'] ?? poster['original'] ?? poster['medium'];
          }

          final titles = attrs['titles'];
          String displayTitle = 'Unknown';
          if (titles != null) {
            displayTitle =
                titles['en'] ?? titles['en_jp'] ?? titles['ja_jp'] ?? 'Unknown';
          }

          // Parse Status
          String? rawStatus =
              attrs['status']; // "current", "finished", "tba", "unreleased", "upcoming"
          String? status;
          if (rawStatus != null) {
            if (rawStatus == 'finished')
              status = 'FINISHED';
            else if (rawStatus == 'current')
              status = 'RELEASING';
            else if (rawStatus == 'upcoming')
              status = 'NOT_YET_RELEASED';
            else
              status = rawStatus.toUpperCase();
          }

          int? epCount = attrs['episodeCount'];

          return AnimeMetadata(
            id: int.tryParse(item['id'].toString()),
            imageUrl: imageUrl,
            description: attrs['synopsis'],
            totalEpisodes: epCount,
            siteUrl: displayTitle,
            startDate: null,
            status: status,
          );
        }).toList();
      } else {
        if (kDebugMode) print('❌ [KITSU] Error ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [KITSU] Search error: $e');
    }
    return [];
  }

  @override
  Future<String?> getCrunchyrollUrl(int id) async {
    // Kitsu could search for streaming links but for now return null
    return null;
  }
}
