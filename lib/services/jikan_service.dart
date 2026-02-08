import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'episode_provider.dart';
import '../models/anime_release.dart';
import '../models/anime_metadata.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../utils/title_utils.dart';

class JikanService implements EpisodeProvider {
  static const String _baseUrl = 'https://api.jikan.moe/v4';

  @override
  Future<void> loadCacheOnStartup() async {
    // Jikan doesn't need efficient local caching for this simple use case yet
    return;
  }

  @override
  Future<void> clearImageCache() async {
    return;
  }

  @override
  Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate) async {
    // Can be implemented later if Jikan schedule is needed
    if (kDebugMode) print('[JikanService] getReleasesForWeek not implemented');
    return [];
  }

  @override
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth}) async {
    return [];
  }

  @override
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title) async {
    // Can be implemented by searching and getting details
    return null;
  }

  @override
  Future<AnimeMetadata?> fetchSeriesMetadata(
    String? seriesUrl,
    String? title,
  ) async {
    // If we have no title, we can't search. seriesUrl might be a crunchyroll URL.
    final searchTerm =
        title ?? (seriesUrl != null ? _extractTitle(seriesUrl) : null);

    if (searchTerm == null || searchTerm.isEmpty) return null;

    final cleanSearchTerm = stripCrunchyrollSuffixes(searchTerm);

    final results = await searchSeries(cleanSearchTerm);
    if (results.isNotEmpty) {
      final best = results.first;
      if (best.id != null) {
        // Fetch streaming info to detect Crunchyroll
        bool hasCrunchyroll = false;
        try {
          final streamUrl = '$_baseUrl/anime/${best.id}/streaming';
          if (kDebugMode) print('🔎 [JIKAN] Checking streaming: $streamUrl');
          final response = await http.get(Uri.parse(streamUrl));
          if (response.statusCode == 200) {
            final body = json.decode(response.body);
            final data = body['data'] as List?;
            if (kDebugMode) {
              print('📺 [JIKAN] Streaming data for ${best.siteUrl}: $data');
            }
            if (data != null) {
              hasCrunchyroll = data.any(
                (s) =>
                    (s['name'] as String?)?.toLowerCase().contains(
                      'crunchyroll',
                    ) ==
                    true,
              );
            }
            if (kDebugMode) print('📺 [JIKAN] hasCrunchyroll: $hasCrunchyroll');
          } else {
            if (kDebugMode) {
              print('❌ [JIKAN] Streaming API error: ${response.statusCode}');
            }
          }
        } catch (_) {}

        return AnimeMetadata(
          id: best.id,
          imageUrl: best.imageUrl,
          description: best.description,
          totalEpisodes: best.totalEpisodes,
          siteUrl: best.siteUrl,
          bannerImage: best.bannerImage,
          startDate: best.startDate,
          nextEpisodeNumber: best.nextEpisodeNumber,
          nextEpisodeDate: best.nextEpisodeDate,
          hasCrunchyroll: hasCrunchyroll,
        );
      }
      return best;
    }
    return null;
  }

  String _extractTitle(String url) {
    try {
      final uri = Uri.parse(url);
      final segs = uri.pathSegments;
      if (segs.isNotEmpty) {
        return segs.last.replaceAll('-', ' ');
      }
    } catch (_) {}
    return url;
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
      final url = '$_baseUrl/anime?q=$encodedQuery&limit=10';

      if (kDebugMode) {
        print('🔎 [JIKAN] Searching: $url');
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final data = body['data'] as List?;

        if (data == null) return [];

        return data.map((item) {
          final images = item['images'];
          String? imageUrl;
          if (images != null) {
            imageUrl =
                images['jpg']?['large_image_url'] ??
                images['jpg']?['image_url'];
          }

          String displayTitle = item['title'] ?? 'Unknown';

          // Try to find English or Default title
          if (item['title_english'] != null) {
            displayTitle = item['title_english'];
          }

          // Parse Status
          String? rawStatus = item['status'];
          String? status;
          if (rawStatus != null) {
            if (rawStatus == 'Finished Airing') {
              status = 'FINISHED';
            } else if (rawStatus == 'Currently Airing') {
              status = 'RELEASING';
            } else if (rawStatus == 'Not yet aired') {
              status = 'NOT_YET_RELEASED';
            } else {
              status = rawStatus.toUpperCase();
            }
          }

          return AnimeMetadata(
            id: item['mal_id'],
            imageUrl: imageUrl,
            description: item['synopsis'],
            totalEpisodes: item['episodes'],
            siteUrl: displayTitle,
            startDate: null,
            status: status,
            // Jikan / MAL don't have a reliable 'next episode' field in search,
            // but we map it here in case it's added or available in full responses
            nextEpisodeNumber: item['next_episode']?.toString(),
          );
        }).toList();
      } else {
        if (kDebugMode) print('❌ [JIKAN] Error ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ [JIKAN] Search error: $e');
    }
    return [];
  }

  @override
  Future<String?> getCrunchyrollUrl(int id) async {
    try {
      final streamUrl = '$_baseUrl/anime/$id/streaming';
      if (kDebugMode) {
        print('🔎 [JIKAN] Checking streaming for ID $id: $streamUrl');
      }
      final response = await http.get(Uri.parse(streamUrl));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final data = body['data'] as List?;
        if (kDebugMode) {
          print('📺 [JIKAN] Streaming data for $id: $data');
        }
        if (data != null) {
          final cr = data.firstWhere(
            (s) =>
                (s['name'] as String?)?.toLowerCase().contains('crunchyroll') ==
                true,
            orElse: () => null,
          );
          if (cr != null) {
            return cr['url'] as String?;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ [JIKAN] Error checking availability: $e');
    }
    return null;
  }
}
