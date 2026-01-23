import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'episode_provider.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../models/anime_metadata.dart';
import '../utils/title_utils.dart';
import 'anilist_cache.dart';

/// Skeleton implementation of an Anilist provider.
/// Currently returns safe defaults; incrementally implement GraphQL calls here.
class AnilistService implements EpisodeProvider {
  AnilistService();

  @override
  Future<void> loadCacheOnStartup() async {
    if (kDebugMode) print('[AnilistService] loadCacheOnStartup - not implemented yet');
    return;
  }

  @override
  Future<void> clearImageCache() async {
    if (kDebugMode) print('[AnilistService] clearImageCache - not implemented yet');
    return;
  }

  @override
  Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate) async {
    if (kDebugMode) print('[AnilistService] getReleasesForWeek - not implemented yet');
    return <AnimeRelease>[];
  }

  @override
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth}) async {
    if (kDebugMode) print('[AnilistService] forceRefresh - not implemented yet');
    return <AnimeRelease>[];
  }

  @override
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title) async {
    if (kDebugMode) print('[AnilistService] getMaxEpisodeForSeries for title="$title" - querying Anilist');
    try {
      final meta = await fetchSeriesMetadata(seriesUrl, title);
      return meta?.totalEpisodes;
    } catch (e) {
      if (kDebugMode) print('❌ Anilist getMaxEpisode error: $e');
      return null;
    }
  }

  @override
  Future<void> scheduleWatchlistEntryUpdate(WatchlistService watchlistService, WatchlistEntry entry) async {
    if (kDebugMode) print('[AnilistService] scheduleWatchlistEntryUpdate - not implemented yet');
    return;
  }

  @override
  Future<AnimeMetadata?> fetchSeriesMetadata(String? seriesUrl, String? title) async {
    if ((title == null || title.isEmpty) && (seriesUrl == null || seriesUrl.isEmpty)) return null;
    final cache = AnilistCache();
    final key = normalizeTitle(title ?? seriesUrl);
    final cached = await cache.get(key);
    if (cached != null) return cached;

    try {
      // Try to fetch several candidate results (Page) so we can compare multiple titles
      final q = '''
      query (
        \$search: String
      ) {
        Page(page: 1, perPage: 5) {
          media(search: \$search, type: ANIME) {
            id
            siteUrl
            title { romaji english native }
            description(asHtml: false)
            episodes
            coverImage { large medium }
            bannerImage
            startDate { year month day }
          }
        }
      }
      ''';

      // Generate a few search seeds to improve matching
      final seeds = <String>{};
      if (title != null && title.isNotEmpty) seeds.add(title);
      if (title != null) {
        // remove parenthetical parts
        seeds.add(title.replaceAll(RegExp(r"\(.*?\)"), '').trim());
        // take left side before ':'
        if (title.contains(':')) seeds.add(title.split(':').first.trim());
      }
      if (seriesUrl != null && seriesUrl.isNotEmpty) seeds.add(seriesUrl);

      AnimeMetadata? bestMeta;
      double bestScore = 0.0;

      for (final seed in seeds) {
        final variables = {'search': seed};
        final resp = await http.post(
          Uri.parse('https://graphql.anilist.co'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'query': q, 'variables': variables}),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode != 200) {
          if (kDebugMode) print('Anilist query failed: ${resp.statusCode} ${resp.body}');
          continue;
        }

        final Map<String, dynamic> data = json.decode(resp.body);
        final List<dynamic>? mediaList = data['data']?['Page']?['media'] as List<dynamic>?;
        if (mediaList == null || mediaList.isEmpty) continue;

        for (final media in mediaList) {
          try {
            final titles = <String>[];
            final titleObj = media['title'] as Map<String, dynamic>?;
            if (titleObj != null) {
              if (titleObj['romaji'] != null) titles.add(titleObj['romaji'] as String);
              if (titleObj['english'] != null) titles.add(titleObj['english'] as String);
              if (titleObj['native'] != null) titles.add(titleObj['native'] as String);
            }
            // compute best similarity against the provided title
            double localBest = 0.0;
            for (final t in titles) {
              final sim = similarity(t, title ?? seed);
              if (sim > localBest) localBest = sim;
            }

            // also compare against seed (which may be seriesUrl)
            final simSeed = similarity(media['siteUrl']?.toString() ?? '', seed);
            if (simSeed > localBest) localBest = simSeed;

            if (localBest > bestScore) {
              bestScore = localBest;
              final cover = media['coverImage']?['large'] ?? media['coverImage']?['medium'];
              final description = (media['description'] as String?)?.replaceAll(RegExp(r'<[^>]*>'), '')?.trim();
              int? episodes;
              try { episodes = media['episodes'] != null ? (media['episodes'] as int) : null; } catch (_) { episodes = null; }
              String? banner = media['bannerImage'];
              DateTime? start;
              try {
                final sd = media['startDate'];
                if (sd != null && sd['year'] != null) {
                  start = DateTime(sd['year'] ?? 0, sd['month'] ?? 1, sd['day'] ?? 1);
                }
              } catch (_) { start = null; }

              bestMeta = AnimeMetadata(
                imageUrl: cover,
                description: description,
                totalEpisodes: episodes,
                siteUrl: media['siteUrl'],
                bannerImage: banner,
                startDate: start,
              );
            }
          } catch (e) {
            // ignore individual media parse errors
          }
        }

        // If we already found a very good match, stop early
        if (bestScore >= 0.80) break;
      }

      // Accept matches above threshold
      if (bestMeta != null && bestScore >= 0.55) {
        // save in cache under normalized key
        await cache.save(key, bestMeta);
        return bestMeta;
      }

      return null;
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching Anilist metadata: $e');
      return null;
    }
  }
}
