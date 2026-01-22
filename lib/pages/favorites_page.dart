//import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:translator/translator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../repositories/favorites_repository.dart';
import '../models/favorite_anime.dart';
import '../models/anime_release.dart';
import '../services/crunchyroll_service.dart';
import '../settings.dart'; // Für AppSettings 
import '../utils/favorites_notifier.dart'; // Für favoritesChangeNotifier
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../widgets/anime_details_dialog.dart';

class FavoritesPage extends StatefulWidget {
  final VoidCallback? onAccentColorChanged;
  final WatchlistService? watchlistService;

  const FavoritesPage({super.key, this.onAccentColorChanged, this.watchlistService});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late final FavoritesRepository _favoritesRepo;
  late final CrunchyrollService _crunchyrollService;
  List<FavoriteAnime> _favorites = [];
  bool _isLoading = true;
  Watchlist? _watchlist;

  @override
  void initState() {
    super.initState();
    _favoritesRepo = FavoritesRepository();
    _crunchyrollService = CrunchyrollService();
    _loadFavorites();
    if (widget.watchlistService != null) {
      _watchlist = widget.watchlistService!.watchlist;
      widget.watchlistService!.loadWatchlist();
      _watchlist!.addListener(_onWatchlistChanged);
    }
  }

  @override
  void dispose() {
    _watchlist?.removeListener(_onWatchlistChanged);
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    final favorites = await _favoritesRepo.getAllFavorites();
    setState(() {
      _favorites = favorites;
      _isLoading = false;
    });
  }

  Future<void> _removeFavorite(FavoriteAnime anime) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aus Favoriten entfernen?'),
        content: Text('Möchtest du "${anime.title}" wirklich aus deinen Favoriten entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _favoritesRepo.removeFavorite(anime.title);
      
      // Benachrichtige alle Cards im Kalender über die Änderung
      favoritesChangeNotifier.value++;
      
      _loadFavorites(); // Reload list
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${anime.title} aus Favoriten entfernt'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleNotifications(FavoriteAnime anime, bool enabled) async {
    final index = _favorites.indexWhere((f) => f.title == anime.title);
    if (index == -1) return;

    // Optimistic update
    setState(() {
      _favorites[index] = anime.copyWith(notificationsEnabled: enabled);
    });

    final success = await _favoritesRepo.setNotificationsEnabled(anime.title, enabled);

    if (!success && mounted) {
      // Rollback on failure
      setState(() {
        _favorites[index] = anime;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Konnte Push-Einstellung nicht speichern')),
      );
    } else if (mounted) {
   //   ScaffoldMessenger.of(context).showSnackBar(
   //     SnackBar(
   //       content: Text(enabled
   //           ? '🔔 Push-Benachrichtigungen aktiviert'
   //          : '🔕 Push-Benachrichtigungen deaktiviert'),
   //       duration: const Duration(seconds: 2),
  //      ),
   //   );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Favoriten'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Optionen',
            onSelected: (value) {
              if (value == 'export') {
                _exportFavorites();
              } else if (value == 'import') {
                _importFavorites();
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Favoriten',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Füge Anime zu deinen Favoriten hinzu,\num Benachrichtigungen zu erhalten.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final anime = _favorites[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: InkWell(
                        onTap: () => _showAnimeDetails(anime),
                        child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: anime.imageUrl != null && anime.imageUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: anime.imageUrl!,
                                  width: 50,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    width: 50,
                                    height: 70,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.image),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 50,
                                    height: 70,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                )
                              : Container(
                                  width: 50,
                                  height: 70,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                ),
                        ),
                        title: Text(
                          anime.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      size: 10,
                                      color: Colors.red.shade400,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Hinzugefügt: ${_formatDate(anime.addedDate)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_watchlist != null && anime.seriesUrl != null)
                                  Builder(builder: (context) {
                                    final matches = _watchlist!.entries.where((e) => e.animeId == anime.seriesUrl).toList();
                                    if (matches.isNotEmpty) {
                                      final match = matches.first;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6.0),
                                        child: Text(
                                          'Watchlist: ${match.episodesWatched}/${match.totalEpisodes} Folgen',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }),
                              ],
                            ),
                        ),
                        trailing: SizedBox(
                          width: 100,
                          height: 56,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 52,
                                height: 56,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 37,
                                      height: 37,
                                      child: IconButton(
                                        icon: Icon(
                                          anime.notificationsEnabled
                                              ? Icons.notifications_active
                                              : Icons.notifications_off,
                                          color: anime.notificationsEnabled
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.grey,
                                          size: 22,
                                        ),
                                        tooltip: anime.notificationsEnabled ? 'Push deaktivieren' : 'Push aktivieren',
                                        onPressed: () => _toggleNotifications(anime, !anime.notificationsEnabled),
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: anime.notificationsEnabled
                                            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                                            : Colors.grey.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        anime.notificationsEnabled ? 'Ein' : 'Aus',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: anime.notificationsEnabled
                                              ? Theme.of(context).colorScheme.primary
                                              : Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                  tooltip: 'Aus Favoriten entfernen',
                                  onPressed: () => _removeFavorite(anime),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    );
                  },
                ),
    );
  }

  void _showAnimeDetails(FavoriteAnime anime) {
    // Erstelle ein AnimeRelease aus dem Favoriten
    final release = AnimeRelease(
      title: anime.title,
      episodeTitle: '',
      episodeNumber: '',
      episodeUrl: '',
      releaseTime: DateTime.now(),
      seriesUrl: anime.seriesUrl ?? '',
      isPremiere: false,
      imageUrl: anime.imageUrl,
    );

    // If this favorite exists in the watchlist, prefill episode info and total
    int? totalEpisodes;
    AnimeRelease dialogRelease = release;
    if (_watchlist != null && anime.seriesUrl != null) {
      final matches = _watchlist!.entries.where((e) => e.animeId == anime.seriesUrl).toList();
      if (matches.isNotEmpty) {
        final match = matches.first;
        // build a new AnimeRelease with episodeNumber set to watched count
        dialogRelease = AnimeRelease(
          title: release.title,
          episodeTitle: release.episodeTitle,
          episodeNumber: match.episodesWatched.toString(),
          episodeUrl: release.episodeUrl,
          releaseTime: release.releaseTime,
          seriesUrl: release.seriesUrl,
          isPremiere: release.isPremiere,
          imageUrl: release.imageUrl,
          description: release.description,
        );
        totalEpisodes = match.totalEpisodes;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AnimeDetailsDialog(
          release: dialogRelease,
          crunchyrollService: _crunchyrollService,
          watchlistService: widget.watchlistService,
          totalEpisodes: totalEpisodes,
          showEpisodeBadge: false,
          showTimeBadge: false,
          onFavoriteRemoved: () {
            favoritesChangeNotifier.value++;
            _loadFavorites();
          },
        );
      },
    );
  }

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final aDate = DateTime(date.year, date.month, date.day);

  final diff = today.difference(aDate).inDays;

  if (diff == 0) {
    return 'Heute';
  } else if (diff == 1) {
    return 'Gestern';
  } else {
    // Genaues Datum anzeigen mit führenden Nullen
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }
}



  Future<void> _exportFavorites() async {
    if (_favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Keine Favoriten zum Exportieren'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // Exportiere - User wählt Speicherort
      final filePath = await _favoritesRepo.exportFavoritesToJson();

      // User hat abgebrochen
      if (filePath == null) {
        return;
      }

      // Zeige Erfolgs-Dialog mit Share-Option
      if (mounted) {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Export erfolgreich'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_favorites.length} Favoriten exportiert'),
                const SizedBox(height: 8),
                const Text(
                  'Gespeichert unter:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  filePath,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'close'),
                child: const Text('Schließen'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, 'share'),
                icon: const Icon(Icons.share),
                label: const Text('Teilen'),
              ),
            ],
          ),
        );

        // Teilen wenn gewünscht
        if (result == 'share') {
          try {
            await Share.shareXFiles(
              [XFile(filePath)],
              subject: 'Meine Crunchyroll Favoriten',
              text: 'Crunchyroll Favoriten-Liste (${_favorites.length} Anime)',
            );
          } catch (e) {
            if (kDebugMode) print('Share error: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Fehler beim Teilen: $e'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Exportieren: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _importFavorites() async {
    try {
      // Datei auswählen
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Favoriten-Datei auswählen',
      );

      if (result == null || result.files.isEmpty) {
        return; // User hat abgebrochen
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        throw Exception('Kein Dateipfad erhalten');
      }

      // Zeige Lade-Dialog
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
                    Text('Importiere Favoriten...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Importiere
      final importedCount = await _favoritesRepo.importFavoritesFromJson(filePath);

      // Schließe Lade-Dialog
      if (mounted) Navigator.pop(context);

      // Lade Favoriten neu
      await _loadFavorites();

      // Benachrichtige andere Cards
      favoritesChangeNotifier.value++;

      // Zeige Erfolgs-Dialog
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
                  ? '1 neuer Favorit wurde importiert'
                  : '$importedCount neue Favoriten wurden importiert',
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
    } catch (e) {
      // Schließe Lade-Dialog falls noch offen
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (kDebugMode) print('Import error: $e');
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
}

/// Dialog für Anime-Details in der Favoriten-Liste
class _FavoriteAnimeDetailsDialog extends StatefulWidget {
  final FavoriteAnime anime;
  final AnimeRelease release;
  final CrunchyrollService crunchyrollService;
  final VoidCallback onFavoriteRemoved;
  final WatchlistService? watchlistService;

  const _FavoriteAnimeDetailsDialog({
    required this.anime,
    required this.release,
    required this.crunchyrollService,
    required this.onFavoriteRemoved,
    this.watchlistService,
  });

  @override
  State<_FavoriteAnimeDetailsDialog> createState() => _FavoriteAnimeDetailsDialogState();
}

class _FavoriteAnimeDetailsDialogState extends State<_FavoriteAnimeDetailsDialog> {
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final GoogleTranslator _translator = GoogleTranslator();
  String? _descriptionOriginal;
  String? _descriptionTranslated;
  bool _isLoadingDescription = true;
  bool _isTranslating = false;
  bool _showGerman = true;
  bool _isFavorite = true; // Immer true, da es aus Favoriten kommt
  bool _isLoadingFavorite = false;
  bool _autoTranslateEnabled = true;
  bool _isInWatchlist = false;
  bool _isProcessingWatchlist = false;

  @override
  void initState() {
    super.initState();
    _loadDescription();
    _updateWatchlistState();
  }

  void _updateWatchlistState() {
    final ws = widget.watchlistService;
    if (ws == null) return;
    final id = widget.anime.seriesUrl ?? widget.anime.title;
    _isInWatchlist = ws.watchlist.entries.any((e) => e.animeId == id);
  }

  Future<void> _loadDescription() async {
    final description = await widget.crunchyrollService.fetchDescription(
      widget.release,
    );
    if (mounted) {
      setState(() {
        _descriptionOriginal = description;
        _isLoadingDescription = false;
      });
      
      // Lade Auto-Translate Setting
      final autoTranslate = await AppSettings.getAutoTranslate();
      if (mounted) {
        setState(() {
          _autoTranslateEnabled = autoTranslate;
        });
      }

      // Starte Übersetzung nur wenn Setting aktiviert (spart unnötige Arbeit)
      if (autoTranslate) {
        await _translateDescription();
      }

      // Zeige automatisch Deutsche Version nur wenn Setting aktiviert
      if (mounted) {
        setState(() {
          _showGerman = autoTranslate;
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

  Future<void> _toggleFavorite() async {
    setState(() => _isLoadingFavorite = true);
    
    try {
      // Aus Favoriten entfernen
      await _favoritesRepository.removeFavorite(widget.anime.title);
      
      if (mounted) {
        setState(() {
          _isFavorite = false;
          _isLoadingFavorite = false;
        });
        
        // Callback ausführen
        widget.onFavoriteRemoved();
        
        // Dialog schließen
        Navigator.of(context).pop();
        
        // Snackbar anzeigen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💔 ${widget.anime.title} aus Favoriten entfernt'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling favorite: $e');
      if (mounted) {
        setState(() => _isLoadingFavorite = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Fehler beim Speichern')),
        );
      }
    }
  }

  Future<void> _openCrunchyrollSeries() async {
    try {
      final seriesUrl = widget.anime.seriesUrl;
      if (seriesUrl == null || seriesUrl.isEmpty) {
        if (kDebugMode) print('No series URL available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keine Crunchyroll-URL verfügbar')),
          );
        }
        return;
      }
      
      final Uri url = Uri.parse(seriesUrl);
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
                // Header mit Bild
                Stack(
                  children: [
                    if (widget.anime.imageUrl != null &&
                        widget.anime.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: widget.anime.imageUrl!,
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
                    // Favorit Button (oben links)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 22,
                        child: _isLoadingFavorite
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  _isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _isFavorite ? Colors.red : Colors.white,
                                  size: 24,
                                ),
                                onPressed: _toggleFavorite,
                                padding: EdgeInsets.zero,
                              ),
                      ),
                    ),
                    // Watchlist Button (oben links, neben Favorit)
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
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
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
                                    final id = widget.anime.seriesUrl ?? widget.anime.title;
                                    final exists = ws.watchlist.entries.any((e) => e.animeId == id);
                                    if (exists) {
                                      ws.watchlist.removeEntry(id);
                                      await ws.saveWatchlist();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.anime.title} aus Watchlist entfernt')),
                                        );
                                      }
                                    } else {
                                      final cs = CrunchyrollService();
                                      final knownMax = await cs.getMaxEpisodeFromCache(widget.anime.seriesUrl, widget.anime.title);
                                      final parsedCurrent = 0;
                                      final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;
                                      final entry = WatchlistEntry(
                                        animeId: id,
                                        title: widget.anime.title,
                                        imageUrl: widget.anime.imageUrl,
                                        episodesWatched: 0,
                                        totalEpisodes: total,
                                      );
                                      ws.watchlist.addEntry(entry);
                                      await ws.saveWatchlist();
                                      cs.scheduleWatchlistEntryUpdate(ws, entry);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.anime.title} zur Watchlist hinzugefügt')),
                                        );
                                      }
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
                    // Close Button
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
                  ],
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Titel
                      Text(
                        widget.anime.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),

                      // Plot/Beschreibung mit Sprachwechsel
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

                      // Button zu Crunchyroll
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _openCrunchyrollSeries,
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
