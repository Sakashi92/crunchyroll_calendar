import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'episode_provider.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../models/anime_metadata.dart';
import '../utils/title_utils.dart';
import 'anilist_cache.dart';
import 'external_search_service.dart';

// Helper to query AniList GraphQL API for nextAiringEpisode and metadata.
const _anilistEndpoint = 'https://graphql.anilist.co';
// AniList rate limits: ~90 requests/minute. We enforce a conservative
// minimum interval between requests and queue them to avoid bursts.
final _anilistRateLimiter = _AniListRateLimiter();

class _AniListRateLimiter {
  // conservative spacing ~700ms -> ~85 requests/min
  final Duration minInterval = const Duration(milliseconds: 700);
  final Queue<_QueuedCall> _queue = Queue<_QueuedCall>();
  DateTime _nextAvailable = DateTime.now();
  bool _running = false;

  Future<T> schedule<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _queue.add(_QueuedCall(fn, completer));
    if (!_running) {
      _processQueue();
    }
    return completer.future;
  }

  Future<void> _processQueue() async {
    _running = true;
    while (_queue.isNotEmpty) {
      final now = DateTime.now();
      if (now.isBefore(_nextAvailable)) {
        final wait = _nextAvailable.difference(now);
        await Future.delayed(wait);
      }

      final item = _queue.removeFirst();
      try {
        final result = await item.fn();
        // complete with result
        item.completer.complete(result);
      } catch (e, st) {
        item.completer.completeError(e, st);
      }

      _nextAvailable = DateTime.now().add(minInterval);
    }
    _running = false;
  }
}

class _QueuedCall {
  final Future<dynamic> Function() fn;
  final Completer completer;
  _QueuedCall(this.fn, this.completer);
}

/// Helper that performs POSTs to AniList respecting rate limits and retrying on 429.
Future<http.Response> _rateLimitedPost(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Duration timeout = const Duration(seconds: 10),
}) async {
  const int maxRetries = 5;
  int attempt = 0;
  while (true) {
    attempt++;
    try {
      final resp = await _anilistRateLimiter.schedule<http.Response>(() {
        return http.post(uri, headers: headers, body: body).timeout(timeout);
      });

      if (resp.statusCode == 429) {
        // Respect Retry-After header if present
        final ra = resp.headers['retry-after'];
        Duration wait = const Duration(seconds: 5);
        if (ra != null) {
          final secs = int.tryParse(ra);
          if (secs != null) {
            wait = Duration(seconds: secs + 1);
          }
        }
        if (kDebugMode) {
          print(
            'AniList 429 received, waiting ${wait.inSeconds}s before retry (attempt $attempt)',
          );
        }
        await Future.delayed(wait);
        if (attempt >= maxRetries) {
          return resp;
        }
        continue; // retry
      }

      return resp;
    } catch (e) {
      if (attempt >= maxRetries) {
        rethrow;
      }
      final backoff = Duration(milliseconds: 500 * attempt);
      if (kDebugMode) {
        print(
          'AniList request error, retrying after ${backoff.inMilliseconds}ms: $e',
        );
      }
      await Future.delayed(backoff);
    }
  }
}

/// Helper to perform a rate-limited POST but optionally wait an extra delay
/// between calls when used by the predictor to be extra conservative.
Future<http.Response> _postWithOptionalPredictDelay(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  Duration timeout = const Duration(seconds: 10),
  bool usePredictDelay = false,
}) async {
  if (usePredictDelay) {
    // wait 1.5s before each API call when predictor is running
    if (kDebugMode) {
      print(
        '🔎 [ANILIST] Predictor mode: waiting 1500ms before request to ${uri.host}',
      );
    }
    await Future.delayed(const Duration(milliseconds: 1500));
  }
  if (kDebugMode) {
    final preview = (body is String && body.length > 200)
        ? '${body.substring(0, 200)}...'
        : body?.toString() ?? '';
    print(
      '🔎 [ANILIST] About to POST to ${uri.toString()} (usePredictDelay=$usePredictDelay) body-preview: $preview',
    );
  }
  final resp = await _rateLimitedPost(
    uri,
    headers: headers,
    body: body,
    timeout: timeout,
  );
  if (kDebugMode) {
    print('🔎 [ANILIST] Response ${resp.statusCode} from ${uri.host}');
  }
  return resp;
}

/// Skeleton implementation of an Anilist provider.
/// Currently returns safe defaults; incrementally implement GraphQL calls here.
class AnilistService implements EpisodeProvider {
  AnilistService();

  String _sanitizeSearchTerm(String? raw) {
    if (raw == null) {
      return '';
    }
    var s = raw.trim();
    try {
      s = Uri.decodeFull(s);
    } catch (_) {}
    // Remove parenthetical and bracketed content (handle nested by iterating)
    var paren = RegExp(r"\([^()]*\)");
    while (paren.hasMatch(s)) {
      s = s.replaceAll(paren, '');
    }
    var bracket = RegExp(r"\[[^\[\]]*\]");
    while (bracket.hasMatch(s)) {
      s = s.replaceAll(bracket, '');
    }
    // Remove season/part indicators and years
    s = s.replaceAll(
      RegExp(
        r"\b(?:season|staffel|saison|part|teil|series)[:\s]*\d+\b",
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(RegExp(r"\b\d{4}\b"), '');
    // Replace URL-like separators and underscores
    s = s.replaceAll(RegExp(r"[-_/]+"), ' ');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r"\s+"), ' ').trim();

    // Collapse consecutive duplicate words (e.g. "The The Outcast")
    final tokens = s.split(RegExp(r"\s+")).where((t) => t.isNotEmpty).toList();
    if (tokens.isNotEmpty) {
      final collapsed = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        if (i == 0 || tokens[i].toLowerCase() != tokens[i - 1].toLowerCase()) {
          collapsed.add(tokens[i]);
        }
      }
      // Collapse simple repeated n-gram sequences (up to length 3)
      var t2 = collapsed;
      for (int n = 3; n >= 1; n--) {
        if (t2.length < n * 2) {
          continue;
        }
        final out = <String>[];
        int i = 0;
        while (i < t2.length) {
          if (i + 2 * n <= t2.length) {
            final a = t2.sublist(i, i + n).map((e) => e.toLowerCase()).toList();
            final b = t2
                .sublist(i + n, i + 2 * n)
                .map((e) => e.toLowerCase())
                .toList();
            bool listsEqualIgnoreCase(List<String> x, List<String> y) {
              if (x.length != y.length) {
                return false;
              }
              for (var ii = 0; ii < x.length; ii++) {
                if (x[ii] != y[ii]) {
                  if (x[ii].toLowerCase() != y[ii].toLowerCase()) {
                    return false;
                  }
                }
              }
              return true;
            }

            if (listsEqualIgnoreCase(a, b)) {
              out.addAll(t2.sublist(i, i + n));
              i += 2 * n;
              continue;
            }
          }
          out.add(t2[i]);
          i++;
        }
        t2 = out;
      }
      s = t2.join(' ');
    }

    // Limit length to avoid overly long queries
    if (s.length > 120) {
      s = s.substring(0, 120).trim();
    }
    return s;
  }

  /// Sucht Media nach Titel und liefert nextAiringEpisode falls vorhanden.
  Future<Map<String, dynamic>?> getNextAiringForTitle(
    String title, {
    bool usePredictDelay = false,
  }) async {
    final clean = _sanitizeSearchTerm(title);
    final query = r'''query ($search: String) {
      Media(search: $search, type: ANIME) {
        id
        title { userPreferred romaji english native }
        title { userPreferred romaji english native }
        nextAiringEpisode { airingAt episode timeUntilAiring }
      }
    }''';

    final variables = {'search': clean.isEmpty ? title : clean};

    try {
      if (kDebugMode) {
        print(
          '🔎 [ANILIST] getNextAiringForTitle search="$clean" (raw="$title") usePredictDelay=$usePredictDelay',
        );
      }
      final resp = await _postWithOptionalPredictDelay(
        Uri.parse(_anilistEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'query': query, 'variables': variables}),
        timeout: const Duration(seconds: 10),
        usePredictDelay: usePredictDelay,
      );
      if (kDebugMode) {
        print(
          '🔎 [ANILIST] getNextAiringForTitle status=${resp.statusCode} for "$title"',
        );
      }
      if (resp.statusCode != 200) {
        return null;
      }
      final Map<String, dynamic> data =
          json.decode(resp.body) as Map<String, dynamic>;
      final media = data['data']?['Media'] as Map<String, dynamic>?;
      return media;
    } catch (e) {
      if (kDebugMode) {
        print('Anilist getNextAiringForTitle error: $e');
      }
      return null;
    }
  }

  @override
  Future<void> loadCacheOnStartup() async {
    if (kDebugMode) {
      print('[AnilistService] loadCacheOnStartup - not implemented yet');
    }
    return;
  }

  @override
  Future<void> clearImageCache() async {
    if (kDebugMode) {
      print('[AnilistService] clearImageCache - not implemented yet');
    }
    return;
  }

  @override
  Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate) async {
    if (kDebugMode) {
      print('[AnilistService] getReleasesForWeek - not implemented yet');
    }
    return <AnimeRelease>[];
  }

  @override
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth}) async {
    if (kDebugMode) {
      print('[AnilistService] forceRefresh - not implemented yet');
    }
    return <AnimeRelease>[];
  }

  @override
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title) async {
    if (kDebugMode) {
      print(
        '[AnilistService] getMaxEpisodeForSeries for title="$title" - querying Anilist',
      );
    }
    try {
      final meta = await fetchSeriesMetadata(seriesUrl, title);
      return meta?.totalEpisodes;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Anilist getMaxEpisode error: $e');
      }
      return null;
    }
  }

  @override
  Future<void> scheduleWatchlistEntryUpdate(
    WatchlistService watchlistService,
    WatchlistEntry entry,
  ) async {
    if (kDebugMode) {
      print(
        '[AnilistService] scheduleWatchlistEntryUpdate - not implemented yet',
      );
    }
    return;
  }

  /// Clears AniList metadata cache and prefetches metadata for all series
  /// known to the provided `CrunchyrollService` to refresh local AniList data.
  Future<void> refreshMetadataForCrunchyroll(
    dynamic crunchy, {
    bool usePredictDelay = false,
    List<String>? seriesSeeds,
    List<WatchlistEntry>? entries,
  }) async {
    try {
      final cache = AnilistCache();
      // Remove cache clear to preserve manual linking - we want to refresh, not delete
      // await cache.clear();

      // Attempt to fetch metadata for all known series from the Crunchyroll cache
      try {
        List<String> series;
        Map<String, int?> urlToId = {};

        if (entries != null) {
          series = entries.map((e) => e.animeId).toList();
          for (final e in entries) {
            if (e.anilistId != null) {
              urlToId[e.animeId] = e.anilistId;
            }
          }
        } else if (seriesSeeds != null) {
          series = List<String>.from(seriesSeeds);
        } else {
          series = await crunchy.getAllKnownSeriesIds();
        }

        if (kDebugMode) {
          print('🔎 [ANILIST] Refreshing metadata for ${series.length} series');
        }
        int i = 0;
        for (final s in series) {
          i++;
          if (kDebugMode) {
            print(
              '🔎 [ANILIST] ($i/${series.length}) Prefetching metadata for $s',
            );
          }

          final existingId = urlToId[s];
          if (existingId != null) {
            // Pre-populate cache so fetchSeriesMetadata finds the ID even after a manual wipe
            final cacheKey = normalizeTitle(s);
            final existing = await cache.get(cacheKey);
            if (existing == null || existing.id != existingId) {
              await cache.save(cacheKey, AnimeMetadata(id: existingId));
            }
          }

          // fetchSeriesMetadata will derive a human-readable title from the URL if needed
          await fetchSeriesMetadata(s, null, usePredictDelay: usePredictDelay);
        }
      } catch (e) {
        if (kDebugMode) {
          print('🔎 [ANILIST] Error enumerating known series for refresh: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔎 [ANILIST] Error during refreshMetadataForCrunchyroll: $e');
      }
    }
  }

  String? extractAnimeName(String? seriesUrl) {
    if (seriesUrl == null || seriesUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(seriesUrl);
    if (uri == null) {
      return null;
    }

    // Extract the last segment of the path (e.g., "trigun-stampede")
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final lastSegment = segments.last;
      // Replace dashes with spaces and capitalize words
      return lastSegment
          .replaceAll('-', ' ')
          .split(' ')
          .map(
            (word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : '',
          )
          .join(' ');
    }
    return null;
  }

  @override
  Future<AnimeMetadata?> fetchSeriesMetadata(
    String? seriesUrl,
    String? title, {
    bool usePredictDelay = false,
  }) async {
    if ((title == null || title.isEmpty) &&
        (seriesUrl == null || seriesUrl.isEmpty)) {
      return null;
    }

    // Use seriesUrl as the primary stable cache key if available
    final cacheKey = normalizeTitle(seriesUrl ?? title);
    final cache = AnilistCache();
    final cached = await cache.get(cacheKey);

    // If we have a cached ID, use it to fetch PRECISE fresh data (1 request, no search)
    if (cached != null && cached.id != null) {
      if (kDebugMode) {
        print(
          '🔎 [ANILIST] Cache hit for "$cacheKey" (ID: ${cached.id}) - fetching FRESH data by ID',
        );
      }
      try {
        final qId = '''
            query (\$id: Int) {
              Media(id: \$id, type: ANIME) {
                id
                siteUrl
                title { romaji english native }
                description(asHtml: false)
                episodes
                nextAiringEpisode { airingAt episode }
                coverImage { large medium }
                bannerImage
                startDate { year month day }
                status
              }
            }
          ''';

        final resp = await _postWithOptionalPredictDelay(
          Uri.parse('https://graphql.anilist.co'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'query': qId,
            'variables': {'id': cached.id},
          }),
          timeout: const Duration(seconds: 10),
          usePredictDelay: usePredictDelay,
        );

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final media = data['data']?['Media'];
          if (media != null) {
            // Parse and return fresh metadata
            final cover =
                media['coverImage']?['large'] ?? media['coverImage']?['medium'];
            final desc = (media['description'] as String?)
                ?.replaceAll(RegExp(r'<[^>]*>'), '')
                .trim();
            int? episodes = media['episodes'] is int ? media['episodes'] : null;

            DateTime? start;
            try {
              if (media['startDate']?['year'] != null) {
                start = DateTime(
                  media['startDate']['year'],
                  media['startDate']['month'] ?? 1,
                  media['startDate']['day'] ?? 1,
                );
              }
            } catch (_) {}

            String? nEpNum;
            DateTime? nEpDate;
            if (media['nextAiringEpisode'] != null) {
              nEpNum = media['nextAiringEpisode']['episode']?.toString();
              if (media['nextAiringEpisode']['airingAt'] != null) {
                nEpDate = DateTime.fromMillisecondsSinceEpoch(
                  media['nextAiringEpisode']['airingAt'] * 1000,
                );
              }
            }

            final fresh = AnimeMetadata(
              id: media['id'],
              imageUrl: cover,
              description: desc,
              totalEpisodes: episodes,
              siteUrl: media['siteUrl'],
              bannerImage: media['bannerImage'],
              startDate: start,
              nextEpisodeNumber: nEpNum,
              nextEpisodeDate: nEpDate,
              status: media['status'] as String?,
            );

            // Update cache with fresh data
            await cache.save(cacheKey, fresh);
            return fresh;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            '⚠️ Failed to refresh by ID ${cached.id}, falling back to search: $e',
          );
        }
      }
    }

    // STRICT MODE: User requested ONLY ID-based predictions.
    // We disable the automatic text/heuristic search entirely.
    // Metadata/Predictions will only appear if the anime has been MANUALLY LINKED via the UI.
    if (kDebugMode) {
      print(
        '🔒 [ANILIST] Strict mode: No cached ID found for "$cacheKey" - skipping automatic search.',
      );
    }
    return null;
  }

  /// Manually search for anime on AniList. Returns a list of candidates.
  Future<List<AnimeMetadata>> searchAnime(String query) async {
    try {
      // Check if query is a numeric ID
      final int? searchId = int.tryParse(query.trim());

      String q;
      Map<String, dynamic> variables;

      if (searchId != null) {
        // ID Search
        q = '''
        query (\$id: Int) {
          Page(page: 1, perPage: 1) {
            media(id: \$id, type: ANIME) {
              id
              siteUrl
              title { romaji english native }
              description(asHtml: false)
              episodes
              nextAiringEpisode { airingAt episode }
              coverImage { large medium }
              bannerImage
              startDate { year month day }
              status
            }
          }
        }
        ''';
        variables = {'id': searchId};
      } else {
        // Text Search
        q = '''
        query (\$search: String) {
          Page(page: 1, perPage: 10) {
            media(search: \$search, type: ANIME) {
              id
              siteUrl
              title { romaji english native }
              description(asHtml: false)
              episodes
              nextAiringEpisode { airingAt episode }
              coverImage { large medium }
              bannerImage
              externalLinks { url site }
              startDate { year month day }
              status
            }
          }
        }
        ''';
        variables = {'search': query};
      }

      final resp = await _postWithOptionalPredictDelay(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'query': q, 'variables': variables}),
        timeout: const Duration(seconds: 10),
      );

      if (resp.statusCode != 200) {
        return [];
      }

      final data = json.decode(resp.body);
      final list = data['data']?['Page']?['media'] as List?;
      if (list == null) {
        return [];
      }

      return list.map((media) {
        final cover =
            media['coverImage']?['large'] ?? media['coverImage']?['medium'];
        final desc = (media['description'] as String?)
            ?.replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        int? episodes = media['episodes'] is int ? media['episodes'] : null;

        DateTime? start;
        try {
          if (media['startDate']?['year'] != null) {
            start = DateTime(
              media['startDate']['year'],
              media['startDate']['month'] ?? 1,
              media['startDate']['day'] ?? 1,
            );
          }
        } catch (_) {}

        String? nEpNum;
        DateTime? nEpDate;
        if (media['nextAiringEpisode'] != null) {
          nEpNum = media['nextAiringEpisode']['episode']?.toString();
          if (media['nextAiringEpisode']['airingAt'] != null) {
            nEpDate = DateTime.fromMillisecondsSinceEpoch(
              media['nextAiringEpisode']['airingAt'] * 1000,
            );
          }
        }

        // Extract best title for display
        String displayTitle = 'Unbekannter Titel';
        if (media['title'] != null) {
          displayTitle =
              media['title']['userPreferred'] ??
              media['title']['english'] ??
              media['title']['romaji'] ??
              media['title']['native'] ??
              'Titel nicht verfügbar';
        }

        final links = media['externalLinks'] as List?;
        String? crUrl;
        if (links != null) {
          final link = links.firstWhere(
            (l) => (l['site'] as String?)?.toLowerCase() == 'crunchyroll',
            orElse: () => null,
          );
          if (link != null) {
            crUrl = link['url'] as String?;
          }
        }

        return AnimeMetadata(
          id: media['id'],
          imageUrl: cover,
          description: desc,
          totalEpisodes: episodes,
          siteUrl: displayTitle,
          bannerImage:
              crUrl ??
              media['bannerImage'], // Prioritize CR link for carrier if found
          startDate: start,
          nextEpisodeNumber: nEpNum,
          nextEpisodeDate: nEpDate,
          hasCrunchyroll: crUrl != null,
          status: media['status'] as String?,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Manual search error: $e');
      }
      return [];
    }
  }

  /// Attempts to find a high-confidence match for auto-linking.
  /// Returns a metadata object only if:
  /// 1. An exact case-insensitive match for the title is found.
  /// 2. OR the search returns exactly one result.
  /// 3. OR the top result has a very high similarity score compared to the rest.
  Future<AnimeMetadata?> findBestMatch(String query) async {
    try {
      final results = await searchAnime(query);
      if (results.isEmpty) {
        return null;
      }

      final normalizedQuery = query.trim().toLowerCase();

      // User requested: If more than 2 candidates exist, we stay safe and require manual choice.
      if (results.length > 2) {
        if (kDebugMode) {
          print(
            '🔍 Auto-Link: Ambiguous search for "$query" (${results.length} hits). Manual link required.',
          );
        }
        return null;
      }

      // 1. Exact Match
      for (final r in results) {
        if (r.siteUrl != null && r.siteUrl!.toLowerCase() == normalizedQuery) {
          if (kDebugMode) {
            print('✅ Auto-Link: Exact match found for "$query"');
          }
          return r;
        }
      }

      // 2. Single Result (and it's not totally off)
      if (results.length == 1) {
        if (kDebugMode) {
          print('✅ Auto-Link: Single result found for "$query"');
        }
        return results.first;
      }

      // 3. Heuristic: Top result is "good enough" (contains query)
      // and query is long enough to be specific (> 5 chars)
      if (query.length > 5) {
        final first = results.first;
        final firstTitle = first.siteUrl?.toLowerCase() ?? '';
        if (firstTitle.contains(normalizedQuery) ||
            normalizedQuery.contains(firstTitle)) {
          if (kDebugMode) {
            print(
              '✅ Auto-Link: High confidence match for "$query" -> "${first.siteUrl}"',
            );
          }
          return first;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Auto-link error: $e');
      }
      return null;
    }
  }

  @override
  Future<List<AnimeMetadata>> searchSeries(String query) async {
    return await searchAnime(query);
  }

  @override
  Future<String?> getCrunchyrollUrl(int mediaId) async {
    try {
      // 1. Try AniList API first
      const query = r'''
      query ($id: Int) {
        Media(id: $id, type: ANIME) {
          title { userPreferred romaji english }
          externalLinks { url site }
        }
      }
      ''';
      final resp = await _postWithOptionalPredictDelay(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'query': query,
          'variables': {'id': mediaId},
        }),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final media = data['data']?['Media'];
        final links = media?['externalLinks'] as List?;
        if (links != null) {
          final cr = links.firstWhere(
            (l) => l['site']?.toString().toLowerCase() == 'crunchyroll',
            orElse: () => null,
          );
          if (cr != null) {
            return cr['url'] as String?;
          }
        }

        // 2. If not found, try ExternalSearchService with the title
        final title =
            media?['title']?['userPreferred'] ??
            media?['title']?['english'] ??
            media?['title']?['romaji'];
        if (title != null) {
          final externalSearch = ExternalSearchService();
          final url = await externalSearch.findCrunchyrollUrl(title);
          if (url != null) {
            return url;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
