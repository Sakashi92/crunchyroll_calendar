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
    _queue.add(_QueuedCall(fn, completer as Completer<Object?>));
    if (!_running) _processQueue();
    return completer.future as Future<T>;
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
        (item.completer as Completer<Object?>).complete(result);
      } catch (e, st) {
        (item.completer as Completer<Object?>).completeError(e, st);
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
Future<http.Response> _rateLimitedPost(Uri uri, {Map<String, String>? headers, Object? body, Duration timeout = const Duration(seconds: 10)}) async {
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
          if (secs != null) wait = Duration(seconds: secs + 1);
        }
        if (kDebugMode) print('AniList 429 received, waiting ${wait.inSeconds}s before retry (attempt $attempt)');
        await Future.delayed(wait);
        if (attempt >= maxRetries) return resp;
        continue; // retry
      }

      return resp;
    } catch (e) {
      if (attempt >= maxRetries) rethrow;
      final backoff = Duration(milliseconds: 500 * attempt);
      if (kDebugMode) print('AniList request error, retrying after ${backoff.inMilliseconds}ms: $e');
      await Future.delayed(backoff);
    }
  }
}

/// Helper to perform a rate-limited POST but optionally wait an extra delay
/// between calls when used by the predictor to be extra conservative.
Future<http.Response> _postWithOptionalPredictDelay(Uri uri, {Map<String, String>? headers, Object? body, Duration timeout = const Duration(seconds: 10), bool usePredictDelay = false}) async {
  if (usePredictDelay) {
    // wait 1.5s before each API call when predictor is running
    print('🔎 [ANILIST] Predictor mode: waiting 1500ms before request to ${uri.host}');
    await Future.delayed(const Duration(milliseconds: 1500));
  }
  final preview = (body is String && body.length > 200) ? body.substring(0, 200) + '...' : body?.toString() ?? '';
  print('🔎 [ANILIST] About to POST to ${uri.toString()} (usePredictDelay=$usePredictDelay) body-preview: ${preview}');
  final resp = await _rateLimitedPost(uri, headers: headers, body: body, timeout: timeout);
  print('🔎 [ANILIST] Response ${resp.statusCode} from ${uri.host}');
  return resp;
}

/// Skeleton implementation of an Anilist provider.
/// Currently returns safe defaults; incrementally implement GraphQL calls here.
class AnilistService implements EpisodeProvider {
  AnilistService();

  String _sanitizeSearchTerm(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    try { s = Uri.decodeFull(s); } catch (_) {}
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
    s = s.replaceAll(RegExp(r"\b(?:season|staffel|saison|part|teil|series)[:\s]*\d+\b", caseSensitive: false), '');
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
        if (i == 0 || tokens[i].toLowerCase() != tokens[i - 1].toLowerCase()) collapsed.add(tokens[i]);
      }
      // Collapse simple repeated n-gram sequences (up to length 3)
      var t2 = collapsed;
      for (int n = 3; n >= 1; n--) {
        if (t2.length < n * 2) continue;
        final out = <String>[];
        int i = 0;
        while (i < t2.length) {
          if (i + 2 * n <= t2.length) {
            final a = t2.sublist(i, i + n).map((e) => e.toLowerCase()).toList();
            final b = t2.sublist(i + n, i + 2 * n).map((e) => e.toLowerCase()).toList();
            bool _listsEqualIgnoreCase(List<String> x, List<String> y) {
              if (x.length != y.length) return false;
              for (var ii = 0; ii < x.length; ii++) {
                if (x[ii] != y[ii]) {
                  if (x[ii].toLowerCase() != y[ii].toLowerCase()) return false;
                }
              }
              return true;
            }

            if (_listsEqualIgnoreCase(a, b)) {
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
    if (s.length > 120) s = s.substring(0, 120).trim();
    return s;
  }

  /// Sucht Media nach Titel und liefert nextAiringEpisode falls vorhanden.
  Future<Map<String, dynamic>?> getNextAiringForTitle(String title, {bool usePredictDelay = false}) async {
    final clean = _sanitizeSearchTerm(title);
    final query = r'''query ($search: String) {
      Media(search: $search, type: ANIME) {
        id
        title { userPreferred romaji english native }
        nextAiringEpisode { airingAt episode timeUntilAiring }
      }
    }''';

    final variables = {'search': clean.isEmpty ? title : clean};

    try {
      print('🔎 [ANILIST] getNextAiringForTitle search="$clean" (raw="$title") usePredictDelay=$usePredictDelay');
      final resp = await _postWithOptionalPredictDelay(
        Uri.parse(_anilistEndpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'query': query, 'variables': variables}),
        timeout: const Duration(seconds: 10),
        usePredictDelay: usePredictDelay,
      );
      print('🔎 [ANILIST] getNextAiringForTitle status=${resp.statusCode} for "$title"');
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> data = json.decode(resp.body) as Map<String, dynamic>;
      final media = data['data']?['Media'] as Map<String, dynamic>?;
      return media;
    } catch (e) {
      print('Anilist getNextAiringForTitle error: $e');
      return null;
    }
  }

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

  String? extractAnimeName(String? seriesUrl) {
    if (seriesUrl == null || seriesUrl.isEmpty) return null;
    final uri = Uri.tryParse(seriesUrl);
    if (uri == null) return null;

    // Extract the last segment of the path (e.g., "trigun-stampede")
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final lastSegment = segments.last;
      // Replace dashes with spaces and capitalize words
      return lastSegment.replaceAll('-', ' ').split(' ').map((word) =>
          word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '').join(' ');
    }
    return null;
  }

  @override
  Future<AnimeMetadata?> fetchSeriesMetadata(String? seriesUrl, String? title, {bool usePredictDelay = false}) async {
    if ((title == null || title.isEmpty) && (seriesUrl == null || seriesUrl.isEmpty)) return null;

    // Extract anime name from URL if title is not provided
    if ((title == null || title.isEmpty) && seriesUrl != null) {
      title = extractAnimeName(seriesUrl);
      if (kDebugMode) {
        print('🔎 [ANILIST] Extracted title from URL: "$title"');
      }
    }

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
        Page(page: 1, perPage: 10) {
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
      String sanitizeSeed(String s) {
        var out = s.trim();
        // If looks like URL, try to extract a human-readable name
        if (out.contains('://') || out.contains('/') || out.contains('crunchyroll.com')) {
          final ex = extractAnimeName(out);
          if (ex != null && ex.isNotEmpty) out = ex;
        }
        try {
          out = Uri.decodeFull(out);
        } catch (_) {}
        // remove parenthetical parts
        out = out.replaceAll(RegExp(r"\(.*?\)"), '');
        // remove season/part indicators like "Season 2", "Staffel 1", "Part 3"
        out = out.replaceAll(RegExp(r"\b(?:season|staffel|saison|part|teil|series)[:\s]*\d+\b", caseSensitive: false), '');
        // strip standalone 4-digit years
        out = out.replaceAll(RegExp(r"\b\d{4}\b"), '');
        // replace dashes/underscores with spaces
        out = out.replaceAll(RegExp(r"[-_]+"), ' ');
        // collapse whitespace
        out = out.replaceAll(RegExp(r"\s+"), ' ').trim();
        return out;
      }

      final seeds = <String>{};
      if (title != null && title.isNotEmpty) {
        final raw = title.trim();
        final clean = sanitizeSeed(title);
        seeds.add(clean);
        // also include the raw title (sometimes AniList matches raw casing/extra words)
        seeds.add(raw);
        // also try without parenthetical parts
        seeds.add(sanitizeSeed(raw.replaceAll(RegExp(r"\(.*?\)"), '')));
        // try left side before ':'
        if (raw.contains(':')) seeds.add(sanitizeSeed(raw.split(':').first));
        // split on common separators like '-' and '—' and include parts
        final parts = raw.split(RegExp(r"\s[-—–|]\s"));
        for (final p in parts) seeds.add(sanitizeSeed(p));

        // add n-gram prefixes (3-word and 2-word) to broaden search
        final tokens2 = clean.split(' ').where((t) => t.isNotEmpty).toList();
        if (tokens2.length >= 3) seeds.add(tokens2.take(3).join(' '));
        if (tokens2.length >= 2) seeds.add(tokens2.take(2).join(' '));
      }
      if (seriesUrl != null && seriesUrl.isNotEmpty) {
        final fromUrl = extractAnimeName(seriesUrl);
        if (fromUrl != null && fromUrl.isNotEmpty) seeds.add(sanitizeSeed(fromUrl));
      }
      // remove any empty seeds
      seeds.removeWhere((s) => s.trim().isEmpty);

      // Build additional fallback seeds: token prefixes, reversed order, hyphenated/concatenated forms
      final fallbackSeeds = <String>{};
      for (final s in seeds.toList()) {
        final toks = s.split(RegExp(r"\s+")).where((t) => t.isNotEmpty).toList();
        if (toks.length > 1) {
          // prefixes
          for (int n = 1; n <= (toks.length < 3 ? toks.length : 3); n++) {
            fallbackSeeds.add(toks.take(n).join(' '));
          }
          // reversed
          fallbackSeeds.add(toks.reversed.join(' '));
          // hyphenated and concatenated
          fallbackSeeds.add(toks.join('-'));
          fallbackSeeds.add(toks.join(''));
          // last two/three tokens
          if (toks.length >= 2) fallbackSeeds.add(toks.skip(toks.length - 2).join(' '));
          if (toks.length >= 3) fallbackSeeds.add(toks.skip(toks.length - 3).join(' '));
        }
        // also try lowercased and titlecased variants
        fallbackSeeds.add(s.toLowerCase());
        fallbackSeeds.add(s.split(' ').map((w) => w.isNotEmpty ? (w[0].toUpperCase() + w.substring(1)) : w).join(' '));
      }

      // If we have a seriesUrl, try the last path segment (romaji-like) as fallback too
      if (seriesUrl != null && seriesUrl.isNotEmpty) {
        final ex = extractAnimeName(seriesUrl);
        if (ex != null && ex.isNotEmpty) fallbackSeeds.add(ex);
      }

      fallbackSeeds.removeWhere((s) => s.trim().isEmpty);
      seeds.addAll(fallbackSeeds);
      if (kDebugMode) print('🔎 [ANILIST] search seeds: $seeds');

      AnimeMetadata? bestMeta;
      double bestScore = 0.0;

      for (final seed in seeds) {
        if (kDebugMode) print('🔎 [ANILIST] fetchSeriesMetadata trying seed="$seed" usePredictDelay=$usePredictDelay');
        final variables = {'search': seed};
        final resp = await _postWithOptionalPredictDelay(
          Uri.parse('https://graphql.anilist.co'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'query': q, 'variables': variables}),
          timeout: const Duration(seconds: 10),
          usePredictDelay: usePredictDelay,
        );
        if (kDebugMode) print('🔎 [ANILIST] fetchSeriesMetadata seed="$seed" status=${resp.statusCode}');
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

            // Log the media object for debugging
            if (kDebugMode) {
              print('🔎 [ANILIST] Processing media: ${json.encode(media)}');
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
        if (bestScore >= 0.75) break;
      }

      // Accept matches above threshold (lowered to be more permissive)
      if (bestMeta != null && bestScore >= 0.45) {
        // save in cache under normalized key
        await cache.save(key, bestMeta);
        return bestMeta;
      }

      // Fallback: if we found any candidate with moderate score, accept it to increase hit rate
      if (bestMeta != null && bestScore >= 0.40) {
        if (kDebugMode) print('🔎 [ANILIST] Accepting lower-confidence match (score=$bestScore) for key=$key');
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
