import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:translator/translator.dart';
import '../models/anime_release.dart';
import '../models/favorite_anime.dart';
import '../repositories/favorites_repository.dart';
import '../services/crunchyroll_service.dart';
import '../settings.dart';
import '../utils/favorites_notifier.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';

/// Dialog Widget für Anime-Details mit asynchronem Laden der Beschreibung
class AnimeDetailsDialog extends StatefulWidget {
  final AnimeRelease release;
  final CrunchyrollService crunchyrollService;
  final VoidCallback? onFavoriteRemoved;
  final void Function(AnimeRelease release)? onAddToWatchlist;
  final WatchlistService? watchlistService;

  const AnimeDetailsDialog({
    super.key,
    required this.release,
    required this.crunchyrollService,
    this.onFavoriteRemoved,
    this.onAddToWatchlist,
    this.watchlistService,
  });

  @override
  State<AnimeDetailsDialog> createState() => _AnimeDetailsDialogState();
}

class _AnimeDetailsDialogState extends State<AnimeDetailsDialog> {
  String? _descriptionOriginal;
  String? _descriptionTranslated;
  bool _isLoadingDescription = true;
  bool _isTranslating = false;
  bool _showGerman = true;
  bool _autoTranslateEnabled = true;
  bool _isFavorite = false;
  bool _isLoadingFavorite = true;
  final _translator = GoogleTranslator();
  late final FavoritesRepository _favoritesRepository;
  bool _isInWatchlist = false;
  bool _isProcessingWatchlist = false;
  int? _knownMaxEpisode;

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    _loadDescription();
    _checkIfFavorite();
    _prefetchKnownMaxEpisode();
    _updateWatchlistState();
  }

  Future<void> _prefetchKnownMaxEpisode() async {
    try {
      final id = widget.release.seriesUrl;
      final title = widget.release.title;
      final cs = widget.crunchyrollService;
      final known = await cs.getMaxEpisodeForSeries(id, title);
      if (known != null) {
        _knownMaxEpisode = known;
      } else {
        // Try a forced refresh if cache didn't contain useful data
        await cs.forceRefresh(forMonth: DateTime.now());
        final known2 = await cs.getMaxEpisodeForSeries(id, title);
        _knownMaxEpisode = known2;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error prefetching known max episode: $e');
    }
  }

  void _updateWatchlistState() {
    final ws = widget.watchlistService;
    if (ws == null) return;
    final id = widget.release.seriesUrl;
    _isInWatchlist = ws.watchlist.entries.any((e) => e.animeId == id);
  }

  Future<void> _checkIfFavorite() async {
    try {
      final isFav = await _favoritesRepository.isFavorite(widget.release.title);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
          _isLoadingFavorite = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking favorite: $e');
      if (mounted) {
        setState(() {
          _isLoadingFavorite = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      if (_isFavorite) {
        await _favoritesRepository.removeFavorite(widget.release.title);
        if (mounted) {
          setState(() => _isFavorite = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Aus Favoriten entfernt'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        // Notify caller that a favorite was removed (e.g., favorites page)
        if (widget.onFavoriteRemoved != null) widget.onFavoriteRemoved!();
      } else {
        final favorite = FavoriteAnime(
          title: widget.release.title,
          imageUrl: widget.release.imageUrl,
          seriesUrl: widget.release.seriesUrl,
          addedDate: DateTime.now(),
        );
        await _favoritesRepository.addFavorite(favorite);
        if (mounted) {
          setState(() => _isFavorite = true);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Fehler beim Speichern')),
        );
      }
    }
  }

  Future<void> _loadDescription() async {
    final description = await widget.crunchyrollService.fetchDescription(widget.release);
    if (mounted) {
      setState(() {
        _descriptionOriginal = description;
        _isLoadingDescription = false;
      });
      final autoTranslate = await AppSettings.getAutoTranslate();
      _autoTranslateEnabled = autoTranslate;
      if (autoTranslate) {
        _translateDescription();
      } else {
        setState(() {
          _showGerman = false;
        });
      }
    }
  }

  Future<void> _translateDescription() async {
    if (_descriptionOriginal == null || 
        _descriptionOriginal == 'Keine Beschreibung verfügbar' ||
        _descriptionTranslated != null) {
      return;
    }
    
    setState(() {
      _isTranslating = true;
    });
    
    try {
      final translation = await _translator.translate(
        _descriptionOriginal!,
        from: 'en',
        to: 'de',
      );
      if (mounted) {
        setState(() {
          _descriptionTranslated = translation.text;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Translation error: $e');
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  void _toggleLanguage() {
    setState(() {
      _showGerman = !_showGerman;
    });
  }

  String get _currentDescription {
    if (_showGerman && _descriptionTranslated != null) {
      return _descriptionTranslated!;
    }
    return _descriptionOriginal ?? 'Keine Beschreibung verfügbar';
  }

  Future<void> _openCrunchyrollEpisode() async {
    try {
      final Uri url = Uri.parse(widget.release.episodeUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        if (kDebugMode) print('Cannot launch $url');
      }
    } catch (e) {
      if (kDebugMode) print('Error opening URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: MediaQuery.of(context).size.width * 0.95,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    if (release.imageUrl != null && release.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: release.imageUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 220,
                          color: Colors.grey.shade300,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) =>
                            Container(height: 220, color: Colors.grey.shade300),
                      )
                    else
                      Container(height: 220, color: Colors.grey.shade300),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 20,
                        child: _isLoadingFavorite
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                                  color: _isFavorite ? Colors.red : Colors.white,
                                  size: 20,
                                ),
                                onPressed: _toggleFavorite,
                                padding: EdgeInsets.zero,
                              ),
                      ),
                    ),
                      if (widget.watchlistService != null)
                        Positioned(
                          top: 8,
                          left: 56,
                          child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              radius: 20,
                              child: _isProcessingWatchlist
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        _isInWatchlist ? Icons.playlist_add_check : Icons.playlist_add,
                                        color: _isInWatchlist ? Colors.green : Colors.white,
                                        size: 20,
                                      ),
                                    onPressed: () async {
                                      final ws = widget.watchlistService!;
                                      setState(() {
                                        _isProcessingWatchlist = true;
                                      });
                                      final id = widget.release.seriesUrl;
                                      final exists = ws.watchlist.entries.any((e) => e.animeId == id);
                                      if (exists) {
                                        ws.watchlist.removeEntry(id);
                                        await ws.saveWatchlist();
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.release.title} aus Watchlist entfernt')),
                                        );
                                      } else {
                                        // Fast add: use cache-only lookup (no network) so UI is snappy
                                        int parsedCurrent = int.tryParse(widget.release.episodeNumber) ?? 0;
                                        int? knownMax = _knownMaxEpisode;
                                        if (knownMax == null) {
                                          knownMax = await widget.crunchyrollService.getMaxEpisodeFromCache(id, widget.release.title);
                                        }
                                        final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;

                                        final entry = WatchlistEntry(
                                          animeId: id,
                                          title: widget.release.title,
                                          imageUrl: widget.release.imageUrl,
                                          episodesWatched: 0,
                                          totalEpisodes: total,
                                        );
                                        ws.watchlist.addEntry(entry);
                                        await ws.saveWatchlist();
                                        // Schedule a background check (may perform network) to update the entry later
                                        widget.crunchyrollService.scheduleWatchlistEntryUpdate(ws, entry);
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.release.title} zur Watchlist hinzugefügt')),
                                        );
                                      }
                                      if (mounted) {
                                        setState(() {
                                          _isProcessingWatchlist = false;
                                          _isInWatchlist = !exists;
                                        });
                                      }
                                    },
                                    padding: EdgeInsets.zero,
                                  ),
                          ),
                        ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 18,
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (release.isPremiere)
                      Positioned(
                        top: 16,
                        left: 66,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
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
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        release.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              release.episodeInfo,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  release.timeString,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Handlung:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (!_isLoadingDescription && _descriptionOriginal != 'Keine Beschreibung verfügbar' && _autoTranslateEnabled)
                            TextButton.icon(
                              onPressed: _isTranslating ? null : _toggleLanguage,
                              icon: Icon(
                                Icons.translate,
                                size: 18,
                                color: _isTranslating ? Colors.grey : Theme.of(context).colorScheme.primary,
                              ),
                              label: Text(
                                _showGerman ? 'EN' : 'DE',
                                style: TextStyle(
                                  color: _isTranslating ? Colors.grey : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: Size.zero,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_isLoadingDescription)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_isTranslating && _showGerman)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Übersetze...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          _currentDescription,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openCrunchyrollEpisode,
                          icon: const Icon(Icons.play_circle),
                          label: const Text('Auf Crunchyroll ansehen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.primary.computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
