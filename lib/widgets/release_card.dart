import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_release.dart';
import '../models/watchlist.dart';
import '../models/notification_log.dart';
import '../services/crunchyroll_service.dart';
import '../services/watchlist_service.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../services/next_episode_predictor.dart';
import '../repositories/seen_repository.dart';
import '../utils/title_utils.dart';
import 'anime_details_dialog.dart';
import '../utils/ui_utils.dart';
import 'anime_pattern_painter.dart';

/// Widget für eine Release-Karte im Kalender
class ReleaseCard extends StatefulWidget {
  final AnimeRelease release;
  final WatchlistService? watchlistService;

  const ReleaseCard({super.key, required this.release, this.watchlistService});

  @override
  State<ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<ReleaseCard> {
  bool _isProcessingWatchlist = false;
  bool _isInWatchlist = false;

  @override
  void initState() {
    super.initState();
    _initWatchlistStatus();
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.addListener(_onWatchlistChanged);
    }
  }

  Future<void> _initWatchlistStatus() async {
    if (widget.watchlistService == null) {
      return;
    }
    try {
      final exists = widget.watchlistService!.watchlist.entries.any(
        (e) => e.animeId == widget.release.seriesUrl,
      );
      if (mounted) {
        setState(() {
          _isInWatchlist = exists;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing watchlist status: $e');
      }
    }
  }

  @override
  void dispose() {
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.removeListener(_onWatchlistChanged);
    }
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (widget.watchlistService == null) {
      return;
    }
    try {
      final exists = widget.watchlistService!.watchlist.entries.any(
        (e) => e.animeId == widget.release.seriesUrl,
      );
      if (mounted) {
        setState(() {
          _isInWatchlist = exists;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error handling watchlist change: $e');
      }
    }
  }

  void _showAnimeDetailsDialog() async {
    try {
      final tempLog = NotificationLog(
        favoriteTitle: widget.release.title,
        releaseTitle: widget.release.episodeTitle,
        episodeNumber: widget.release.episodeNumber,
        notifyTime: DateTime.now(),
      );
      final hash = tempLog.generateContentHash();
      await SeenRepository().markSeen(hash);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking seen: $e');
      }
    }

    if (!mounted) {
      return;
    }
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AnimeDetailsDialog(
          release: widget.release,
          crunchyrollService: CrunchyrollService(),
          watchlistService: widget.watchlistService,
          onAddToWatchlist: (release) async {
            final ws = widget.watchlistService;
            if (ws == null) {
              return;
            }
            setState(() {
              _isProcessingWatchlist = true;
            });
            try {
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
                final best = await AnilistService().findBestMatch(
                  release.title,
                );
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

              if (autoId != null) {
                try {
                  final predictor = NextEpisodePredictor(cs, AnilistService());
                  await predictor.predictNextForSeries(
                    entry.animeId,
                    entry.title,
                  );
                } catch (_) {}
              }

              if (mounted) {
                setState(() {
                  _isInWatchlist = true;
                });
              }
            } catch (e) {
              if (kDebugMode) {
                print('❌ Error adding to watchlist: $e');
              }
            } finally {
              if (mounted) {
                setState(() {
                  _isProcessingWatchlist = false;
                });
              }
            }
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showAnimeDetailsDialog,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                if (widget.release.imageUrl != null &&
                    widget.release.imageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.release.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildAnimePlaceholder(),
                    errorWidget: (context, url, error) =>
                        _buildAnimePlaceholder(),
                  )
                else
                  _buildAnimePlaceholder(),
                if (!widget.release.isPredicted)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      radius: 20,
                      child: _isProcessingWatchlist
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 2,
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                _isInWatchlist
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isInWatchlist
                                    ? Colors.red
                                    : Colors.white,
                                size: 20,
                              ),
                              onPressed: () async {
                                final ws = widget.watchlistService;
                                if (ws == null) {
                                  return;
                                }
                                setState(() {
                                  _isProcessingWatchlist = true;
                                });
                                try {
                                  final id = widget.release.seriesUrl;
                                  final exists = ws.watchlist.entries.any(
                                    (e) => e.animeId == id,
                                  );
                                  if (exists) {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Eintrag entfernen'),
                                        content: Text(
                                          'Möchtest du "${widget.release.title}" wirklich aus der Watchlist entfernen?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Abbrechen'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: Text(
                                              'Entfernen',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      ws.watchlist.removeEntry(id);
                                      await ws.saveWatchlist();
                                      if (mounted) {
                                        UIUtils.showSnackBar(
                                          context,
                                          SnackBar(
                                            content: Text(
                                              '${widget.release.title} aus Watchlist entfernt',
                                            ),
                                          ),
                                        );
                                      }
                                    } else {
                                      if (mounted) {
                                        setState(() {
                                          _isProcessingWatchlist = false;
                                        });
                                      }
                                      return;
                                    }
                                  } else {
                                    final cs = CrunchyrollService();
                                    final parsedCurrent =
                                        int.tryParse(
                                          widget.release.episodeNumber,
                                        ) ??
                                        0;
                                    final knownMax = await cs
                                        .getMaxEpisodeFromCache(
                                          id,
                                          widget.release.title,
                                        );
                                    final total =
                                        (knownMax != null &&
                                            knownMax > parsedCurrent)
                                        ? knownMax
                                        : parsedCurrent;

                                    int? autoId;
                                    try {
                                      final best = await AnilistService()
                                          .findBestMatch(widget.release.title);
                                      if (best != null) {
                                        autoId = best.id;
                                        final cache = AnilistCache();
                                        final key = normalizeTitle(
                                          widget.release.seriesUrl,
                                        );
                                        await cache.save(key, best);
                                      }
                                    } catch (_) {}

                                    final entry = WatchlistEntry(
                                      animeId: id,
                                      title: widget.release.title,
                                      imageUrl: widget.release.imageUrl,
                                      episodesWatched: 0,
                                      totalEpisodes: total,
                                      anilistId: autoId,
                                      addedAt: DateTime.now(),
                                    );
                                    ws.watchlist.addEntry(entry);
                                    await ws.saveWatchlist();
                                    cs.scheduleWatchlistEntryUpdate(ws, entry);
                                    if (mounted) {
                                      UIUtils.showSnackBar(
                                        context,
                                        SnackBar(
                                          content: Text(
                                            '${widget.release.title} zur Watchlist hinzugefügt${autoId != null ? " (Verknüpft)" : ""}',
                                          ),
                                        ),
                                      );
                                    }

                                    if (autoId != null) {
                                      try {
                                        final predictor = NextEpisodePredictor(
                                          cs,
                                          AnilistService(),
                                        );
                                        await predictor.predictNextForSeries(
                                          entry.animeId,
                                          entry.title,
                                        );
                                      } catch (_) {}
                                    }
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _isProcessingWatchlist = false;
                                      _isInWatchlist = !exists;
                                    });
                                  }
                                } catch (e) {
                                  if (kDebugMode) {
                                    print(
                                      '❌ Error toggling watchlist from card: $e',
                                    );
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _isProcessingWatchlist = false;
                                    });
                                  }
                                }
                              },
                              padding: EdgeInsets.zero,
                            ),
                    ),
                  ),
                if (widget.release.isPremiere)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'PREMIERE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.release.timeString,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.release.isPredicted
                        ? '${widget.release.title} (Vorhersage)'
                        : widget.release.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.release.episodeInfo,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimePlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade300,
            Colors.deepOrange.shade400,
            Colors.red.shade400,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: CustomPaint(painter: AnimePatternPainter()),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.live_tv,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Cover wird geladen...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
