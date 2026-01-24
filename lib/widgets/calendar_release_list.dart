import 'package:flutter/material.dart';
import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import 'release_card.dart';

class CalendarReleaseList extends StatelessWidget {
  final List<AnimeRelease> releases;
  final bool isLoading;
  final WatchlistService? watchlistService;

  const CalendarReleaseList({
    super.key,
    required this.releases,
    required this.isLoading,
    this.watchlistService,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingState();
    }

    if (releases.isEmpty) {
      return _buildEmptyState(context);
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        itemCount: releases.length,
        itemBuilder: (context, index) {
          final release = releases[index];
          return ReleaseCard(
            key: ValueKey('${release.title}_${release.episodeInfo}'),
            release: release,
            watchlistService: watchlistService,
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(
          height: 200,
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
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Center(
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
            ),
          ),
        ],
      ),
    );
  }
}
