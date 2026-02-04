import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import '../services/crunchyroll_service.dart';
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

  const CalendarAppBar({
    super.key,
    required this.releases,
    this.watchlistService,
    required this.isLoadingImages,
    required this.imagesLoaded,
    required this.imagesToLoad,
    required this.onOpenSettings,
    required this.activeDay,
    required this.currentReleases,
    required this.isMinimized,
    required this.onToggleExpand,
  });

  final DateTime activeDay;
  final List<AnimeRelease> currentReleases;
  final bool isMinimized;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final baseTitle = Column(
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
    );

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      toolbarHeight: 48,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: baseTitle,
      flexibleSpace: (isLandscape && isMinimized)
          ? SafeArea(
              child: Center(
                child: InkWell(
                  onTap: onToggleExpand,
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('E, d. MMM', 'de_DE').format(activeDay),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currentReleases.isEmpty
                              ? 'Kein Release'
                              : '${currentReleases.length} Release${currentReleases.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
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
          ),
        );
      }
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(48 + 4); // AppBar height + potential progress bar
}
