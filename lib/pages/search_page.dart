import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/anime_release.dart';
import '../models/notification_log.dart';
import '../models/watchlist.dart';
import '../repositories/seen_repository.dart';
import '../services/crunchyroll_service.dart';
import '../services/watchlist_service.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../services/next_episode_predictor.dart';
import '../utils/ui_utils.dart';
import '../utils/title_utils.dart';
import '../services/app_settings_service.dart';
import '../widgets/anime_details_dialog.dart';

/// Einfache In-App Suchseite für lokal geladene Releases
class SearchPage extends StatefulWidget {
  final Map<DateTime, List<AnimeRelease>> releases;
  final WatchlistService? watchlistService;

  const SearchPage({super.key, required this.releases, this.watchlistService});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];

  List<String> _history = [];
  List<String> _allSuggestions = [];
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final titles = <String>{};
    widget.releases.values.expand((l) => l).forEach((r) {
      titles.add(r.title);
      if (r.episodeTitle.isNotEmpty) titles.add(r.episodeTitle);
    });
    _allSuggestions = titles.toList()..sort();

    AppSettingsService.getSearchHistory().then((list) {
      if (mounted) {
        setState(() => _history = list);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final text = _controller.text.trim();
    _updateSuggestions(text);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text);
    });
  }

  void _updateSuggestions(String text) {
    if (text.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final q = text.toLowerCase();
    final matched = _allSuggestions
        .where((s) => s.toLowerCase().contains(q))
        .take(10)
        .toList();
    setState(() {
      _suggestions = matched;
    });
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    final q = query.toLowerCase();
    final List<Map<String, dynamic>> matches = [];

    widget.releases.forEach((date, list) {
      for (var r in list) {
        final hay = '${r.title} ${r.episodeTitle} ${r.episodeInfo}'
            .toLowerCase();
        if (hay.contains(q)) {
          matches.add({'release': r, 'date': date});
        }
      }
    });

    setState(() {
      _results = matches;
    });
  }

  void _onSuggestionTap(String suggestion) async {
    _controller.text = suggestion;
    _updateSuggestions(suggestion);
    await AppSettingsService.addToSearchHistory(suggestion);
    final list = await AppSettingsService.getSearchHistory();
    if (mounted) {
      setState(() => _history = list);
    }
    _performSearch(suggestion);
  }

  Future<void> _addToWatchlist(AnimeRelease release) async {
    if (widget.watchlistService == null) {
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

    // Auto-link integration
    int? autoId;
    try {
      final best = await AnilistService().findBestMatch(release.title);
      if (best != null) {
        autoId = best.id;
        if (kDebugMode) {
          print('✅ Auto-linked "${release.title}" to AniList ID: $autoId');
        }

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
    widget.watchlistService!.watchlist.addEntry(entry);
    await widget.watchlistService!.saveWatchlist();
    // schedule background update (may perform network)
    cs.scheduleWatchlistEntryUpdate(widget.watchlistService!, entry);
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Zur Watchlist hinzugefügt: ${release.title}${autoId != null ? " (Verknüpft)" : ""}',
          ),
        ),
      );
    }

    // Trigger prediction refresh if auto-linked
    if (autoId != null) {
      try {
        final predictor = NextEpisodePredictor(cs, AnilistService());
        await predictor.predictNextForSeries(entry.animeId, entry.title);
      } catch (_) {}
    }
  }

  Future<void> _onResultTap(AnimeRelease r, DateTime date) async {
    await AppSettingsService.addToSearchHistory(r.title);
    final list = await AppSettingsService.getSearchHistory();
    if (mounted) {
      setState(() => _history = list);
    }

    try {
      final tempLog = NotificationLog(
        favoriteTitle: r.title,
        releaseTitle: r.episodeTitle,
        episodeNumber: r.episodeNumber,
        notifyTime: DateTime.now(),
      );
      final hash = tempLog.generateContentHash();
      await SeenRepository().markSeen(hash);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error marking seen from search: $e');
      }
    }

    if (!mounted) {
      return;
    }
    await showDialog(
      context: context,
      builder: (BuildContext ctx) => AnimeDetailsDialog(
        release: r,
        crunchyrollService: CrunchyrollService(),
        onAddToWatchlist: (release) {
          _addToWatchlist(release);
          Navigator.of(ctx).pop();
        },
        watchlistService: widget.watchlistService,
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return const Center(child: Text('Keine letzten Suchanfragen'));
    }
    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = _history[index];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(s),
          onTap: () => _onSuggestionTap(s),
        );
      },
    );
  }

  Widget _buildSuggestionList() {
    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = _suggestions[index];
        return ListTile(
          leading: const Icon(Icons.search),
          title: Text(s),
          onTap: () => _onSuggestionTap(s),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Suche nach Anime, Serie oder Folge',
            border: InputBorder.none,
          ),
          onChanged: (_) => _onSearchChanged(),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onSearchChanged();
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _controller.text.isEmpty
            ? _buildHistoryList()
            : (_results.isNotEmpty
                  ? ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = _results[index];
                        final AnimeRelease r = entry['release'] as AnimeRelease;
                        final DateTime date = entry['date'] as DateTime;
                        return ListTile(
                          title: Text(r.title),
                          subtitle: Text(
                            '${r.episodeInfo} — ${DateFormat('dd.MM.yyyy').format(date)}',
                          ),
                          onTap: () => _onResultTap(r, date),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: Text(
                              'Vorschläge',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildSuggestionList(),
                          if (_suggestions.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 32.0),
                              child: Center(
                                child: Text(
                                  'Keine Treffer',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )),
      ),
    );
  }
}
