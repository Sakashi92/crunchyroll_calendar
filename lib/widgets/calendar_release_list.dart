import 'package:flutter/material.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import 'release_card.dart';

class CalendarReleaseList extends StatelessWidget {
  final List<AnimeRelease> releases;
  final bool isLoading;
  final WatchlistService? watchlistService;
  final EdgeInsetsGeometry? contentPadding;
  final Widget? header;
  final VoidCallback? onHide;

  const CalendarReleaseList({
    super.key,
    required this.releases,
    required this.isLoading,
    this.watchlistService,
    this.contentPadding,
    this.header,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Threshold for grid: 600px
          final bool useGrid = width > 600;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header),
              if (isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildLoadingState(),
                )
              else if (releases.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                )
              else
                SliverPadding(
                  padding: contentPadding ?? const EdgeInsets.all(8),
                  sliver: useGrid
                      ? _buildGrid(width)
                      : SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final release = releases[index];
                            return ReleaseCard(
                              key: ValueKey(
                                '${release.title}_${release.episodeInfo}',
                              ),
                              release: release,
                              watchlistService: watchlistService,
                              onHide: onHide,
                            );
                          }, childCount: releases.length),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGrid(double width) {
    // Calculate number of columns
    // We want each card to be at least ~300px wide
    int crossAxisCount = (width / 350).floor();
    if (crossAxisCount < 2) crossAxisCount = 2;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final release = releases[index];
        return ReleaseCard(
          key: ValueKey('${release.title}_${release.episodeInfo}'),
          release: release,
          watchlistService: watchlistService,
          onHide: onHide,
        );
      }, childCount: releases.length),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          height: 50, // Reduced height for smoother look in sliver
          child: Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Lade Releases…',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'Keine Anime-Releases an diesem Tag bisher.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
