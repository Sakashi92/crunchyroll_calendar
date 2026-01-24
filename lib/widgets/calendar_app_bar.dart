import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import '../services/crunchyroll_service.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../services/next_episode_predictor.dart';
import '../models/watchlist.dart';
import '../utils/title_utils.dart';
import '../pages/search_page.dart';
import '../pages/watchlist_page.dart';
import 'anime_details_dialog.dart';

class CalendarAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Map<DateTime, List<AnimeRelease>> releases;
  final WatchlistService? watchlistService;
  final bool isLoadingImages;
  final int imagesLoaded;
  final int imagesToLoad;
  final VoidCallback onOpenSettings;
  final VoidCallback onRefresh;

  const CalendarAppBar({
    super.key,
    required this.releases,
    this.watchlistService,
    required this.isLoadingImages,
    required this.imagesLoaded,
    required this.imagesToLoad,
    required this.onOpenSettings,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      toolbarHeight: 48,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Kalender'),
          if (isLoadingImages)
            Text(
              'Lade Bilder... $imagesLoaded/$imagesToLoad',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Suche',
          onPressed: () => _handleSearch(context),
        ),
        IconButton(
          icon: const Icon(Icons.favorite),
          tooltip: 'Watchlist',
          onPressed: () {
            if (watchlistService == null) {
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => WatchlistPage(service: watchlistService!),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Einstellungen',
          onPressed: onOpenSettings,
        ),
      ],
      bottom: isLoadingImages
          ? PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: imagesToLoad > 0 ? imagesLoaded / imagesToLoad : null,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _handleSearch(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SearchPage(releases: releases, watchlistService: watchlistService),
      ),
    );
    if (result != null && result is Map) {
      final AnimeRelease r = result['release'] as AnimeRelease;
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (BuildContext ctx) => AnimeDetailsDialog(
            release: r,
            crunchyrollService: CrunchyrollService(),
            watchlistService: watchlistService,
            onAddToWatchlist: (release) async {
              await _addToWatchlist(ctx, release);
            },
          ),
        );
      }
    }
  }

  Future<void> _addToWatchlist(
    BuildContext context,
    AnimeRelease release,
  ) async {
    final ws = watchlistService;
    if (ws == null) {
      return;
    }
    final cs = CrunchyrollService();
    final parsedCurrent = int.tryParse(release.episodeNumber) ?? 0;
    final knownMax = await cs.getMaxEpisodeFromCache(
      release.seriesUrl,
      release.title,
    );
    final total = (knownMax != null && knownMax > parsedCurrent)
        ? knownMax
        : parsedCurrent;

    int? autoId;
    try {
      final best = await AnilistService().findBestMatch(release.title);
      if (best != null) {
        autoId = best.id;
        final cache = AnilistCache();
        final key = normalizeTitle(release.seriesUrl);
        await cache.save(key, best);
      }
    } catch (_) {}

    final entry = WatchlistEntry(
      animeId: release.seriesUrl,
      title: release.title,
      imageUrl: release.imageUrl,
      episodesWatched: 0,
      totalEpisodes: total,
      anilistId: autoId,
      addedAt: DateTime.now(),
    );
    ws.watchlist.addEntry(entry);
    await ws.saveWatchlist();
    cs.scheduleWatchlistEntryUpdate(ws, entry);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Zur Watchlist hinzugefügt: ${release.title}${autoId != null ? " (Verknüpft)" : ""}',
          ),
        ),
      );

      if (autoId != null) {
        try {
          final predictor = NextEpisodePredictor(cs, AnilistService());
          await predictor.predictNextForSeries(entry.animeId, entry.title);
        } catch (_) {}
      }
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(48 + 4); // AppBar height + potential progress bar
}
