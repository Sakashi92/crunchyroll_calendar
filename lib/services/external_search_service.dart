import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ExternalSearchService {
  static final ExternalSearchService _instance =
      ExternalSearchService._internal();
  factory ExternalSearchService() => _instance;
  ExternalSearchService._internal();

  /// Searches for a Crunchyroll series URL for a given title.
  /// First tries to use Kitsu API, then returns null (manual search fallback logic is handled in the UI).
  Future<String?> findCrunchyrollUrl(String title) async {
    if (title.isEmpty) return null;

    // 1. Try Kitsu (API, very reliable for streaming links)
    if (kDebugMode) print('🔎 [SEARCH] Trying Kitsu for: $title');
    try {
      final kitsuUrl = await _searchKitsu(title);
      if (kitsuUrl != null) return _canonicalizeUrl(kitsuUrl);
    } catch (e) {
      if (kDebugMode) print('❌ [SEARCH] Kitsu Error: $e');
    }

    return null;
  }

  Future<String?> _searchKitsu(String title) async {
    try {
      final encodedTitle = Uri.encodeComponent(title);
      final url = Uri.parse(
        'https://kitsu.io/api/edge/anime?filter[text]=$encodedTitle&include=streamingLinks&page[limit]=3',
      );

      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final included = data['included'] as List?;
        if (included != null) {
          final crLinks = included
              .where(
                (item) =>
                    item['type'] == 'streamingLinks' &&
                    (item['attributes']?['url'] as String?)?.contains(
                          'crunchyroll.com',
                        ) ==
                        true,
              )
              .map((item) => item['attributes']['url'] as String)
              .toList();

          if (crLinks.isNotEmpty) {
            final result = _pickBestMatch(title, crLinks);
            if (result.isNotEmpty) return result;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _canonicalizeUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return url;

      final segments = uri.pathSegments;
      final seriesIdx = segments.indexOf('series');
      if (seriesIdx != -1 && segments.length > seriesIdx + 1) {
        final id = segments[seriesIdx + 1];
        // Enforce the format: https://www.crunchyroll.com/de/series/ID/
        // Default to 'de' as requested by the user
        String locale = 'de';
        if (seriesIdx > 0 && segments[seriesIdx - 1].length == 2) {
          locale = segments[seriesIdx - 1];
        }
        return 'https://www.crunchyroll.com/$locale/series/$id/';
      }
    } catch (_) {}
    return url;
  }

  String _pickBestMatch(String title, List<String> links) {
    if (links.isEmpty) return '';

    final normalizedTitle = title.toLowerCase();
    final titleWords = normalizedTitle
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 2)
        .toList();

    if (titleWords.isEmpty) return links.first;

    String? bestMatch;
    int maxScore = -1;

    for (final link in links) {
      int score = 0;
      final uri = Uri.tryParse(link);
      if (uri == null) continue;

      final segments = uri.pathSegments;
      final seriesIdx = segments.indexOf('series');
      if (seriesIdx == -1 || seriesIdx >= segments.length - 1) continue;

      final id = segments[seriesIdx + 1];
      final slug = segments.length > seriesIdx + 2
          ? segments[seriesIdx + 2]
          : '';

      // Heuristic: Prefer alphanumeric IDs over purely numeric IDs (legacy)
      final isAlphanumeric = RegExp(r'^[A-Z0-9]+$').hasMatch(id.toUpperCase());
      final isNumeric = RegExp(r'^\d+$').hasMatch(id);

      if (isAlphanumeric && !isNumeric)
        score += 5; // Strategic bonus for modern IDs

      // Check slug for title words
      for (final word in titleWords) {
        if (slug.contains(word)) score += 3;
        if (id.toLowerCase().contains(word)) score += 1;
      }

      // Bonus for exact slug match (if title is long enough)
      final expectedSlug = normalizedTitle.replaceAll(' ', '-');
      if (slug == expectedSlug && expectedSlug.length > 5) score += 10;

      // Bonus if multiple words match
      int wordMatches = 0;
      for (final word in titleWords) {
        if (slug.contains(word)) wordMatches++;
      }
      if (wordMatches >= 2) score += 5;

      if (kDebugMode) {
        print('🔎 [SCORE] link: $slug (id: $id) -> score: $score');
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = link;
      }
    }

    // Require a minimum confidence score
    if (maxScore < 2) {
      if (kDebugMode)
        print('⚠️ [SEARCH] No high-confidence match found for "$title"');
      return '';
    }

    return bestMatch ?? '';
  }

  /// Returns a search URL for manual use.
  String getManualSearchUrl(String title) {
    return 'https://www.google.com/search?q=site:crunchyroll.com/series+"${Uri.encodeComponent(title)}"';
  }
}
