import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:translator/translator.dart';
import '../models/anime_release.dart';
import '../services/crunchyroll_service.dart';
import '../services/episode_provider_factory.dart';
import '../models/anime_metadata.dart';
import '../settings.dart';
 
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../services/next_episode_predictor.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../utils/title_utils.dart';
import '../widgets/anilist_search_dialog.dart';

/// Dialog Widget für Anime-Details mit asynchronem Laden der Beschreibung
class AnimeDetailsDialog extends StatefulWidget {
  final AnimeRelease release;
  final CrunchyrollService crunchyrollService;
  final int? totalEpisodes;
  final bool showEpisodeBadge;
  final bool showTimeBadge;
  final void Function(AnimeRelease release)? onAddToWatchlist;
  final WatchlistService? watchlistService;
  final bool showManualLink;

  const AnimeDetailsDialog({
    super.key,
    required this.release,
    required this.crunchyrollService,
    this.totalEpisodes,
    this.showEpisodeBadge = true,
    this.showTimeBadge = true,
    this.onAddToWatchlist,
    this.watchlistService,
    this.showManualLink = false,
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
  
  final _translator = GoogleTranslator();
  
  bool _isInWatchlist = false;
  bool _isProcessingWatchlist = false;
  int? _knownMaxEpisode;
  bool _hideTotalForAnilist = false;

  @override
  void initState() {
    super.initState();
    _loadDescription();
    // If caller provided a total episode count (e.g., from Watchlist), use it immediately
    if (widget.totalEpisodes != null) {
      _knownMaxEpisode = widget.totalEpisodes;
    } else {
      _prefetchKnownMaxEpisode();
    }
    _updateWatchlistState();
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.addListener(_onWatchlistChanged);
    }
    // Determine if AniList is selected to hide totals in badges
    AppSettings.getEpisodeProviderName().then((name) {
      if (mounted) setState(() { _hideTotalForAnilist = (name == 'anilist'); });
    });
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
    // favorite feature removed; no-op
  }

  // Favorite feature removed; no-op placeholder kept for API stability if needed.

  Future<void> _loadDescription() async {
    // First, always get the Crunchyroll description (calendar source)
    String? description = await widget.crunchyrollService.fetchDescription(widget.release);

    // Next, attempt to enrich metadata from the selected provider (description/episodes only)
    try {
      final provider = await EpisodeProviderFactory.getProvider();
      final meta = await provider.fetchSeriesMetadata(widget.release.seriesUrl, widget.release.title);
      if (meta != null) {
        // Do NOT use provider images here; always prefer Kitsu for covers
        if (meta.description != null && meta.description!.isNotEmpty) {
          description = meta.description;
        }
        if (meta.totalEpisodes != null) {
          _knownMaxEpisode = meta.totalEpisodes;
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error enriching metadata: $e');
    }

    // Ensure we have a cover image — fetch from Kitsu only
    try {
      if (widget.release.imageUrl == null || widget.release.imageUrl!.isEmpty) {
        final kitImage = await widget.crunchyrollService.fetchImageForTitle(widget.release.title);
        if (kitImage.isNotEmpty) widget.release.imageUrl = kitImage;
      }
    } catch (e) {
      if (kDebugMode) print('Error fetching cover from Kitsu for popup: $e');
    }

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
      // Prefer episode URL, fall back to series URL when episode URL is empty
      String? urlString = (widget.release.episodeUrl != null && widget.release.episodeUrl!.isNotEmpty)
          ? widget.release.episodeUrl
          : (widget.release.seriesUrl.isNotEmpty ? widget.release.seriesUrl : null);

      if (urlString == null || urlString.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine URL verfügbar')));
        return;
      }

      final Uri? url = Uri.tryParse(urlString);
      if (url == null) {
        if (kDebugMode) print('Invalid URL: $urlString');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ungültige URL')));
        return;
      }

      if (await canLaunchUrl(url)) {
        final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!launched && kDebugMode) print('launchUrl returned false for $url');
        if (mounted) Navigator.of(context).pop();
      } else {
        if (kDebugMode) print('Cannot launch $url');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL kann nicht geöffnet werden')));
      }
    } catch (e) {
      if (kDebugMode) print('Error opening URL: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Öffnen der URL')));
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
                    if (!release.isPredicted)
                      // Favorite (heart) button on details cover (top-left)
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
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    _isInWatchlist ? Icons.favorite : Icons.favorite_border,
                                    color: _isInWatchlist ? Colors.red : Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    final ws = widget.watchlistService;
                                    if (ws == null) return;
                                    setState(() { _isProcessingWatchlist = true; });
                                    try {
                                      final id = widget.release.seriesUrl;
                                      final exists = ws.watchlist.entries.any((e) => e.animeId == id);
                                      if (exists) {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Eintrag entfernen'),
                                            content: Text('Möchtest du "${widget.release.title}" wirklich aus der Watchlist entfernen?'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
                                              TextButton(
                                                onPressed: () => Navigator.of(ctx).pop(true),
                                                child: Text('Entfernen', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          ws.watchlist.removeEntry(id);
                                          await ws.saveWatchlist();
                                          // Remove predicted releases for this series
                                          await widget.crunchyrollService.removePredictedReleasesForSeries(id, widget.release.title);
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${widget.release.title} aus Watchlist entfernt')),
                                          );
                                        } else {
                                          if (mounted) setState(() { _isProcessingWatchlist = false; });
                                          return;
                                        }
                                      } else {
                                        int parsedCurrent = int.tryParse(widget.release.episodeNumber) ?? 0;
                                        int? knownMax = _knownMaxEpisode;
                                        if (knownMax == null) {
                                          knownMax = await widget.crunchyrollService.getMaxEpisodeFromCache(id, widget.release.title);
                                        }
                                        final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;

                                        // Auto-link integration
                                        int? autoId;
                                        try {
                                          final best = await AnilistService().findBestMatch(widget.release.title);
                                          if (best != null) {
                                            autoId = best.id;
                                            if (kDebugMode) print('✅ Auto-linked "${widget.release.title}" to AniList ID: $autoId');
                                            
                                            final cache = AnilistCache();
                                            final key = normalizeTitle(widget.release.seriesUrl ?? widget.release.title);
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
                                        widget.crunchyrollService.scheduleWatchlistEntryUpdate(ws, entry);
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.release.title} zur Watchlist hinzugefügt${autoId != null ? " (Verknüpft)" : ""}')),
                                        );

                                        // Trigger prediction refresh if auto-linked
                                        if (autoId != null) {
                                          try {
                                            final predictionsEnabled = await AppSettings.getPredictionEnabled();
                                            if (predictionsEnabled) {
                                              // Run in background
                                              Future.microtask(() async {
                                                try {
                                                  final predictor = NextEpisodePredictor(widget.crunchyrollService, AnilistService());
                                                  await predictor.predictNextForSeries(id, widget.release.title);
                                                } catch (_) {}
                                              });
                                            }
                                          } catch (_) {}
                                        }
                                      }
                                      if (mounted) setState(() {
                                        _isProcessingWatchlist = false;
                                        _isInWatchlist = !exists;
                                      });
                                    } catch (e) {
                                      if (kDebugMode) print('❌ Error toggling watchlist from details dialog: $e');
                                      if (mounted) setState(() { _isProcessingWatchlist = false; });
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
                        bottom: 8,
                        right: 8,
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
                    if (release.isPredicted)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Vorhersage',
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
                          if (widget.showEpisodeBadge) ...[
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
                                _hideTotalForAnilist
                                    ? '${release.episodeInfo}'
                                    : '${release.episodeInfo}${_knownMaxEpisode != null ? ' / ${_knownMaxEpisode}' : ''}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          if (widget.showTimeBadge)
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
                      const SizedBox(height: 8),
                      // Manual AniList Link Button - Only visible if enabled (e.g. from Watchlist)
                      if (widget.showManualLink)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                                final currentTitle = widget.release.title;
                                final seriesUrl = widget.release.seriesUrl;
                                
                                // Show search dialog
                                final result = await showDialog<AnimeMetadata>(
                                  context: context, 
                                  builder: (_) => AnilistSearchDialog(initialQuery: currentTitle)
                                );
                                
                                if (result != null && mounted) {
                                  // Save the selection (cache key is based on normalized title/URL)
                                  final cache = AnilistCache();
                                  final key = normalizeTitle(seriesUrl ?? currentTitle);
                                  await cache.save(key, result);
                                  
                                  // ALSO update the WatchlistEntry if present
                                  if (_isInWatchlist && widget.watchlistService != null) {
                                    try {
                                      final ws = widget.watchlistService!;
                                      final entryIndex = ws.watchlist.entries.indexWhere((e) => e.animeId == seriesUrl);
                                      if (entryIndex != -1) {
                                        final entry = ws.watchlist.entries[entryIndex];
                                        entry.anilistId = result.id;
                                        ws.watchlist.updateEntry(entry);
                                        await ws.saveWatchlist();
                                        if (kDebugMode) print('✅ Link: Updated watchlist entry with AniList ID: ${result.id}');
                                      }
                                    } catch (e) {
                                      if (kDebugMode) print('❌ Link: Failed to update watchlist entry: $e');
                                    }
                                  }
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Verknüpft mit: ${result.siteUrl ?? "ID ${result.id}"}'))
                                    );
                                    
                                    // Trigger immediate refresh of description/metadata
                                    setState(() { _isLoadingDescription = true; });
                                    _loadDescription();
                                    
                                    // Trigger single item prediction update if in watchlist
                                    if (_isInWatchlist && widget.watchlistService != null) {
                                       try {
                                          final anilist = AnilistService();
                                          final predictor = NextEpisodePredictor(widget.crunchyrollService, anilist);
                                          await predictor.predictNextForSeries(widget.release.seriesUrl, widget.release.title); 
                                       } catch (_) {}
                                    }
                                  }
                                }
                            },
                            icon: const Icon(Icons.link),
                            label: const Text('Manuelle AniList Verknüpfung'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (!widget.release.isPredicted)
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

  void _onWatchlistChanged() {
    if (!mounted) return;
    final prev = _isInWatchlist;
    _updateWatchlistState();
    if (prev != _isInWatchlist && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.removeListener(_onWatchlistChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnimeDetailsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchlistService != widget.watchlistService) {
      if (oldWidget.watchlistService != null) {
        oldWidget.watchlistService!.watchlist.removeListener(_onWatchlistChanged);
      }
      if (widget.watchlistService != null) {
        widget.watchlistService!.watchlist.addListener(_onWatchlistChanged);
      }
      _updateWatchlistState();
      if (mounted) setState(() {});
    }
  }
}
