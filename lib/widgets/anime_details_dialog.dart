import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:translator/translator.dart';
import '../models/anime_release.dart';
import '../services/crunchyroll_service.dart';
import '../services/episode_provider_factory.dart';
import '../models/anime_metadata.dart';
import '../services/app_settings_service.dart';

import '../services/watchlist_service.dart';
import '../utils/ui_utils.dart';
import '../models/watchlist.dart';
import '../services/next_episode_predictor.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../utils/title_utils.dart';
import '../widgets/anilist_search_dialog.dart';
import 'details_description_section.dart';
import 'details_metadata_section.dart';
import 'details_watchlist_button.dart';
import 'details_header_image.dart';
import '../services/external_search_service.dart';

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
  final bool isCrunchyroll;

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
    this.isCrunchyroll = true,
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
  bool _hideTotalCount = false;

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
    AppSettingsService.getEpisodeProviderName().then((name) {
      if (mounted) {
        setState(() {
          _hideTotalCount =
              (name == 'anilist' || name == 'jikan' || name == 'crunchyroll');
        });
      }
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
    String? description = await widget.crunchyrollService.fetchDescription(
      widget.release,
    );

    // Next, attempt to enrich metadata from the selected provider (description/episodes only)
    try {
      final provider = await EpisodeProviderFactory.getProvider();
      final meta = await provider.fetchSeriesMetadata(
        widget.release.seriesUrl,
        widget.release.title,
      );
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
        final kitImage = await widget.crunchyrollService.fetchImageForTitle(
          widget.release.title,
        );
        if (kitImage.isNotEmpty) {
          widget.release.imageUrl = kitImage;
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error fetching cover from Kitsu for popup: $e');
    }

    if (mounted) {
      setState(() {
        _descriptionOriginal = description;
        _isLoadingDescription = false;
      });
      final autoTranslate = await AppSettingsService.getAutoTranslate();
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
      // 1. Check if we already have a direct URL
      String? urlString = widget.release.episodeUrl.isNotEmpty
          ? widget.release.episodeUrl
          : (widget.release.seriesUrl.isNotEmpty &&
                    widget.release.seriesUrl.startsWith('http')
                ? widget.release.seriesUrl
                : null);

      // 2. If missing, try ExternalSearchService (programmatic search)
      if (urlString == null) {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(
              content: Text('Suche Crunchyroll URL...'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        final externalSearch = ExternalSearchService();
        urlString = await externalSearch.findCrunchyrollUrl(
          widget.release.title,
        );
      }

      // 3. Fallback: If still missing, offer manual search or use dummy link
      if (urlString == null) {
        final manualUrl = ExternalSearchService().getManualSearchUrl(
          widget.release.title,
        );

        if (mounted) {
          final result = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Streaming-Link nicht gefunden'),
              content: const Text(
                'Wir konnten keinen direkten Link zu Crunchyroll finden. Möchtest du danach suchen?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Suchen'),
                ),
              ],
            ),
          );

          if (result == true) {
            final uri = Uri.parse(manualUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return;
            }
          }
        }

        // Final fallback: Dummy link to trigger App
        final slug = Uri.encodeComponent(
          widget.release.title.replaceAll(' ', '-').toLowerCase(),
        );
        urlString = 'https://www.crunchyroll.com/de/series/G-FORCE-APP/$slug';
      }

      final Uri? url = Uri.tryParse(urlString);
      if (url == null) {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(content: Text('Ungültige URL')),
          );
        }
        return;
      }

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.of(context).pop();
      } else {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(content: Text('URL kann nicht geöffnet werden')),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error opening URL: $e');
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          const SnackBar(content: Text('Fehler beim Öffnen der URL')),
        );
      }
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
                DetailsHeaderImage(
                  imageUrl: release.imageUrl,
                  isPremiere: release.isPremiere,
                  isPredicted: release.isPredicted,
                  onClose: () => Navigator.of(context).pop(),
                  watchlistButton: release.isPredicted
                      ? null
                      : DetailsWatchlistButton(
                          isInWatchlist: _isInWatchlist,
                          isProcessing: _isProcessingWatchlist,
                          onTap: _handleWatchlistToggle,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DetailsMetadataSection(
                        title: release.title,
                        episodeInfo: release.episodeInfo,
                        knownMaxEpisode: _knownMaxEpisode,
                        timeString: release.timeString,
                        showEpisodeBadge: widget.showEpisodeBadge,
                        showTimeBadge: widget.showTimeBadge,
                        hideTotalCount: _hideTotalCount,
                      ),
                      const SizedBox(height: 16),
                      DetailsDescriptionSection(
                        description: _currentDescription,
                        isLoading: _isLoadingDescription,
                        isTranslating: _isTranslating,
                        showGerman: _showGerman,
                        autoTranslateEnabled: _autoTranslateEnabled,
                        onToggleLanguage: _toggleLanguage,
                      ),
                      const SizedBox(height: 8),
                      if (widget.showManualLink) _buildManualLinkButton(),
                      const SizedBox(height: 20),
                      if (!release.isPredicted && widget.isCrunchyroll)
                        _buildCrunchyrollPlayButton(),
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

  Widget _buildManualLinkButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _handleManualLink,
        icon: const Icon(Icons.link),
        label: const Text('Manuelle AniList Verknüpfung'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildCrunchyrollPlayButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openCrunchyrollEpisode,
        icon: const Icon(Icons.play_circle),
        label: const Text('Auf Crunchyroll ansehen'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor:
              Theme.of(context).colorScheme.primary.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Future<void> _handleWatchlistToggle() async {
    final ws = widget.watchlistService;
    if (ws == null) return;
    setState(() {
      _isProcessingWatchlist = true;
    });
    try {
      final id = widget.release.seriesUrl;
      final exists = ws.watchlist.entries.any((e) => e.animeId == id);
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
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Entfernen',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          ws.watchlist.removeEntry(id);
          await ws.saveWatchlist();
          await widget.crunchyrollService.removePredictedReleasesForSeries(
            id,
            widget.release.title,
          );
          if (mounted) {
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text('${widget.release.title} aus Watchlist entfernt'),
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
        int parsedCurrent = int.tryParse(widget.release.episodeNumber) ?? 0;
        int? knownMax = _knownMaxEpisode;
        if (knownMax == null) {
          knownMax = await widget.crunchyrollService.getMaxEpisodeFromCache(
            id,
            widget.release.title,
          );
        }
        final total = (knownMax != null && knownMax > parsedCurrent)
            ? knownMax
            : parsedCurrent;

        int? autoId;
        try {
          final best = await AnilistService().findBestMatch(
            widget.release.title,
          );
          if (best != null) {
            autoId = best.id;
            final cache = AnilistCache();
            final key = normalizeTitle(widget.release.seriesUrl);
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
            final predictionsEnabled =
                await AppSettingsService.getPredictionEnabled();
            if (predictionsEnabled) {
              Future.microtask(() async {
                try {
                  final predictor = NextEpisodePredictor(
                    widget.crunchyrollService,
                    AnilistService(),
                  );
                  await predictor.predictNextForSeries(
                    id,
                    widget.release.title,
                  );
                } catch (_) {}
              });
            }
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
        print('❌ Error toggling watchlist from details dialog: $e');
      }
      if (mounted) {
        setState(() {
          _isProcessingWatchlist = false;
        });
      }
    }
  }

  Future<void> _handleManualLink() async {
    final currentTitle = widget.release.title;
    final seriesUrl = widget.release.seriesUrl;

    final result = await showDialog<AnimeMetadata>(
      context: context,
      builder: (_) => AnilistSearchDialog(initialQuery: currentTitle),
    );

    if (result != null && mounted) {
      final cache = AnilistCache();
      final key = normalizeTitle(seriesUrl);
      await cache.save(key, result);

      if (_isInWatchlist && widget.watchlistService != null) {
        try {
          final ws = widget.watchlistService!;
          final entryIndex = ws.watchlist.entries.indexWhere(
            (e) => e.animeId == seriesUrl,
          );
          if (entryIndex != -1) {
            final entry = ws.watchlist.entries[entryIndex];
            final oldId = entry.animeId;
            entry.anilistId = result.id;

            // NEW: Automatically update Crunchyroll URL if AniList provides one
            String? updatedUrl;
            if (result.hasCrunchyroll == true &&
                result.bannerImage != null &&
                result.bannerImage!.contains('crunchyroll.com')) {
              updatedUrl = result.bannerImage;
              if (updatedUrl != oldId) {
                ws.watchlist.renameEntry(oldId, updatedUrl!);
                if (kDebugMode)
                  print(
                    '🔗 Sync: Updated Crunchyroll URL from AniList: $updatedUrl',
                  );
              }
            }

            ws.watchlist.updateEntry(entry);
            await ws.saveWatchlist();

            if (mounted && updatedUrl != null && updatedUrl != oldId) {
              UIUtils.showSnackBar(
                context,
                SnackBar(
                  content: Text(
                    'Crunchyroll-Link wurde automatisch aktualisiert! ✅',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        } catch (e) {
          if (kDebugMode) print('❌ Link: Failed to update watchlist entry: $e');
        }
      }

      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text(
              'Verknüpft mit: ${result.siteUrl ?? "ID ${result.id}"}',
            ),
          ),
        );
        setState(() {
          _isLoadingDescription = true;
        });
        _loadDescription();

        if (_isInWatchlist && widget.watchlistService != null) {
          try {
            final anilist = AnilistService();
            final predictor = NextEpisodePredictor(
              widget.crunchyrollService,
              anilist,
            );
            await predictor.predictNextForSeries(
              widget.release.seriesUrl,
              widget.release.title,
            );
          } catch (_) {}
        }
      }
    }
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
        oldWidget.watchlistService!.watchlist.removeListener(
          _onWatchlistChanged,
        );
      }
      if (widget.watchlistService != null) {
        widget.watchlistService!.watchlist.addListener(_onWatchlistChanged);
      }
      _updateWatchlistState();
      if (mounted) setState(() {});
    }
  }
}
