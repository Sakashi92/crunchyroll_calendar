import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_release.dart';
import '../models/favorite_anime.dart';
import '../models/notification_log.dart';
import '../repositories/favorites_repository.dart';
import '../repositories/seen_repository.dart';
import '../services/crunchyroll_service.dart';
import '../services/watchlist_service.dart';
import '../utils/favorites_notifier.dart';
import 'anime_placeholder.dart';
import 'anime_details_dialog.dart';

/// Stateful Widget für Release Card mit Favoriten-Status
class ReleaseCard extends StatefulWidget {
  final AnimeRelease release;
  final WatchlistService? watchlistService;

  const ReleaseCard({super.key, required this.release, this.watchlistService});

  @override
  State<ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<ReleaseCard> {
  bool _isFavorite = false;
  late final FavoritesRepository _favoritesRepository;
  bool _isInitialized = false;
  static final Map<String, bool> _favoriteCache = {};

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    
    favoritesChangeNotifier.addListener(_onFavoritesChanged);
    
    if (_favoriteCache.containsKey(widget.release.title)) {
      _isFavorite = _favoriteCache[widget.release.title]!;
      _isInitialized = true;
    }
    
    _checkIfFavorite();
  }

  @override
  void dispose() {
    favoritesChangeNotifier.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    _checkIfFavorite();
  }

  Future<void> _checkIfFavorite() async {
    try {
      final isFav = await _favoritesRepository.isFavorite(widget.release.title);
      _favoriteCache[widget.release.title] = isFav;
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking favorite: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final wasAlreadyFavorite = _isFavorite;
    
    setState(() {
      _isFavorite = !_isFavorite;
    });
    
    try {
      if (wasAlreadyFavorite) {
        await _favoritesRepository.removeFavorite(widget.release.title);
        _favoriteCache[widget.release.title] = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Aus Favoriten entfernt'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        final favorite = FavoriteAnime(
          title: widget.release.title,
          imageUrl: widget.release.imageUrl,
          seriesUrl: widget.release.seriesUrl,
          addedDate: DateTime.now(),
        );
        await _favoritesRepository.addFavorite(favorite);
        _favoriteCache[widget.release.title] = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❤️ Zu Favoriten hinzugefügt'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
      
      favoritesChangeNotifier.value++;
      
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling favorite: $e');
      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Fehler beim Speichern')),
        );
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
      if (kDebugMode) print('❌ Error marking seen: $e');
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AnimeDetailsDialog(
          release: widget.release,
          crunchyrollService: CrunchyrollService(),
          watchlistService: widget.watchlistService,
        );
      },
    );

    _checkIfFavorite();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      final img = widget.release.imageUrl ?? '<null>'; 
      print('🔎 ReleaseCard.build: ${widget.release.title} imageUrl=$img');
    }
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
                if (widget.release.imageUrl != null && widget.release.imageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: widget.release.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const AnimePlaceholder(),
                    errorWidget: (context, url, error) => const AnimePlaceholder(),
                  )
                else
                  const AnimePlaceholder(),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _isInitialized
                      ? CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 20,
                          child: IconButton(
                            icon: Icon(
                              _isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: _isFavorite ? Colors.red : Colors.white,
                              size: 24,
                            ),
                            onPressed: _toggleFavorite,
                            padding: EdgeInsets.zero,
                          ),
                        )
                      : const CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 22,
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                ),
                if (widget.release.isPremiere)
                  Positioned(
                    top: 8,
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
                    widget.release.title,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.release.episodeInfo,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
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
}
