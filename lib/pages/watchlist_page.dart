import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/anime_release.dart';
import '../services/crunchyroll_service.dart';
import '../repositories/notification_repository.dart';
import '../widgets/anime_details_dialog.dart';
import '../models/watchlist.dart';
import '../services/watchlist_service.dart';
import '../services/app_settings_service.dart';
import '../utils/ui_utils.dart';

import '../models/anime_metadata.dart';
import '../services/anilist_service.dart';
import '../services/next_episode_predictor.dart';
import '../services/external_search_service.dart';

// Sorting modes for the watchlist
enum SortMode { addedAtDesc, alphabet, status }

class WatchlistPage extends StatefulWidget {
  final WatchlistService service;
  const WatchlistPage({super.key, required this.service});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  late Watchlist watchlist;
  late List<WatchlistEntry> _displayEntries;
  SortMode _sortMode = SortMode.addedAtDesc;
  bool _fabVisible = true;
  late ScrollController _scrollController;

  final TextEditingController _searchController = TextEditingController();
  bool _isLocalSearching = false;

  Future<int?> _promptForEpisodeNumber(
    BuildContext ctx,
    String title,
    int initial,
  ) async {
    final controller = TextEditingController(text: initial.toString());
    return await showDialog<int?>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Folgenanzahl'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, null),
            child: Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(dCtx, v ?? initial);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    watchlist = widget.service.watchlist;
    watchlist.addListener(_onWatchlistChanged);
    _displayEntries = List.from(watchlist.entries);

    _searchController.addListener(() {
      setState(() {
        _applySort();
      });
    });

    // Load watchlist and refresh totals asynchronously
    _initAsync();
    // Load saved sort mode then apply
    AppSettingsService.getWatchlistSortModeIndex()
        .then((idx) {
          if (!mounted) {
            return;
          }
          setState(() {
            _sortMode = SortMode.values.elementAt(
              idx.clamp(0, SortMode.values.length - 1),
            );
            _applySort();
          });
        })
        .catchError((e) {
          if (kDebugMode) {
            print('Failed to load saved watchlist sort mode: $e');
          }
          _applySort();
        });
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      try {
        final dirStr = _scrollController.position.userScrollDirection
            .toString();
        if (dirStr.contains('reverse') && _fabVisible) {
          setState(() => _fabVisible = false);
        } else if (dirStr.contains('forward') && !_fabVisible) {
          setState(() => _fabVisible = true);
        }
      } catch (e) {
        if (kDebugMode) print('ScrollController listener error: $e');
      }
    });
  }

  Future<void> _initAsync() async {
    try {
      await widget.service.loadWatchlist();
      if (!mounted) {
        return;
      }
      setState(() {
        _displayEntries = List.from(watchlist.entries);
        _applySort();
      });

      // Try to sync totals from cached releases and update watchlist
      final crunch = CrunchyrollService();
      final notifRepo = NotificationRepository();
      // Ensure cache loaded then sync
      await crunch.loadCacheOnStartup();
      await crunch.syncWatchlistWithReleases(widget.service, notifRepo);

      if (!mounted) {
        return;
      }
      setState(() {
        _displayEntries = List.from(watchlist.entries);
        _applySort();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error updating watchlist totals: $e');
      }
    }
  }

  void _openDetailsDialog(WatchlistEntry entry) {
    final release = AnimeRelease(
      title: entry.title,
      episodeNumber: entry.episodesWatched.toString(),
      episodeTitle: '',
      releaseTime: DateTime.now(),
      imageUrl: entry.imageUrl,
      description: null,
      seriesUrl: entry.animeId,
      episodeUrl: '',
      isPremiere: false,
    );

    showDialog(
      context: context,
      builder: (ctx) => AnimeDetailsDialog(
        release: release,
        crunchyrollService: CrunchyrollService(),
        watchlistService: widget.service,
        totalEpisodes: entry.totalEpisodes,
        showTimeBadge: false,
        showEpisodeBadge: false,
        showManualLink: _isCrunchyrollItem(entry),
        isCrunchyroll: _isCrunchyrollItem(entry),
      ),
    );
  }

  @override
  void dispose() {
    // Guard against LateInitializationError in case initState didn't complete
    try {
      watchlist.removeListener(_onWatchlistChanged);
    } catch (e) {
      if (kDebugMode) {
        print('Dispose: watchlist not initialized: $e');
      }
    }

    try {
      _scrollController.dispose();
    } catch (e) {
      if (kDebugMode) {
        print('Dispose: _scrollController not initialized: $e');
      }
    }

    super.dispose();
  }

  void _onWatchlistChanged() {
    _displayEntries = List.from(watchlist.entries);
    _applySort();
    setState(() {});
  }

  String _statusLabel(WatchStatus s) {
    switch (s) {
      case WatchStatus.watching:
        return 'Am Schauen';
      case WatchStatus.completed:
        return 'Abgeschlossen';
      case WatchStatus.paused:
        return 'Pausiert';
      case WatchStatus.dropped:
        return 'Abgebrochen';
    }
  }

  void _applySort() {
    List<WatchlistEntry> temp = List.from(watchlist.entries);

    // Filter by search text
    if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      temp = temp.where((e) => e.title.toLowerCase().contains(q)).toList();
    }

    if (_sortMode == SortMode.addedAtDesc) {
      temp.sort((a, b) {
        final da = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da); // newest first
      });
    } else if (_sortMode == SortMode.alphabet) {
      temp.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } else if (_sortMode == SortMode.status) {
      temp.sort((a, b) => a.status.index.compareTo(b.status.index));
    }
    _displayEntries = temp;
  }

  String _formatAddedAt(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final date = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Hinzugefügt: heute';
    if (date == yesterday) return 'Hinzugefügt: gestern';
    return 'Hinzugefügt: ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  bool _isCrunchyrollItem(WatchlistEntry entry) {
    if (entry.isCrunchyroll == true) return true;

    // Ignore fallback deep link
    if (entry.animeId == 'crunchyroll://') return false;

    // Check for actual Crunchyroll URLs
    if (entry.animeId.contains('crunchyroll.com')) return true;

    // Check for Crunchyroll series paths (e.g., /series/...)
    if (entry.animeId.contains('/') &&
        entry.animeId.toLowerCase().contains('crunchyroll')) {
      return true;
    }

    return false;
  }

  void _addAnime() async {
    // Search Dialog
    final searchController = TextEditingController();
    List<AnimeMetadata> searchResults = [];
    bool isSearching = false;
    bool hasSearched = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> performSearch() async {
            if (searchController.text.trim().isEmpty) return;

            setState(() {
              isSearching = true;
              hasSearched = true;
              searchResults = [];
            });

            try {
              final results = await AnilistService().searchSeries(
                searchController.text,
              );
              if (context.mounted) {
                setState(() {
                  searchResults = results;
                  isSearching = false;
                });
              }
            } catch (e) {
              if (kDebugMode) {
                print('Search error: $e');
              }
              if (context.mounted) {
                setState(() {
                  isSearching = false;
                });
              }
            }
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 24.0,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Anime hinzufügen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Titel suchen (Anilist/MAL/Kitsu)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: performSearch,
                      ),
                    ),
                    onSubmitted: (_) => performSearch(),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  if (isSearching)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (hasSearched && searchResults.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('Keine Ergebnisse gefunden.'),
                      ),
                    )
                  else if (searchResults.isNotEmpty)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final meta = searchResults[index];
                          // Format subtitle info
                          final parts = <String>[];
                          if (meta.totalEpisodes != null) {
                            parts.add('${meta.totalEpisodes} Folgen');
                          }
                          if (meta.startDate != null) {
                            parts.add('${meta.startDate!.year}');
                          }
                          if (meta.status != null) {
                            parts.add(meta.status!);
                          }

                          return ListTile(
                            leading: meta.imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: meta.imageUrl!,
                                      width: 50,
                                      height: 75,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[300]),
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.broken_image),
                                    ),
                                  )
                                : Container(
                                    width: 50,
                                    height: 75,
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.movie),
                                  ),
                            title: Text(
                              meta.siteUrl ?? 'Unbekannter Titel',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(parts.join(' • ')),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: Theme.of(context).primaryColor,
                              onPressed: () async {
                                AnimeMetadata itemToAdd = meta;
                                try {
                                  // ALWAYS use AniList for Crunchyroll URLs as requested
                                  final anilist = AnilistService();
                                  if (meta.id != null) {
                                    UIUtils.showSnackBar(
                                      context,
                                      const SnackBar(
                                        content: Text(
                                          'Suche Crunchyroll Link via AniList...',
                                        ),
                                        duration: Duration(milliseconds: 1000),
                                      ),
                                    );
                                    String? crUrl = await anilist
                                        .getCrunchyrollUrl(meta.id!);

                                    // Only mark as Crunchyroll if we found a real URL
                                    final bool foundRealCrunchyrollUrl =
                                        crUrl != null &&
                                        crUrl.contains('crunchyroll.com');

                                    // Deep link fallback if no specific URL found
                                    crUrl ??= 'crunchyroll://';

                                    itemToAdd = meta.copyWith(
                                      hasCrunchyroll: foundRealCrunchyrollUrl,
                                      bannerImage:
                                          crUrl, // Use bannerImage as a carrier for the deep link
                                    );
                                  }
                                } catch (_) {}

                                if (context.mounted) {
                                  _addEntryFromSearch(itemToAdd);
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Schließen'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyFoundUrl(
    BuildContext context,
    String url,
    void Function(String) onAccept,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crunchyroll Link gefunden!'),
        content: Text('Soll der Link übernommen werden?\n\n$url'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nein'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      onAccept(url);
      if (context.mounted) {
        UIUtils.showSnackBar(
          context,
          const SnackBar(content: Text('Link wurde übernommen.')),
        );
      }
    }
  }

  void _addEntryFromSearch(AnimeMetadata meta) async {
    // Determine ID. If it's a number (Anilist/Kitsu ID), convert to string.
    // Ensure we don't accidentally treat it as a URL/path if it's just an ID,
    // BUT we need a unique ID.
    // For non-Crunchyroll items, the ID format matters less, but we want to avoid the "Crunchyroll" banner.
    // Kitsu IDs are numbers, Anilist IDs are numbers.

    // Determine ID.
    // If bannerImage contains a Crunchyroll URL, use IT as the ID!
    String id;
    if (meta.bannerImage != null &&
        meta.bannerImage!.contains('crunchyroll.com')) {
      id = meta.bannerImage!;
    } else {
      id =
          meta.id?.toString() ??
          meta.siteUrl ??
          DateTime.now().millisecondsSinceEpoch.toString();
    }

    final title = meta.siteUrl ?? 'Unbekannter Titel';

    // Restore title if search stored it in siteUrl but we just overwrote it with a link?
    // Wait, the search result 'siteUrl' was holding the display title (e.g. "One Piece").
    // But in the previous step, I overwrote 'siteUrl' with the CR Link.
    // So 'title' logic above is tricky.
    // Let's rely on the fact that if I passed a CR Link in siteUrl, I probably LOST the display title from siteUrl field.
    // I should check if I lost the title.
    // Actually, Jikan results use `siteUrl` for DISPLAY TITLE in the ListView.
    // But `itemToAdd` is a copy.
    // I need to preserve the title.
    // Let's pass the Title explicitly or assume the entry creation uses `meta.title`?
    // AnimeMetadata structure: siteUrl was used for Title in search UI.

    // Check availability in list
    if (watchlist.entries.any((e) => e.animeId == id || e.title == title)) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(content: Text('"$title" ist bereits in der Liste!')),
        );
      }
      return;
    }

    // Attempt to parse episode count
    int totalEpisodes = 0;
    if (meta.totalEpisodes != null) {
      totalEpisodes = meta.totalEpisodes!;
    }

    final entry = WatchlistEntry(
      animeId: id,
      title: title,
      imageUrl: meta.imageUrl,
      episodesWatched: 0,
      totalEpisodes: totalEpisodes,
      status: WatchStatus.watching,
      addedAt: DateTime.now(),
      anilistId: meta.id, // Store Anilist/MAL ID for metadata lookups
      notificationsEnabled: false,
      isCrunchyroll:
          (meta.hasCrunchyroll == true) ||
          (meta.siteUrl?.contains('crunchyroll.com') == true) ||
          (meta.bannerImage?.contains('crunchyroll.com') == true),
    );

    // Auto-fetch status if possible
    if (meta.status != null) {
      entry.airingStatus = meta.status;
    }

    // Set initial sorting for new item effectively at top
    watchlist.addEntry(entry);
    await widget.service.saveWatchlist();

    // Immediate metadata sync & auto-deactivation for the new entry
    unawaited(widget.service.refreshMetadataWithFallback(entry));

    if (mounted) {
      setState(() {
        _displayEntries = List.from(watchlist.entries);
        _applySort();
      });
      UIUtils.showSnackBar(
        context,
        SnackBar(content: Text('"$title" zur Watchlist hinzugefügt')),
      );
    }
  }

  Future<void> _toggleNotifications(WatchlistEntry entry, bool enabled) async {
    // Optimistic update
    final old = entry.notificationsEnabled;
    entry.notificationsEnabled = enabled;
    try {
      await widget.service.saveWatchlist();
      if (mounted) setState(() {});

      // One-time lookup when enabling
      if (enabled) {
        if (mounted) {
          UIUtils.hideCurrentSnackBar(context);
          UIUtils.showSnackBar(
            context,
            const SnackBar(
              content: Text('Benachrichtigung aktiviert. Suche Sendedatum...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        try {
          final cs = CrunchyrollService();
          final predictor = NextEpisodePredictor(cs, AnilistService());
          final predicted = await predictor.predictNextForSeries(
            entry.animeId,
            entry.title,
            anilistId: entry.anilistId,
          );

          if (mounted && predicted != null) {
            final d = predicted.releaseTime;
            final dateStr =
                '${d.day}.${d.month}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            UIUtils.hideCurrentSnackBar(context);
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text(
                  'Benachrichtigung aktiviert. Nächste Folge: $dateStr',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else if (mounted) {
            UIUtils.hideCurrentSnackBar(context);
            UIUtils.showSnackBar(
              context,
              const SnackBar(
                content: Text(
                  'Benachrichtigung aktiviert. Kein genaues Datum gefunden.',
                ),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error looking up date in toggle: $e');
          }
        }
      } else {
        if (mounted) {
          UIUtils.hideCurrentSnackBar(context);
          UIUtils.showSnackBar(
            context,
            const SnackBar(content: Text('Benachrichtigung deaktiviert')),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error toggling watchlist notifications: $e');
      }
      entry.notificationsEnabled = old;
      if (mounted) setState(() {});
    }
  }

  Future<void> _showEditDialog(WatchlistEntry entry) async {
    int episodes = entry.episodesWatched;
    int total = entry.totalEpisodes;
    bool autoSync = entry.autoSyncTotal;
    final noteController = TextEditingController(text: entry.note ?? '');
    WatchStatus status = entry.status;
    String currentId = entry.animeId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          scrollable: true,
          title: Text('Bearbeiten: ${entry.title}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Gesehene Folgen')),
                  IconButton(
                    onPressed: () {
                      if (episodes > 0) setState(() => episodes--);
                    },
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(
                        ctx,
                        'Gesehene Folgen eingeben',
                        episodes,
                      );
                      if (v != null) setState(() => episodes = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Text('$episodes', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => episodes++),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('Gesamtfolgen')),
                  IconButton(
                    onPressed: () {
                      if (total > 0) {
                        setState(() {
                          total--;
                          autoSync = false;
                        });
                      }
                    },
                    icon: Icon(Icons.remove_circle_outline),
                  ),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(
                        ctx,
                        'Gesamtfolgen eingeben',
                        total,
                      );
                      if (v != null) {
                        setState(() {
                          total = v;
                          autoSync = false;
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Text('$total', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      total++;
                      autoSync = false;
                    }),
                    icon: Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Automatisch Gesamtfolgen abgleichen')),
                  StatefulBuilder(
                    builder: (ctx2, setState2) => Switch(
                      value: autoSync,
                      onChanged: (v) async {
                        // Update local toggle immediately
                        setState(() {
                          autoSync = v;
                        });

                        if (v) {
                          try {
                            final crunch = CrunchyrollService();
                            final known = await crunch.getMaxEpisodeForSeries(
                              entry.animeId,
                              entry.title,
                            );
                            if (known != null && known > total) {
                              if (mounted) setState(() => total = known);
                            }
                          } catch (e) {
                            if (kDebugMode) {
                              print('Error fetching max episode on toggle: $e');
                            }
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              DropdownButton<WatchStatus>(
                value: status,
                items: WatchStatus.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(_statusLabel(s)),
                      ),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) {
                    setState(() => status = s);
                  }
                },
              ),
              TextField(
                controller: noteController,
                decoration: InputDecoration(labelText: 'Notiz'),
              ),
              const SizedBox(height: 16),
              if (!currentId.contains('crunchyroll.com'))
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (entry.anilistId != null) {
                        UIUtils.showSnackBar(
                          context,
                          const SnackBar(
                            content: Text(
                              'Suche Crunchyroll Link via AniList...',
                            ),
                          ),
                        );
                        final url = await AnilistService().getCrunchyrollUrl(
                          entry.anilistId!,
                        );
                        if (url != null) {
                          if (!mounted) return;
                          // ... handle found URL as before
                          _applyFoundUrl(context, url, (newUrl) {
                            setState(() => currentId = newUrl);
                          });
                          return;
                        }
                      }

                      // Fallback to title search if no ID or no link found by ID
                      final match = await AnilistService().findBestMatch(
                        entry.title,
                      );
                      if (match != null &&
                          match.hasCrunchyroll == true &&
                          match.bannerImage != null) {
                        if (mounted) {
                          _applyFoundUrl(context, match.bannerImage!, (newUrl) {
                            setState(() => currentId = newUrl);
                          });
                        }
                        return;
                      }

                      final externalSearch = ExternalSearchService();
                      final url = await externalSearch.findCrunchyrollUrl(
                        entry.title,
                      );
                      if (url != null) {
                        if (mounted) {
                          _applyFoundUrl(context, url, (newUrl) {
                            setState(() {
                              currentId = newUrl;
                            });
                          });
                        }
                      } else {
                        if (mounted) {
                          UIUtils.showSnackBar(
                            context,
                            const SnackBar(
                              content: Text('Kein Link automatisch gefunden.'),
                            ),
                          );
                          // Open manual search
                          final manualUrl = externalSearch.getManualSearchUrl(
                            entry.title,
                          );
                          final uri = Uri.parse(manualUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Crunchyroll Link suchen'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                bool finalNotifications = entry.notificationsEnabled;
                bool finalPredictions = entry.predictionsEnabled;

                if (status != WatchStatus.watching) {
                  finalNotifications = false;
                  finalPredictions = false;
                  // Clean up predictions from calendar if status changed to inactive
                  final cs = CrunchyrollService();
                  cs.removePredictedReleasesForSeries(
                    entry.animeId,
                    entry.title,
                  );
                }

                final newEntry = WatchlistEntry(
                  animeId: currentId,
                  title: entry.title,
                  imageUrl: entry.imageUrl,
                  episodesWatched: episodes,
                  totalEpisodes: total,
                  status: status,
                  notificationsEnabled: finalNotifications,
                  autoSyncTotal: autoSync,
                  note: noteController.text,
                  rating: entry.rating,
                  anilistId: entry.anilistId,
                  addedAt: entry.addedAt,
                  predictionsEnabled: finalPredictions,
                );
                watchlist.updateEntry(newEntry);
                widget.service.saveWatchlist();

                // If status is watching, trigger an immediate sync to re-evaluate deactivation logic
                if (newEntry.status == WatchStatus.watching) {
                  unawaited(
                    widget.service.refreshMetadataWithFallback(newEntry),
                  );
                }

                Navigator.pop(ctx);
              },
              child: Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportJson() async {
    if (watchlist.entries.isEmpty) {
      UIUtils.showSnackBar(
        context,
        const SnackBar(
          content: Text('⚠️ Keine Einträge zum Exportieren'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final jsonString = await widget.service.exportToJson();

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final suggestedFileName = 'crunchyroll_watchlist_$timestamp.json';
      final bytes = utf8.encode(jsonString);

      String? chosenPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Watchlist exportieren',
        fileName: suggestedFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (chosenPath == null) return; // user cancelled

      // On some platforms (Android), saveFile might return a path that needs cleanup
      if (chosenPath.startsWith('file://')) {
        chosenPath = Uri.parse(chosenPath).toFilePath();
      }

      // Manually write the bytes at the path to ensure it is saved on Windows
      final file = File(chosenPath);
      await file.writeAsBytes(bytes);

      // Get the actual filename and directory from the chosen path
      final actualFileName = file.path
          .split(Platform.isWindows ? '\\' : '/')
          .last;
      final actualPath = file.parent.path;

      if (mounted) {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            icon: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Export erfolgreich'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${watchlist.entries.length} Einträge wurden erfolgreich exportiert.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Speicherort:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    actualPath,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dateiname:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  actualFileName,
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'close'),
                child: const Text('Schließen'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'share'),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Teilen'),
              ),
            ],
          ),
        );

        if (result == 'share') {
          try {
            // Slight delay to ensure file system has flushed the file
            await Future.delayed(const Duration(milliseconds: 300));

            if (await file.exists()) {
              await Share.shareXFiles(
                [XFile(file.path)],
                subject: 'Meine Crunchyroll Watchlist',
                text: 'Schau dir meine Crunchyroll Watchlist an!',
              );
            } else {
              throw Exception('Datei nicht gefunden unter: ${file.path}');
            }
          } catch (e) {
            if (kDebugMode) {
              print('Share error: $e');
            }
            if (mounted) {
              UIUtils.showSnackBar(
                context,
                SnackBar(content: Text('❌ Fehler beim Teilen: $e')),
              );
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Export error: $e');
      }
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('❌ Fehler beim Exportieren: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Watchlist-Datei auswählen',
      );

      if (result == null || result.files.isEmpty) return; // cancelled

      final filePath = result.files.single.path;
      if (filePath == null) throw Exception('Kein Dateipfad erhalten');

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Importiere Watchlist...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final importedCount = await widget.service.importFromJsonFilePath(
        filePath,
      );

      if (mounted) Navigator.pop(context); // close loading

      if (importedCount > 0) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Import erfolgreich'),
                ],
              ),
              content: Text(
                importedCount == 1
                    ? '1 neuer Eintrag wurde importiert'
                    : '$importedCount neue Einträge wurden importiert',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Keine neuen Einträge'),
                ],
              ),
              content: const Text(
                'Die Datei wurde eingelesen, jedoch wurden keine neuen Einträge hinzugefügt.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // close loading dialog if open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (kDebugMode) {
        print('Import error: $e');
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Import fehlgeschlagen'),
              ],
            ),
            content: Text(
              'Fehler beim Importieren:\n\n$e',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isLocalSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Suchen...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
              )
            : const Text('Watchlist'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_isLocalSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isLocalSearching = false;
                  _searchController.clear();
                  // Listener will trigger _applySort
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isLocalSearching = true;
                });
              },
            ),
          if (!_isLocalSearching)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Händisch hinzufügen',
              onPressed: _addAnime,
            ),
          // AniList forecast removed — calendar icon intentionally omitted
          // Sort button
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sortieren',
            onSelected: (m) {
              setState(() {
                _sortMode = m;
                _displayEntries = List.from(watchlist.entries);
                _applySort();
              });
              // persist selection
              AppSettingsService.setWatchlistSortModeIndex(m.index).catchError((
                e,
              ) {
                if (kDebugMode) {
                  print('Failed to save watchlist sort mode: $e');
                }
              });
            },
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem(
                value: SortMode.addedAtDesc,
                checked: _sortMode == SortMode.addedAtDesc,
                child: Text('Datum: zuletzt hinzugefügt'),
              ),
              CheckedPopupMenuItem(
                value: SortMode.alphabet,
                checked: _sortMode == SortMode.alphabet,
                child: Text('Alphabet'),
              ),
              CheckedPopupMenuItem(
                value: SortMode.status,
                checked: _sortMode == SortMode.status,
                child: Text('Status'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Optionen',
            onSelected: (value) {
              if (value == 'export') {
                _exportJson();
              } else if (value == 'import') {
                _importJson();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 12),
                    Text('Exportieren'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 12),
                    Text('Importieren'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: _displayEntries.length,
        itemBuilder: (ctx, i) {
          final entry = _displayEntries[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            clipBehavior: Clip.antiAlias,
            elevation: 2,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Column: Cover Image + Action Icons
                  SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        // Cover Image (Tappable)
                        InkWell(
                          onTap: () => _openDetailsDialog(entry),
                          child: _buildCoverImage(entry),
                        ),
                        // Action Icons (Expanded to properly center/align in remaining space)
                        Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (entry.status == WatchStatus.watching &&
                                    (CrunchyrollService().isTitleInCalendar(
                                          entry.title,
                                        ) ||
                                        (entry.airingStatus?.toUpperCase() !=
                                                'FINISHED' &&
                                            entry.airingStatus?.toUpperCase() !=
                                                'CANCELLED')))
                                  IconButton(
                                    icon: Icon(
                                      entry.notificationsEnabled
                                          ? Icons.notifications_active
                                          : Icons.notifications_off,
                                      color: entry.notificationsEnabled
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: entry.notificationsEnabled
                                        ? 'Push deaktivieren'
                                        : 'Push aktivieren',
                                    onPressed: () => _toggleNotifications(
                                      entry,
                                      !entry.notificationsEnabled,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Bearbeiten',
                                  onPressed: () => _showEditDialog(entry),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                ),
                                if (entry.status == WatchStatus.watching &&
                                    CrunchyrollService().isTitleInCalendar(
                                      entry.title,
                                    ))
                                  IconButton(
                                    icon: Icon(
                                      entry.predictionsEnabled
                                          ? Icons.auto_awesome
                                          : Icons.auto_awesome_outlined,
                                      color: entry.predictionsEnabled
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    tooltip: entry.predictionsEnabled
                                        ? 'Vorhersage deaktivieren'
                                        : 'Vorhersage aktivieren',
                                    onPressed: () async {
                                      final wasEnabled =
                                          entry.predictionsEnabled;
                                      setState(() {
                                        entry.predictionsEnabled = !wasEnabled;
                                      });
                                      widget.service.watchlist.updateEntry(
                                        entry,
                                      );
                                      await widget.service.saveWatchlist();
                                      final cs = CrunchyrollService();

                                      if (wasEnabled) {
                                        await cs
                                            .removePredictedReleasesForSeries(
                                              entry.animeId,
                                              entry.title,
                                            );
                                        if (context.mounted) {
                                          UIUtils.showSnackBar(
                                            context,
                                            const SnackBar(
                                              content: Text(
                                                'Vorhersage deaktiviert',
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        if (context.mounted) {
                                          UIUtils.showSnackBar(
                                            context,
                                            const SnackBar(
                                              content: Text(
                                                'Suche nach Sendetermin...',
                                              ),
                                              duration: Duration(seconds: 1),
                                            ),
                                          );
                                        }
                                        try {
                                          final predictor =
                                              NextEpisodePredictor(
                                                cs,
                                                AnilistService(),
                                              );
                                          final predicted = await predictor
                                              .predictNextForSeries(
                                                entry.animeId,
                                                entry.title,
                                                anilistId: entry.anilistId,
                                              );

                                          if (context.mounted) {
                                            UIUtils.hideCurrentSnackBar(
                                              context,
                                            );
                                            if (predicted != null) {
                                              final d = predicted.releaseTime;
                                              final dateStr =
                                                  '${d.day}.${d.month}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

                                              // Auto-enable general notifications if found
                                              if (!entry.notificationsEnabled) {
                                                setState(() {
                                                  entry.notificationsEnabled =
                                                      true;
                                                });
                                                widget.service.watchlist
                                                    .updateEntry(entry);
                                                await widget.service
                                                    .saveWatchlist();
                                              }

                                              if (context.mounted) {
                                                UIUtils.showSnackBar(
                                                  context,
                                                  SnackBar(
                                                    content: Text(
                                                      'Gefunden: $dateStr (Benachrichtigung aktiv)',
                                                    ),
                                                    backgroundColor:
                                                        Colors.green,
                                                    duration: const Duration(
                                                      seconds: 4,
                                                    ),
                                                  ),
                                                );
                                              }
                                            } else {
                                              if (context.mounted) {
                                                UIUtils.showSnackBar(
                                                  context,
                                                  const SnackBar(
                                                    content: Text(
                                                      'Keine bevorstehende Folge gefunden.',
                                                    ),
                                                    backgroundColor:
                                                        Colors.orange,
                                                  ),
                                                );
                                              }
                                            }
                                          }
                                        } catch (_) {
                                          if (context.mounted) {
                                            UIUtils.hideCurrentSnackBar(
                                              context,
                                            );
                                          }
                                        }
                                      }
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right Column: Details & Text
                  Expanded(
                    child: InkWell(
                      onTap: () => _showEditDialog(entry),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title & Delete Button
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      size: 20,
                                    ),
                                    tooltip: 'Entfernen',
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text(
                                            'Eintrag entfernen',
                                          ),
                                          content: Text(
                                            'Möchtest du "${entry.title}" wirklich aus der Watchlist entfernen?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Abbrechen'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
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
                                      if (confirmed == true) {
                                        watchlist.removeEntry(entry.animeId);
                                        await widget.service.saveWatchlist();
                                        final crunch = CrunchyrollService();
                                        await crunch
                                            .removePredictedReleasesForSeries(
                                              entry.animeId,
                                              entry.title,
                                            );
                                        if (context.mounted) {
                                          UIUtils.showSnackBar(
                                            context,
                                            const SnackBar(
                                              content: Text('Eintrag entfernt'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Episodes
                            Text(
                              'Folgen: ${entry.episodesWatched}/${entry.totalEpisodes}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),

                            // Status
                            const SizedBox(height: 2),
                            Text(
                              'Status: ${_statusLabel(entry.status)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),

                            // Badges: Linked & Calendar
                            if (entry.anilistId != null &&
                                _isCrunchyrollItem(entry)) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Verknüpft',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.green,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (CrunchyrollService().isTitleInCalendar(
                              entry.title,
                            )) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Im Kalender',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Note
                            if (entry.note != null &&
                                entry.note!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Notiz: ${entry.note}',
                                  maxLines: 10, // Allow more lines for notes
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],

                            // Spacer to push bottom row down
                            const SizedBox(height: 8),

                            // Bottom Row: Date only
                            if (entry.addedAt != null)
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  _formatAddedAt(entry.addedAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCoverImage(WatchlistEntry entry) {
    const double coverHeight = 160.0;
    const double coverWidth = 120.0;

    if (entry.imageUrl == null || entry.imageUrl!.isEmpty) {
      // Placeholder for missing image
      final placeholder = Container(
        width: coverWidth,
        height: coverHeight,
        color: Colors.grey.shade200,
        child: Icon(Icons.image_not_supported, color: Colors.grey.shade400),
      );

      if (_isCrunchyrollItem(entry)) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              placeholder,
              Positioned(top: 0, right: 0, child: _buildCrunchyrollBadge()),
            ],
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: placeholder,
      );
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: entry.imageUrl!,
      width: coverWidth,
      height: coverHeight,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        width: coverWidth,
        height: coverHeight,
        color: Colors.grey.shade200,
        child: Icon(Icons.image, color: Colors.grey.shade400),
      ),
      errorWidget: (context, url, error) => Container(
        width: coverWidth,
        height: coverHeight,
        color: Colors.grey.shade200,
        child: Icon(Icons.broken_image, color: Colors.grey.shade400),
      ),
    );

    if (_isCrunchyrollItem(entry)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            imageWidget,
            Positioned(top: 0, right: 0, child: _buildCrunchyrollBadge()),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageWidget,
    );
  }

  Widget _buildCrunchyrollBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.inversePrimary,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
      ),
      child: const Text(
        'Crunchyroll',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
