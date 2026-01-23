import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/anime_release.dart';
import 'anilist_service.dart';
import 'crunchyroll_service.dart';
import 'prediction_notifier.dart';
import '../models/anime_metadata.dart';
import 'anilist_cache.dart';
import '../utils/title_utils.dart';

/// Simple next-episode predictor.
/// - Reads recent releases for a series from the CrunchyrollService cache
/// - Computes average interval between last N releases
/// - Uses AniList metadata (if available) to bound predictions
/// - Inserts a synthetic AnimeRelease into CrunchyrollService cache via `addPredictedRelease`
class NextEpisodePredictor {
  final CrunchyrollService crunchy;
  final AnilistService anilist;

  NextEpisodePredictor(this.crunchy, this.anilist);

  /// Predict next episode for a given series (identified by seriesUrl or title)
  /// Returns the predicted release or null if prediction not possible.
  Future<AnimeRelease?> predictNextForSeries(String? seriesUrl, String? title, {int? anilistId}) async {
    try {
      final now = DateTime.now();
      print('🔎 [PREDICTOR] Predicting next for seriesUrl=${seriesUrl ?? '-'} title=${title ?? '-'}');
      // load cached releases
      final releases = await crunchy.getReleasesForSeriesCached(seriesUrl, title);
      
      // PREDICTOR UPDATE: Check AniList metadata first for an exact scheduled date
      final effectiveTitle = title ?? (releases != null && releases.isNotEmpty ? releases.last.title : null);
      if (effectiveTitle != null) {
          // If we have a direct anilistId from the watchlist, prepopulate the cache key
          if (anilistId != null) {
            final cache = AnilistCache();
            final cacheKey = normalizeTitle(seriesUrl ?? title ?? effectiveTitle);
            final existing = await cache.get(cacheKey);
            if (existing == null || existing.id != anilistId) {
               await cache.save(cacheKey, AnimeMetadata(id: anilistId));
            }
          }

          final meta = await anilist.fetchSeriesMetadata(seriesUrl, effectiveTitle, usePredictDelay: true);
          
          // If we have an exact future date from AniList, use it!
          if (meta?.nextEpisodeDate != null) {
              final nextDate = meta!.nextEpisodeDate!;
              final todayMidnight = DateTime(now.year, now.month, now.day);
              final minAllowed = todayMidnight.subtract(const Duration(hours: 24));
              final maxAllowedMidnight = todayMidnight.add(const Duration(days: 7));
              
              final nextDay = DateTime(nextDate.year, nextDate.month, nextDate.day);
              
              if (nextDate.isAfter(minAllowed) && !nextDay.isAfter(maxAllowedMidnight)) {
                  final bestTitle = title ?? (releases != null && releases.isNotEmpty ? releases.last.title : meta?.siteUrl) ?? 'Unknown';
                  final epParams = meta?.nextEpisodeNumber ?? (
                      (releases != null && releases.isNotEmpty) 
                      ? (int.tryParse(releases.last.episodeNumber) != null ? (int.parse(releases.last.episodeNumber) + 1).toString() : '1') 
                      : '1'
                  );
                  
                  // Fetch high-res image from Kitsu
                  String? displayImage;
                  try {
                    final kImg = await crunchy.fetchImageForTitle(bestTitle);
                    if (kImg.isNotEmpty) displayImage = kImg;
                  } catch (_) {}
                  
                  // Fallback to AniList or old release image
                  displayImage ??= meta?.imageUrl ?? (releases != null && releases.isNotEmpty ? releases.last.imageUrl : null);

                  final predicted = AnimeRelease(
                    title: bestTitle,
                    episodeNumber: epParams,
                    episodeTitle: '',
                    releaseTime: nextDate,
                    imageUrl: displayImage,
                    description: meta?.description ?? (releases != null && releases.isNotEmpty ? releases.last.description : null),
                    seriesUrl: seriesUrl ?? (releases != null && releases.isNotEmpty ? releases.last.seriesUrl : meta?.siteUrl) ?? '',
                    episodeUrl: meta?.siteUrl ?? (releases != null && releases.isNotEmpty ? releases.last.episodeUrl : null) ?? '',
                    isPremiere: false,
                    isPredicted: true,
                  );
                  
                  await crunchy.addPredictedRelease(predicted);
                  predictionsUpdated.value = true;
                  print('✅ [PREDICTOR] Predicted using AniList Schedule: $bestTitle -> ep $epParams @ $nextDate');
                  return predicted;
              }
          }
      }

      if (releases == null || releases.length < 2) return null;

      // sort by releaseTime
      releases.sort((a, b) => a.releaseTime.compareTo(b.releaseTime));

      // take last up to 6 intervals
      final recent = releases.reversed.take(6).toList().reversed.toList();
      final List<Duration> intervals = [];
      for (var i = 1; i < recent.length; i++) {
        intervals.add(recent[i].releaseTime.difference(recent[i - 1].releaseTime).abs());
      }
      if (intervals.isEmpty) return null;

      // compute median interval (robust to outliers)
      intervals.sort((a, b) => a.inSeconds.compareTo(b.inSeconds));
      final median = intervals[intervals.length ~/ 2];

      final lastRelease = recent.last;
      final predictedDate = lastRelease.releaseTime.add(median);

      // Relaxed window: Allow predictions from the last 24 hours (so today's episodes stay visible)
      // and up to 7 days in the future.
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final minAllowed = todayMidnight.subtract(const Duration(hours: 24));
      final maxAllowedMidnight = todayMidnight.add(const Duration(days: 7));
      
      final predictedDay = DateTime(predictedDate.year, predictedDate.month, predictedDate.day);

      if (predictedDate.isBefore(minAllowed) || predictedDay.isAfter(maxAllowedMidnight)) {
        if (kDebugMode) print('Skipping prediction for $title: predicted date $predictedDate is outside allowed window ($minAllowed to $maxAllowedMidnight)');
        return null;
      }

      // fetch AniList metadata to get totalEpisodes (optional)
      // Note: We already fetched metadata above, but if logic flows here, we re-use or re-fetch?
      // For simplicity in this edit, just fetch again or ensure variable is accessible.
      // Ideally we would have stored 'meta' from above. 
      // Let's re-fetch briefly or assume partial data flow.
      print('🔎 [PREDICTOR] Fetching AniList metadata for validation...');
      final meta = await anilist.fetchSeriesMetadata(seriesUrl, effectiveTitle, usePredictDelay: true);
      print('🔎 [PREDICTOR] AniList metadata fetched for "$effectiveTitle": totalEpisodes=${meta?.totalEpisodes}');

      // compute predicted episode number: try parse last episode number
      int lastEp = int.tryParse(lastRelease.episodeNumber) ?? 0;
      final predictedEpisode = (lastEp > 0) ? lastEp + 1 : (meta?.totalEpisodes != null ? (meta!.totalEpisodes! - 0) : lastEp + 1);

      // cap predictedEpisode by totalEpisodes if known
      int? totalEpisodes = meta?.totalEpisodes;
      if (totalEpisodes != null && predictedEpisode > totalEpisodes) {
        // no prediction if already at or beyond total
        return null;
      }

      final finalTitle = title ?? lastRelease.title;
      
      // Fetch high-res image from Kitsu
      String? displayImage;
      try {
        final kImg = await crunchy.fetchImageForTitle(finalTitle);
        if (kImg.isNotEmpty) displayImage = kImg;
      } catch (_) {}
      
      displayImage ??= meta?.imageUrl ?? lastRelease.imageUrl;

      final predicted = AnimeRelease(
        title: finalTitle,
        episodeNumber: predictedEpisode.toString(),
        episodeTitle: '',
        releaseTime: predictedDate,
        imageUrl: displayImage,
        description: meta?.description ?? lastRelease.description,
        seriesUrl: seriesUrl ?? lastRelease.seriesUrl,
        episodeUrl: meta?.siteUrl ?? lastRelease.episodeUrl,
        isPremiere: false,
        isPredicted: true,
      );

      // add prediction to CrunchyrollService cache (method added below should exist)
      await crunchy.addPredictedRelease(predicted);
      // Signal UI to reload cached predictions
      predictionsUpdated.value = true;
      print('✅ [PREDICTOR] Predicted next for $title -> ep ${predictedEpisode} @ $predictedDate');
      return predicted;
    } catch (e) {
      print('❌ [PREDICTOR] Error predicting next episode for $title: $e');
      return null;
    }
  }

  /// Predict for all series known in cache/watchlist. This iterates over unique seriesUrls.
  Future<void> predictForAllKnownSeries() async {
    // Collect releases from the last 7 days and predict for each unique series
    final now = DateTime.now();
    final releases = <AnimeRelease>[];
    for (int d = 0; d < 7; d++) {
      final day = now.subtract(Duration(days: d));
      try {
        final dayReleases = await crunchy.getReleasesForDay(day);
        releases.addAll(dayReleases);
      } catch (e) {
        if (kDebugMode) print('Error fetching releases for $day: $e');
      }
    }

    // Deduplicate by seriesUrl first, fallback to title if missing
    final Map<String, String?> uniqueSeries = {};
    for (final r in releases) {
      final key = (r.seriesUrl != null && r.seriesUrl!.isNotEmpty) ? r.seriesUrl! : (r.title ?? '');
      if (!uniqueSeries.containsKey(key)) uniqueSeries[key] = r.title;
    }

    final seriesList = uniqueSeries.entries.toList();
    print('🔎 [PREDICTOR] Running predictions for ${seriesList.length} series discovered in last 7 days');

    int i = 0;
    for (final entry in seriesList) {
      i++;
      final seriesId = entry.key;
      final title = entry.value;
      print('🔎 [PREDICTOR] (${i}/${seriesList.length}) Starting prediction for seriesId=$seriesId title=$title');
      await predictNextForSeries(seriesId, title);
      print('🔎 [PREDICTOR] (${i}/${seriesList.length}) Finished prediction for seriesId=$seriesId');
    }

    print('🔎 [PREDICTOR] All predictions complete');
  }
}
