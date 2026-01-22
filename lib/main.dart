import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:translator/translator.dart';
import 'dart:io';
import 'dart:async';
import 'models/anime_release.dart';
import 'services/crunchyroll_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/permission_service.dart';
import 'services/battery_optimization_service.dart';
import 'repositories/favorites_repository.dart';
import 'repositories/seen_repository.dart';
import 'models/favorite_anime.dart';
import 'models/notification_log.dart';
import 'settings.dart';
import 'pages/watchlist_page.dart';
//import 'pages/search_page.dart' as search_page;
import 'models/watchlist.dart';
import 'services/watchlist_service.dart';
import 'widgets/anime_details_dialog.dart';
import 'utils/favorites_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  Intl.defaultLocale = 'de_DE';
  
  // Notification Service initialisieren
  await NotificationService().initialize();
  
  // Background Service initialisieren und Task starten (alle 20 Minuten)
  await BackgroundService.initialize();
  await BackgroundService().startPeriodicScraperTask(intervalMinutes: 20);
  
  runApp(const MainApp());
}

// Simple in-app search page for locally loaded releases
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

  // Autocomplete / history
  List<String> _history = [];
  List<String> _allSuggestions = [];
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    // Build suggestion pool from loaded releases
    final titles = <String>{};
    widget.releases.values.expand((l) => l).forEach((r) {
      titles.add(r.title);
      if (r.episodeTitle.isNotEmpty) titles.add(r.episodeTitle);
    });
    _allSuggestions = titles.toList()..sort();

    // Load history
    AppSettings.getSearchHistory().then((list) {
      if (mounted) setState(() => _history = list);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    // immediate suggestions
    final text = _controller.text.trim();
    _updateSuggestions(text);

    // debounced full search
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
    final matched = _allSuggestions.where((s) => s.toLowerCase().contains(q)).take(10).toList();
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
        final hay = '${r.title} ${r.episodeTitle} ${r.episodeInfo}'.toLowerCase();
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
    await AppSettings.addToSearchHistory(suggestion);
    final list = await AppSettings.getSearchHistory();
    if (mounted) setState(() => _history = list);
    _performSearch(suggestion);
  }

  Future<void> _onResultTap(AnimeRelease r, DateTime date) async {
    await AppSettings.addToSearchHistory(r.title);
    final list = await AppSettings.getSearchHistory();
    if (mounted) setState(() => _history = list);

    // mark as seen (so background notifications skip it)
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
      if (kDebugMode) print('❌ Error marking seen from search: $e');
    }

    // show details dialog
    await showDialog(
      context: context,
      builder: (BuildContext ctx) => AnimeDetailsDialog(
        release: r,
        crunchyrollService: CrunchyrollService(),
        watchlistService: widget.watchlistService,
        onAddToWatchlist: (release) {
          _addToWatchlist(release);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _addToWatchlist(AnimeRelease release) async {
    if (widget.watchlistService == null) return;
    final cs = CrunchyrollService();
    final parsedCurrent = int.tryParse(release.episodeNumber) ?? 0;
    // fast cache-only lookup (no network) for snappy UI
    final knownMax = await cs.getMaxEpisodeFromCache(release.seriesUrl, release.title);
    final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;

    final entry = WatchlistEntry(
      animeId: release.seriesUrl,
      title: release.title,
      imageUrl: release.imageUrl,
      episodesWatched: 0,
      totalEpisodes: total,
    );
    widget.watchlistService!.watchlist.addEntry(entry);
    await widget.watchlistService!.saveWatchlist();
    // schedule background update (may perform network) - don't await
    cs.scheduleWatchlistEntryUpdate(widget.watchlistService!, entry);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Zur Watchlist hinzugefügt: ${release.title}')),
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) return const Center(child: Text('Keine letzten Suchanfragen'));
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
    if (_suggestions.isEmpty) return const SizedBox.shrink();
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
                        subtitle: Text('${r.episodeInfo} — ${DateFormat('dd.MM.yyyy').format(date)}'),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('Vorschläge', style: TextStyle(color: Colors.grey.shade700)),
                        ),
                        const SizedBox(height: 4),
                        _buildSuggestionList(),
                        if (_suggestions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 32.0),
                            child: Center(child: Text('Keine Treffer', style: TextStyle(color: Colors.grey.shade600))),
                          ),
                      ],
                    ),
                  )),
      ),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Color _accentColor = Colors.orange;
  final Watchlist watchlist = Watchlist();
  late final WatchlistService watchlistService;

  @override
  void initState() {
    super.initState();
    watchlistService = WatchlistService(watchlist);
    _loadAccentColor();
    // Versuche einmalig Migration von Favoriten-Notification-Settings in die Watchlist
    _runWatchlistMigration();
  }

  void _runWatchlistMigration() async {
    try {
      final migrated = await watchlistService.migrateNotificationSettingsFromFavorites();
      if (migrated > 0) {
        if (kDebugMode) print('🔁 Migrated $migrated notification settings from favorites to watchlist');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🔁 $migrated Favoriten-Benachrichtigungen in Watchlist übernommen')),
          );
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Migration error: $e');
    }
  }

  Future<void> _loadAccentColor() async {
    final color = await AppSettings.getAccentColor();
    setState(() {
      _accentColor = color;
    });
  }

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarPage(onAccentColorChanged: _loadAccentColor, watchlistService: watchlistService),
    ];
    return MaterialApp(
      title: 'Crunchyroll Anime Kalender',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: pages[0],
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  final VoidCallback? onAccentColorChanged;
  final WatchlistService? watchlistService;

  const CalendarPage({super.key, this.onAccentColorChanged, this.watchlistService});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with TickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  
  DateTime? _selectedDay;
  // -1 = swiped left (next day), 1 = swiped right (previous day)
  int _lastSwipeDirection = 0;
  // Drag state for interactive swipe preview
  double _dragOffset = 0.0; // pixels, positive = dragging right (show previous), negative = left (show next)
  bool _isDragging = false;
  bool _isSnapping = false;
  late AnimationController _dragAnimationController;
  Animation<double>? _currentSettleAnimation; // Track current animation to remove listeners
  VoidCallback? _currentSettleListener; // Track the setState listener
  Function(AnimationStatus)? _currentStatusListener; // Track the status listener
  DateTime? _dragStartDay;
  // Stable snapshot of the selected/focused day at the start of the current drag session
  DateTime? _dragSessionStartDay;
  // Wenn während des Drags bereits ein Seitenwechsel ausgeführt wurde,
  // verhindern wir beim Drag-Ende ein zweites Commit.
  bool _committedDuringDrag = false;
  Map<DateTime, List<AnimeRelease>> _releases = {};
  final CrunchyrollService _crunchyrollService = CrunchyrollService();
  bool _isLoadingImages = false;
  int _imagesLoaded = 0;
  int _imagesToLoad = 0;
  bool _cacheLoaded = false;
  bool _isLoadingReleases = false;
  // Accumulates vertical drag delta to allow repeated swipes without lifting
  double _verticalDragDelta = 0.0;
  // Threshold in logical pixels to trigger a format change while dragging
  // Increased to reduce accidental switches while swiping through the calendar
  final double _verticalDragThreshold = 260.0;
  // Horizontal commit thresholds for day swipe
  // Fraction of width that must be dragged to commit (35% requested)
  final double _horizontalCommitFraction = 0.35;
  // Minimum velocity (px/s) to force a commit regardless of distance
  final double _horizontalVelocityCommit = 900.0;
  // Wenn true: Kalender ist minimiert und zeigt nur den Header (Monat + chevrons)
  bool _isCalendarMinimized = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadCalendarFormat();
    _loadAutoMinimizeSetting();

    // Berechtigungen nach dem ersten Frame anfragen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });

    // Registriere Callback für Bilder-Ladestatus
    _crunchyrollService.onImageLoadingChanged = (isLoading, loaded, total) {
      if (mounted) {
        setState(() {
          _isLoadingImages = isLoading;
          _imagesLoaded = loaded;
          _imagesToLoad = total;
        });
      }
    };
    
    // Registriere Callback wenn Bilder geladen wurden - UI aktualisieren
    _crunchyrollService.onImageLoaded = () {
      if (kDebugMode) print('🔔 CrunchyrollService.onImageLoaded triggered');
      if (mounted) {
        setState(() {
          // Trigger rebuild um neue Bilder anzuzeigen
        });
      }
    };

    // Start loading releases (show loader until first load completes)
    setState(() {
      _isLoadingReleases = true;
    });
    _loadReleases().whenComplete(() {
      if (mounted) {
        setState(() {
          _isLoadingReleases = false;
        });
      }
    });

    // Starte automatische Updates alle 5 Minuten
    _crunchyrollService.startAutoUpdate(() {
      if (mounted) {
        _loadReleases();
      }
    });

    // Controller for finishing/settling drag animations
    _dragAnimationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  }

  Future<void> _loadAutoMinimizeSetting() async {
    try {
      final enabled = await AppSettings.getAutoMinimizeCalendar();
      final threshold = await AppSettings.getAutoMinimizeScrollThreshold();
      if (mounted) {
        setState(() {
          _isCalendarMinimized = _isCalendarMinimized; // keep current minimized state
        });
      }
      // store locally for quick checks
      _autoMinimizeEnabled = enabled;
      _autoMinimizeScrollThreshold = threshold;
    } catch (e) {
      if (kDebugMode) print('Error loading auto-minimize setting: $e');
      _autoMinimizeEnabled = true;
    }
  }

  // Cached toggle value for quicker checks
  bool _autoMinimizeEnabled = true;
  // cumulative scroll delta (pixels) accumulated while the list is scrolled
  double _cumulativeScrollDelta = 0.0;
  // threshold (pixels) read from settings before auto-minimizing
  double _autoMinimizeScrollThreshold = 200.0;
  OverlayEntry? _topDateOverlay;

  @override
  void dispose() {
    _crunchyrollService.stopAutoUpdate();
    _dragAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadCalendarFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final formatIndex = prefs.getInt('calendar_format') ?? 0;
    final format = CalendarFormat.values[formatIndex];
    setState(() {
      _calendarFormat = format;
    });
  }

  void _goToPreviousMonth() {
    setState(() {
      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, _focusedDay.day);
    });
    _loadReleases();
  }

  void _goToNextMonth() {
    setState(() {
      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, _focusedDay.day);
    });
    _loadReleases();
  }

  /// Wechsel das Kalender-Format (Swipe up = kompakter, Swipe down = umfangreicher)
  void _cycleCalendarFormat({required bool up}) {
    final formats = [
      CalendarFormat.month,
      CalendarFormat.twoWeeks,
      CalendarFormat.week,
    ];
    final currentIndex = formats.indexOf(_calendarFormat);
    int newIndex = currentIndex;
    if (up) {
      if (currentIndex < formats.length - 1) newIndex = currentIndex + 1;
    } else {
      if (currentIndex > 0) newIndex = currentIndex - 1;
    }

    if (newIndex != currentIndex) {
      setState(() {
        _calendarFormat = formats[newIndex];
      });
      // Persistieren und neu laden
      _saveCalendarFormat(_calendarFormat);
      _loadReleases();
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await PermissionService().requestInitialPermissions();
      if (kDebugMode) print('✓ Berechtigungen angefragt');
      
      // Zeige Akku-Optimierung Dialog beim ersten Start (nur Android)
      if (Platform.isAndroid && mounted) {
        final hasShown = await BatteryOptimizationService.hasShownDialog();
        if (!hasShown && mounted) {
          await BatteryOptimizationService.showBatteryOptimizationDialog(context);
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Fehler beim Anfragen der Berechtigungen: $e');
    }
  }

  Future<void> _saveCalendarFormat(CalendarFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('calendar_format', format.index);
  }

  Future<void> _loadReleases({bool showMessage = false}) async {
    // Lade beim Start alle gecachten Daten (Bilder, verarbeitete Titel) - nur einmal
    if (mounted) {
      setState(() {
        _isLoadingReleases = true;
      });
    }
    if (!_cacheLoaded) {
      await _crunchyrollService.loadCacheOnStartup();
      _cacheLoaded = true;
    }

    try {
      // Laden des aktuellen fokussierten Monats
      final dateToLoad = _selectedDay ?? _focusedDay;
      
      if (kDebugMode) print('Loading releases for: ${dateToLoad.day}.${dateToLoad.month}.${dateToLoad.year}');
      
      final releases = await _crunchyrollService.getReleasesForWeek(
        dateToLoad,
      );

      final Map<DateTime, List<AnimeRelease>> releasesByDay = {};
      for (var release in releases) {
        final date = DateTime(
          release.releaseTime.year,
          release.releaseTime.month,
          release.releaseTime.day,
        );

        if (releasesByDay[date] == null) {
          releasesByDay[date] = [];
        }
        releasesByDay[date]!.add(release);
      }

      // Optionally remove duplicate releases (same episode URL or same title+episode)
      final hideDup = await AppSettings.getHideDuplicateReleases();
      Map<DateTime, List<AnimeRelease>> finalByDay = releasesByDay;
      if (hideDup) {
        String normalizeUrl(String url) {
          try {
            final uri = Uri.parse(url);
            // Keep scheme, host, port and path; remove query and fragment
            final normalized = Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null,
              path: uri.path,
            ).toString();
            return normalized.toLowerCase();
          } catch (_) {
            return url.toLowerCase();
          }
        }

        final deduped = <DateTime, List<AnimeRelease>>{};
        releasesByDay.forEach((date, list) {
          final seen = <String>{};
          final out = <AnimeRelease>[];
          for (var r in list) {
            final urlPart = (r.episodeUrl.isNotEmpty) ? normalizeUrl(r.episodeUrl) : '';
            final titlePart = '${r.title.trim().toLowerCase()}_${r.episodeNumber.trim().toLowerCase()}';
            final id = urlPart.isNotEmpty ? urlPart : titlePart;
            if (!seen.contains(id)) {
              seen.add(id);
              out.add(r);
            }
          }
          deduped[date] = out;
        });
        finalByDay = deduped;
      }

      setState(() {
        _releases = finalByDay;
      });

      // Wenn die App gerade im Vordergrund Releases lädt, markiere sie als 'gesehen'
      // damit später keine Benachrichtigungen für bereits sichtbare Einträge erscheinen.
      try {
        final seenRepo = SeenRepository();
        for (final list in finalByDay.values) {
          for (final r in list) {
            final tempLog = NotificationLog(
              favoriteTitle: r.title,
              releaseTitle: r.episodeTitle,
              episodeNumber: r.episodeNumber,
              notifyTime: DateTime.now(),
            );
            final hash = tempLog.generateContentHash();
            // don't await to speed up UI; fire-and-forget
            seenRepo.markSeen(hash);
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ Error auto-marking seen releases: $e');
      }
      
      // Zeige Meldung wenn gewünscht und eingestellt
      if (showMessage && mounted) {
        _showRefreshSuccessMessage();
      }
      
      // Nach dem aktuellen Monat: lade benachbarte Monate nacheinander
      _preloadAdjacentMonths(dateToLoad);
      
      // Dann lade alle anderen gecachten Monate für die Punkte
      // aber nicht parallel mit den Bildern
      _loadAllCachedMonths();
    } catch (e) {
      if (kDebugMode) print('Error loading releases: $e');
    }
    finally {
      if (mounted) {
        setState(() {
          _isLoadingReleases = false;
        });
      }
    }
  }
  
  /// Lädt Vormonat und Nächstmonat im Hintergrund vor
  /// damit Benutzer auf alle angezeigten Tage klicken kann
  Future<void> _preloadAdjacentMonths(DateTime referenceDate) async {
    try {
      // Vormonat laden
      final previousMonth = DateTime(referenceDate.year, referenceDate.month - 1, 1);
      if (kDebugMode) print('📅 Preloading previous month: ${previousMonth.month}/${previousMonth.year}');
      final previousMonthReleases = await _crunchyrollService.getReleasesForWeek(previousMonth);
      
      // Nächster Monat laden
      final nextMonth = DateTime(referenceDate.year, referenceDate.month + 1, 1);
      if (kDebugMode) print('📅 Preloading next month: ${nextMonth.month}/${nextMonth.year}');
      final nextMonthReleases = await _crunchyrollService.getReleasesForWeek(nextMonth);
      
      // Füge die vorgeladenen Releases zur _releases Map hinzu
      // damit die Punkte im Kalender angezeigt werden
      if (mounted) {
        setState(() {
          // Verarbeite Releases aus Vormonat
          for (var release in previousMonthReleases) {
            final date = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );
            if (_releases[date] == null) {
              _releases[date] = [];
            }
            // Verhindere Duplikate
            if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
              _releases[date]!.add(release);
            }
          }
          
          // Verarbeite Releases aus Nächstmonat
          for (var release in nextMonthReleases) {
            final date = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );
            if (_releases[date] == null) {
              _releases[date] = [];
            }
            // Verhindere Duplikate
            if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
              _releases[date]!.add(release);
            }
          }
        });
      }
      
      if (kDebugMode) print('✓ Adjacent months preloaded and added to calendar');
    } catch (e) {
      if (kDebugMode) print('Error preloading adjacent months: $e');
    }
  }

  Future<void> _forceRefresh() async {
    // Prüfe ob der Monat eingeforen ist (älter als 2 Monate)
    final now = DateTime.now();
    
    // Berechne korrekt 2 Monate zurück (mit Jahr-Überlauf)
    // Setze einen Tag später, damit der Monat "älter oder gleich" ist
    int freezeYear = now.year;
    int freezeMonth = now.month - 2;
    while (freezeMonth <= 0) {
      freezeYear--;
      freezeMonth += 12;
    }
    final twoMonthsAgo = DateTime(freezeYear, freezeMonth, 2); // Tag 2 statt 1
    
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    
    if (kDebugMode) print('🧊 Freeze check: monthStart=${monthStart.month}/${monthStart.year}, twoMonthsAgo=${twoMonthsAgo.month}/${twoMonthsAgo.year}, isBefore=${monthStart.isBefore(twoMonthsAgo)}');
    
    if (monthStart.isBefore(twoMonthsAgo)) {
      // Monat ist eingeforen - Refresh nicht erlaubt
      _showFrozenMonthMessage();
      return;
    }

    try {
      // Übergebe den angezeigten Monat für den Refresh
      final releases = await _crunchyrollService.forceRefresh(forMonth: _focusedDay);

      final Map<DateTime, List<AnimeRelease>> releasesByDay = {};
      for (var release in releases) {
        final date = DateTime(
          release.releaseTime.year,
          release.releaseTime.month,
          release.releaseTime.day,
        );

        if (releasesByDay[date] == null) {
          releasesByDay[date] = [];
        }
        releasesByDay[date]!.add(release);
      }

      // Respect user setting: optionally hide duplicate releases
      final hideDup = await AppSettings.getHideDuplicateReleases();
      Map<DateTime, List<AnimeRelease>> finalByDay = releasesByDay;
      if (hideDup) {
        String normalizeUrl(String url) {
          try {
            final uri = Uri.parse(url);
            final normalized = Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null,
              path: uri.path,
            ).toString();
            return normalized.toLowerCase();
          } catch (_) {
            return url.toLowerCase();
          }
        }

        final deduped = <DateTime, List<AnimeRelease>>{};
        releasesByDay.forEach((date, list) {
          final seen = <String>{};
          final out = <AnimeRelease>[];
          for (var r in list) {
            final urlPart = (r.episodeUrl.isNotEmpty) ? normalizeUrl(r.episodeUrl) : '';
            final titlePart = '${r.title.trim().toLowerCase()}_${r.episodeNumber.trim().toLowerCase()}';
            final id = urlPart.isNotEmpty ? urlPart : titlePart;
            if (!seen.contains(id)) {
              seen.add(id);
              out.add(r);
            }
          }
          deduped[date] = out;
        });
        finalByDay = deduped;
      }

      setState(() {
        _releases = finalByDay;
      });
      
      // Zeige Erfolgsmeldung
      _showRefreshSuccessMessage();
    } catch (e) {
      if (kDebugMode) print('Error during force refresh: $e');
    }
  }
  
  /// Zeigt eine Meldung an, dass die Einträge aktualisiert wurden
  Future<void> _showRefreshSuccessMessage() async {
    final showMessage = await AppSettings.getShowRefreshMessage();
    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓ Einträge aktualisiert'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  void _showSelectedDateDialog(DateTime selected) {
    final full = DateFormat("EEEE, d. MMMM yyyy", 'de_DE').format(selected);
    if (!mounted) return;

    // remove any existing overlay
    _topDateOverlay?.remove();
    _topDateOverlay = null;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final topOffset = MediaQuery.of(context).padding.top + 48.0 + 8.0 + 3.0;

    _topDateOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: topOffset,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
                child: Text(full, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_topDateOverlay!);

    Future.delayed(const Duration(milliseconds: 1500), () {
      _topDateOverlay?.remove();
      _topDateOverlay = null;
    });
  }

  /// Zeigt eine Nachricht an, dass der Monat eingeforen ist
  void _showFrozenMonthMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '🧊 Dieser Monat ist älter als 2 Monate und kann nicht aktualisiert werden. '
          'Die Einträge sind gesperrt um zu verhindern, dass Crunchyroll-Daten verloren gehen.',
          maxLines: 3,
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.orange.shade700,
      ),
    );
  }

  List<AnimeRelease> _getReleasesForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _releases[date] ?? [];
  }

  Widget _buildContentForDay(DateTime day) {
    final releases = _getReleasesForDay(day);

    if (_isLoadingReleases) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Lade Releases…',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (releases.isEmpty) {
      return ListView(
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
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: releases.length,
      itemBuilder: (context, index) {
        final release = releases[index];
        return _buildReleaseCard(release);
      },
    );
  }

  /// Lädt alle gecachten Monate beim Start um Punkte überall anzuzeigen
  Future<void> _loadAllCachedMonths() async {
    try {
      final cachedMonths = await _crunchyrollService.getCachedMonths();
      if (kDebugMode) print('Found ${cachedMonths.length} cached months');
      
      // Sortiere Monate: aktueller und benachbarte sind bereits geladen
      // Lade nur die restlichen nacheinander
      final now = DateTime.now();
      final currentMonth = (now.year, now.month);
      final previousMonth = (now.year, now.month <= 1 ? now.year - 1 : now.year, (now.month - 1 <= 0 ? 12 : now.month - 1));
      final nextMonth = (now.year, now.month >= 12 ? now.year + 1 : now.year, (now.month + 1 > 12 ? 1 : now.month + 1));
      
      // Filter: nur Monate laden die noch nicht geladen wurden
      final otherMonths = cachedMonths.where((month) => 
        !(month == currentMonth || 
          month == previousMonth || 
          month == nextMonth)
      ).toList();
      
      if (kDebugMode) print('Loading ${otherMonths.length} additional months sequentially...');
      
      // Lade nacheinander SEQUENZIELL, nicht parallel
      for (var (year, month) in otherMonths) {
        final dateInMonth = DateTime(year, month, 1);
        if (kDebugMode) print('📥 Loading cached month: $month/$year');
        final releases = await _crunchyrollService.getReleasesForMonthFromCache(dateInMonth);
        
        if (releases.isNotEmpty) {
          // Gruppiere Releases nach Tag
          for (var release in releases) {
            final date = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );
            
            if (!_releases.containsKey(date)) {
              _releases[date] = [];
            }
            
            // Füge hinzu wenn nicht bereits vorhanden (Duplikat-Prüfung)
            if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
              _releases[date]!.add(release);
            }
          }
        }
      }
      
      // Trigger UI Update um Punkte anzuzeigen
      if (mounted) {
        setState(() {});
      }
      
      if (kDebugMode) print('✓ Loaded ${_releases.length} days with anime releases from cache');
    } catch (e) {
      if (kDebugMode) print('Error loading cached months: $e');
    }
  }
  
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          crunchyrollService: _crunchyrollService,
          onSettingsChanged: () {
            // Direkt Releases neu laden (z.B. nach Aktivieren von "Doppelte Releases ausblenden")
            _loadReleases();
            // Starte/aktualisiere Auto-Update mit neuen Einstellungen
            _crunchyrollService.restartAutoUpdate(() {
              if (mounted) {
                _loadReleases();
              }
            });
            // Lade neue Einstellung für automatisches Minimieren
            _loadAutoMinimizeSetting();
            // Benachrichtige MainApp dass sich die Accent-Farbe geändert hat
            widget.onAccentColorChanged?.call();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Kalender'),
            if (_isLoadingImages)
              Text(
                'Lade Bilder... $_imagesLoaded/$_imagesToLoad',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Suche',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchPage(releases: _releases, watchlistService: widget.watchlistService),
                ),
              );
              if (result != null && result is Map) {
                final AnimeRelease r = result['release'] as AnimeRelease;
                final DateTime date = result['date'] as DateTime;
                // Show details dialog for the selected release (do not change calendar focus)
                await showDialog(
                  context: context,
                  builder: (BuildContext ctx) => AnimeDetailsDialog(
                    release: r,
                    crunchyrollService: CrunchyrollService(),
                    watchlistService: widget.watchlistService,
                    onAddToWatchlist: (release) async {
                      final ws = widget.watchlistService;
                      if (ws == null) return;
                      final cs = CrunchyrollService();
                      final parsedCurrent = int.tryParse(release.episodeNumber) ?? 0;
                      final knownMax = await cs.getMaxEpisodeFromCache(release.seriesUrl, release.title);
                      final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;

                      final entry = WatchlistEntry(
                        animeId: release.seriesUrl,
                        title: release.title,
                        imageUrl: release.imageUrl,
                        episodesWatched: 0,
                        totalEpisodes: total,
                      );
                      ws.watchlist.addEntry(entry);
                      await ws.saveWatchlist();
                      cs.scheduleWatchlistEntryUpdate(ws, entry);
                      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Zur Watchlist hinzugefügt: ${release.title}')),
                      );
                      Navigator.of(ctx).pop();
                    },
                  ),
                );
              }
            },
          ),
          // Favorites removed (feature deprecated)
          IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'Watchlist',
            onPressed: () {
              if (widget.watchlistService == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WatchlistPage(service: widget.watchlistService!),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => _openSettings(),
          ),
        ],
        bottom: _isLoadingImages
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _imagesToLoad > 0
                      ? _imagesLoaded / _imagesToLoad
                      : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _forceRefresh,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
                            child: _isCalendarMinimized
                  ? InkWell(
                      onTap: () {
                        setState(() {
                          _isCalendarMinimized = false;
                          _cumulativeScrollDelta = 0.0;
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Kalender Icon
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.calendar_today,
                                size: 20,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Datum Informationen
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    () {
                                      final selected = _selectedDay ?? _focusedDay;
                                      return DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(selected);
                                    }(),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    () {
                                      final releases = _getReleasesForDay(_selectedDay ?? _focusedDay);
                                      if (releases.isEmpty) return 'Keine Releases';
                                      return '${releases.length} Release${releases.length == 1 ? '' : 's'}';
                                    }(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Expand Icon
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) {
                        _verticalDragDelta = 0.0;
                      },
                      onPointerMove: (event) {
                        // event.delta.dy: positive => moving down, negative => moving up
                        _verticalDragDelta += event.delta.dy;

                        if (_verticalDragDelta <= -_verticalDragThreshold) {
                          // swiped up enough -> more compact view
                          // subtract threshold so further movement can trigger again
                          _verticalDragDelta += _verticalDragThreshold;
                          _cycleCalendarFormat(up: true);
                        } else if (_verticalDragDelta >= _verticalDragThreshold) {
                          // swiped down enough -> more expanded view
                          _verticalDragDelta -= _verticalDragThreshold;
                          _cycleCalendarFormat(up: false);
                        }
                      },
                      onPointerUp: (_) {
                        _verticalDragDelta = 0.0;
                      },
                      onPointerCancel: (_) {
                        _verticalDragDelta = 0.0;
                      },
                      child: TableCalendar<AnimeRelease>(
                        locale: 'de_DE',
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: _focusedDay,
                        calendarFormat: _calendarFormat,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        selectedDayPredicate: (day) {
                          return isSameDay(_selectedDay, day);
                        },
                                                                        onDaySelected: (selectedDay, focusedDay) {
                          if (!isSameDay(_selectedDay, selectedDay)) {
                            // Bestimme Animationsrichtung basierend auf Datum-Differenz
                            final previous = _selectedDay ?? _focusedDay;
                            final diff = selectedDay.difference(previous).inDays;
                            if (diff > 0) {
                              // Späteres Datum ausgewählt -> von rechts reinschieben (swipe left)
                              _lastSwipeDirection = -1;
                            } else if (diff < 0) {
                              // Früheres Datum ausgewählt -> von links reinschieben (swipe right)
                              _lastSwipeDirection = 1;
                            }
                            
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                              _isLoadingReleases = true; // Zeige Ladeindikator während Wechsel
                            });
                            // Lade Releases für den neuen ausgewählten Tag
                            _loadReleases();
                          }
                        },
                        onFormatChanged: (format) {
                          if (_calendarFormat != format) {
                            setState(() {
                              _calendarFormat = format;
                            });
                            _saveCalendarFormat(format);
                          }
                        },
                        onPageChanged: (focusedDay) {
                          if (kDebugMode) print('onPageChanged: incoming focusedDay=$focusedDay, format=$_calendarFormat');
                          setState(() {
                            _focusedDay = focusedDay;
                          });
                          _loadReleases();
                        },
                        eventLoader: _getReleasesForDay,
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          formatButtonShowsNext: false,
                        ),
                        calendarBuilders: CalendarBuilders<AnimeRelease>(
                          markerBuilder: (context, date, events) {
                            if (events.isEmpty) return const SizedBox.shrink();
                            final color = Theme.of(context).colorScheme.primary;
                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  width: 22,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        availableCalendarFormats: const {
                          CalendarFormat.month: 'Monat',
                          CalendarFormat.twoWeeks: '2 Wochen',
                          CalendarFormat.week: 'Woche',
                        },
                      ),
                    ),
            ),
            const Divider(height: 1),
            // Immer die Liste anzeigen - kein Ladekreis mehr!
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    // Only consider vertical scrolling and when feature enabled
                    if (_autoMinimizeEnabled && notification.metrics.axis == Axis.vertical && (notification.scrollDelta ?? 0) != 0) {
                      // If already minimized, nothing to do; reset accumulator
                      if (_isCalendarMinimized) {
                        _cumulativeScrollDelta = 0.0;
                      } else {
                        // Accumulate absolute scroll distance (both up and down)
                        _cumulativeScrollDelta += (notification.scrollDelta ?? 0).abs();

                        if (_cumulativeScrollDelta >= _autoMinimizeScrollThreshold) {
                          // reached threshold — minimize and reset accumulator
                          _cumulativeScrollDelta = 0.0;
                          setState(() {
                            _isCalendarMinimized = true;
                          });
                        }
                      }
                    }
                  }
                  return false;
                },
                child: _buildReleaseList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildReleaseList() {
    // Zeige Ladeindikator während Releases geladen werden
    // Dies verhindert das kurze Aufblitzen von alten Daten
    if (_isLoadingReleases) {
      final dayKey = ValueKey('loading_${(_selectedDay ?? _focusedDay).toIso8601String()}');
      return SizedBox(
        key: dayKey,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Lade Releases…',
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

    final releases = _getReleasesForDay(_selectedDay ?? _focusedDay);

    Widget content;

    if (false) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Lade Releases…',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
        } else if (releases.isEmpty) {
      content = Container(
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
    } else {
            content = Container(
        color: Theme.of(context).colorScheme.surface,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          itemCount: releases.length,
          itemBuilder: (context, index) {
            final release = releases[index];
            return _buildReleaseCard(release);
          },
        ),
      );
    }

    // Wrap the content in a GestureDetector so horizontal swipes change the day.
    // Use AnimatedSwitcher + SlideTransition for a side-entry animation.
    final dayKey = ValueKey((_selectedDay ?? _focusedDay).toIso8601String());

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        if (_dragAnimationController.isAnimating) _dragAnimationController.stop();
        setState(() {
          _isDragging = true;
          // Start fresh for this gesture: reset offset and session anchors
          _dragOffset = 0.0;
          _dragStartDay = _selectedDay ?? _focusedDay;
          _dragSessionStartDay = _selectedDay ?? _focusedDay;
          // Reset commit flag for this new drag session
          _committedDuringDrag = false;
        });
      },
      onHorizontalDragCancel: () {
        // User aborted the swipe gesture — return to current page without committing
        if (_dragAnimationController.isAnimating) _dragAnimationController.stop();
        setState(() {
          _isDragging = false;
          _isSnapping = false;
          _dragOffset = 0.0;
          _committedDuringDrag = false;
        });
      },
      onHorizontalDragUpdate: (details) {
        // Simply track offset for visual preview during drag
        if (_isSnapping || _committedDuringDrag) return;
        setState(() {
          _dragOffset += details.delta.dx;
        });
      },
      onHorizontalDragEnd: (details) {
        // Skip if no meaningful drag happened (small accidental moves)
        if (_dragOffset.abs() < 100 && details.primaryVelocity!.abs() < _horizontalVelocityCommit) {
          if (kDebugMode) print('[SWIPE] Ignored: offset=${_dragOffset.toStringAsFixed(1)}, velocity=${details.primaryVelocity?.toStringAsFixed(1)}');
          setState(() {
            _isDragging = false;
            _dragOffset = 0.0;
            _committedDuringDrag = false;
          });
          return;
        }

        final velocity = details.primaryVelocity ?? 0.0;
        final width = context.size?.width ?? 0.0;

        if (width <= 0) return;

        // --- Vereinfachte Swipe-Commit-Logik ---
        double target = 0.0;
        bool shouldCommit = false;
        // Clamp current offset to screen bounds to avoid weird large offsets
        final double clampedOffset = _dragOffset.clamp(-width, width);
        // Use clampedOffset for decision-making and animation
        
        // Commit nur bei hoher Velocity UND mit Minimum-Offset (35%), oder bei Offset > 35%
        // WICHTIG: Velocity hat Vorzeichen! velocity < 0 = nach links swipen = nächster Tag = target < 0
        // Minimum offset to consider even with high velocity: same as normal threshold (35%)
        final double minOffsetForVelocityCommit = width * _horizontalCommitFraction;
        
        if (velocity.abs() > _horizontalVelocityCommit && clampedOffset.abs() >= minOffsetForVelocityCommit) {
          if (kDebugMode) print('[SWIPE] Commit by velocity: ${velocity.toStringAsFixed(1)} (sign=${velocity.sign}) + offset=${clampedOffset.toStringAsFixed(1)}');
          // velocity sign determines direction: negative = left (next), positive = right (prev)
          target = velocity < 0 ? -width : width;
          shouldCommit = true;
        } else if (clampedOffset.abs() > width * _horizontalCommitFraction) {
          if (kDebugMode) print('[SWIPE] Commit by offset: ${clampedOffset.toStringAsFixed(1)} / ${width.toStringAsFixed(1)}');
          // clampedOffset < 0 means dragged left (negative) = show next day (target = -width)
          target = clampedOffset < 0 ? -width : width;
          shouldCommit = true;
        } else {
          if (kDebugMode) print('[SWIPE] No commit: offset=${clampedOffset.toStringAsFixed(1)}, velocity=${velocity.toStringAsFixed(1)}');
          target = 0.0;
          shouldCommit = false;
        }

        _isSnapping = true;
        if (shouldCommit) _committedDuringDrag = true;

        // Remove old listeners from previous animation if still attached
        if (_currentSettleAnimation != null) {
          if (_currentSettleListener != null) {
            _currentSettleAnimation!.removeListener(_currentSettleListener!);
          }
          if (_currentStatusListener != null) {
            _currentSettleAnimation!.removeStatusListener(_currentStatusListener!);
          }
        }

        // Animationsdauer proportional zur verbleibenden Strecke, damit px/s konstant sind
        // Basis: volle Breite -> 260ms. Dauer = (distance / width) * baseDurationMs
        const int baseDurationMs = 260;
        final double distance = (target - clampedOffset).abs();
        final double full = width > 0 ? width : 1.0;
        int durationMs = ((distance / full) * baseDurationMs).round();
        // Clamp to avoid too short/long animations
        if (durationMs < 120) durationMs = 120;
        if (durationMs > 800) durationMs = 800;
        _dragAnimationController.duration = Duration(milliseconds: durationMs);
        if (kDebugMode) print('[SWIPE] Anim duration=${durationMs}ms distance=${distance.toStringAsFixed(1)} full=${full.toStringAsFixed(1)} clampedOffset=${clampedOffset.toStringAsFixed(1)} target=${target.toStringAsFixed(1)}');
        _dragAnimationController.reset();
        final Animation<double> settle = Tween<double>(begin: clampedOffset, end: target)
          .animate(CurvedAnimation(parent: _dragAnimationController, curve: Curves.easeOut));

        // Save animation and listeners for cleanup
        _currentSettleAnimation = settle;

        _currentSettleListener = () {
          setState(() {
            _dragOffset = settle.value;
          });
        };
        settle.addListener(_currentSettleListener!);

        _currentStatusListener = (status) {
          if (status == AnimationStatus.completed) {
            if (shouldCommit) {
              final base = _dragSessionStartDay ?? _selectedDay ?? _focusedDay;
              if (target < 0) {
                setState(() {
                  _lastSwipeDirection = -1;
                  _selectedDay = DateTime(base.year, base.month, base.day).add(const Duration(days: 1));
                  _focusedDay = _selectedDay!;
                });
              } else {
                setState(() {
                  _lastSwipeDirection = 1;
                  _selectedDay = DateTime(base.year, base.month, base.day).subtract(const Duration(days: 1));
                  _focusedDay = _selectedDay!;
                });
              }
              _loadReleases();
            }
            setState(() {
              _isDragging = false;
              _isSnapping = false;
              _dragOffset = 0.0;
              _committedDuringDrag = false;
            });
            // Clean up listeners
            if (_currentSettleListener != null) {
              settle.removeListener(_currentSettleListener!);
              _currentSettleListener = null;
            }
            if (_currentStatusListener != null) {
              settle.removeStatusListener(_currentStatusListener!);
              _currentStatusListener = null;
            }
            _currentSettleAnimation = null;
          }
        };
        settle.addStatusListener(_currentStatusListener!);

        _dragAnimationController.forward(from: 0.0);
      },
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;

        Widget currentChild = SizedBox(key: dayKey, child: content);

        if (!_isDragging && _dragOffset == 0.0) {
          // No active drag: show animated switcher (standard behavior)
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 520),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final isIncoming = child.key == dayKey;
              Offset incomingBegin = Offset.zero;
              if (_lastSwipeDirection == -1) incomingBegin = const Offset(1.0, 0.0);
              else if (_lastSwipeDirection == 1) incomingBegin = const Offset(-1.0, 0.0);

              if (isIncoming) {
                final tween = Tween<Offset>(begin: incomingBegin, end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut));
                return SlideTransition(position: animation.drive(tween), child: child);
              } else {
                final outgoingEnd = Offset(-incomingBegin.dx, 0.0);
                final tween = Tween<Offset>(begin: Offset.zero, end: outgoingEnd).chain(CurveTween(curve: Curves.easeInOut));
                return SlideTransition(position: animation.drive(tween), child: child);
              }
            },
            child: currentChild,
          );
        }

        // During drag: show current and adjacent day, each translated by _dragOffset
        final baseDay = _selectedDay ?? _focusedDay;
        final showingNext = _dragOffset < 0; // dragging left shows next day
        final adjacentDay = DateTime(baseDay.year, baseDay.month, baseDay.day).add(Duration(days: showingNext ? 1 : -1));
        final adjacentReleasesWidget = _buildContentForDay(adjacentDay);

        return Stack(children: [
          // Adjacent (incoming) -- positioned relative to drag
          Transform.translate(
            offset: Offset(_dragOffset + (showingNext ? width : -width), 0),
            child: SizedBox(width: width, child: adjacentReleasesWidget),
          ),
          // Current
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: SizedBox(width: width, child: currentChild),
          ),
        ]);
      }),
    );
  }

  Widget _buildReleaseCard(AnimeRelease release) {
    return _ReleaseCard(
      key: ValueKey('${release.title}_${release.episodeInfo}'),
      release: release,
      watchlistService: widget.watchlistService,
    );
  }
}

/// Stateful Widget für Release Card mit Favoriten-Status
class _ReleaseCard extends StatefulWidget {
  final AnimeRelease release;
  final WatchlistService? watchlistService;
  const _ReleaseCard({super.key, required this.release, this.watchlistService});

  @override
  State<_ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<_ReleaseCard> {
  bool _isFavorite = false;
  late final FavoritesRepository _favoritesRepository;
  // Watchlist state
  bool _isProcessingWatchlist = false;
  bool _isInWatchlist = false;
  bool _isInitialized = false; // Track if we've loaded the status
  static final Map<String, bool> _favoriteCache = {}; // In-memory cache to prevent flickering

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    
    // Höre auf globale Favoriten-Änderungen
    favoritesChangeNotifier.addListener(_onFavoritesChanged);
    
    // Check cache first for instant display
    if (_favoriteCache.containsKey(widget.release.title)) {
      _isFavorite = _favoriteCache[widget.release.title]!;
      _isInitialized = true;
    }
    
    // Load favorite status immediately
    _checkIfFavorite();

    // Initialize watchlist status if a service was provided
    _initWatchlistStatus();
    // Listen to watchlist changes so the card updates immediately
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.addListener(_onWatchlistChanged);
    }
  }

  Future<void> _initWatchlistStatus() async {
    if (widget.watchlistService == null) return;
    try {
      final exists = widget.watchlistService!.watchlist.entries
          .any((e) => e.animeId == widget.release.seriesUrl);
      if (mounted) {
        setState(() {
          _isInWatchlist = exists;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing watchlist status: $e');
    }
  }

  @override
  void dispose() {
    favoritesChangeNotifier.removeListener(_onFavoritesChanged);
    if (widget.watchlistService != null) {
      widget.watchlistService!.watchlist.removeListener(_onWatchlistChanged);
    }
    super.dispose();
  }

  void _onWatchlistChanged() {
    if (widget.watchlistService == null) return;
    try {
      final exists = widget.watchlistService!.watchlist.entries
          .any((e) => e.animeId == widget.release.seriesUrl);
      if (mounted) {
        setState(() {
          _isInWatchlist = exists;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error handling watchlist change: $e');
    }
  }

  void _onFavoritesChanged() {
    // Lade Status neu wenn sich Favoriten ändern
    _checkIfFavorite();
  }

  Future<void> _checkIfFavorite() async {
    try {
      final isFav = await _favoritesRepository.isFavorite(widget.release.title);
      // Update cache
      _favoriteCache[widget.release.title] = isFav;
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
          _isInitialized = true; // Mark as initialized to prevent white flash
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking favorite: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true; // Mark as initialized even on error
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    // Speichere den ALTEN Zustand vor dem optimistischen Update
    final wasAlreadyFavorite = _isFavorite;
    
    // Optimistisches UI Update
    setState(() {
      _isFavorite = !_isFavorite;
    });
    
    try {
      if (wasAlreadyFavorite) {
        // War favorisiert → jetzt entfernen
        await _favoritesRepository.removeFavorite(widget.release.title);
        _favoriteCache[widget.release.title] = false; // Update cache
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Aus Favoriten entfernt'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        // War nicht favorisiert → jetzt hinzufügen
        final favorite = FavoriteAnime(
          title: widget.release.title,
          imageUrl: widget.release.imageUrl,
          seriesUrl: widget.release.seriesUrl,
          addedDate: DateTime.now(),
        );
        await _favoritesRepository.addFavorite(favorite);
        _favoriteCache[widget.release.title] = true; // Update cache
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❤️ Zu Favoriten hinzugefügt'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
      
      // Benachrichtige alle anderen Cards über die Änderung
      favoritesChangeNotifier.value++;
      
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling favorite: $e');
      // Bei Fehler zurücksetzen
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
    // Mark as seen (generate content-hash and store)
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
          onAddToWatchlist: (release) async {
            final ws = widget.watchlistService;
            if (ws == null) return;
            setState(() { _isProcessingWatchlist = true; });
              try {
              final cs = CrunchyrollService();
              final parsedCurrent = int.tryParse(release.episodeNumber) ?? 0;
              final knownMax = await cs.getMaxEpisodeFromCache(release.seriesUrl, release.title);
              final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;

              final entry = WatchlistEntry(
                animeId: release.seriesUrl,
                title: release.title,
                imageUrl: release.imageUrl,
                episodesWatched: 0,
                totalEpisodes: total,
              );
              ws.watchlist.addEntry(entry);
              await ws.saveWatchlist();
              cs.scheduleWatchlistEntryUpdate(ws, entry);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${release.title} zur Watchlist hinzugefügt')),
              );
              setState(() { _isInWatchlist = true; });
            } catch (e) {
              if (kDebugMode) print('❌ Error adding to watchlist: $e');
            } finally {
              if (mounted) setState(() { _isProcessingWatchlist = false; });
            }
            Navigator.of(context).pop();
          },
        );
      },
    );

    // Nach dem Schließen des Dialogs, Status neu laden
    _checkIfFavorite();
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
            // Anime Thumbnail
            Stack(
              children: [
                // Zeige Bild wenn vorhanden, sonst Placeholder
                if (widget.release.imageUrl != null && widget.release.imageUrl!.isNotEmpty)
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
                // Favoriten-Button (oben links)
                // Favorite icon removed from anime overview
                // Watchlist-Button (oben links, neben Favorit)
                // Hidden when the anime is already in the watchlist
                // Favorite (heart) button on cover (former favorites position)
                Positioned(
                  top: 8,
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 20,
                    child: _isInitialized
                        ? (_isProcessingWatchlist
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
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${widget.release.title} aus Watchlist entfernt')),
                                        );
                                      } else {
                                        if (mounted) setState(() { _isProcessingWatchlist = false; });
                                        return;
                                      }
                                    } else {
                                      final cs = CrunchyrollService();
                                      final parsedCurrent = int.tryParse(widget.release.episodeNumber) ?? 0;
                                      final knownMax = await cs.getMaxEpisodeFromCache(id, widget.release.title);
                                      final total = (knownMax != null && knownMax > parsedCurrent) ? knownMax : parsedCurrent;
                                      final entry = WatchlistEntry(
                                        animeId: id,
                                        title: widget.release.title,
                                        imageUrl: widget.release.imageUrl,
                                        episodesWatched: 0,
                                        totalEpisodes: total,
                                        addedAt: DateTime.now(),
                                      );
                                      ws.watchlist.addEntry(entry);
                                      await ws.saveWatchlist();
                                      cs.scheduleWatchlistEntryUpdate(ws, entry);
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('${widget.release.title} zur Watchlist hinzugefügt')),
                                      );
                                    }
                                    if (mounted) setState(() {
                                      _isProcessingWatchlist = false;
                                      _isInWatchlist = !exists;
                                    });
                                  } catch (e) {
                                    if (kDebugMode) print('❌ Error toggling watchlist from card: $e');
                                    if (mounted) setState(() { _isProcessingWatchlist = false; });
                                  }
                                },
                                padding: EdgeInsets.zero,
                              ))
                        : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            ),
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
                // Release Time Badge
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

            // Anime Info
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
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
          // Anime-style Pattern
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: CustomPaint(painter: _AnimePatternPainter()),
            ),
          ),
          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // TV/Play Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.live_tv,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                // Text
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
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

// Custom Painter für Anime-ähnliches Muster
class _AnimePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Zeichne stilisierte "Speed Lines" wie in Anime
    for (int i = 0; i < 8; i++) {
      final startX = size.width * (i / 8);
      final startY = 0.0;
      final endX = size.width * ((i + 2) / 8);
      final endY = size.height;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    // Zeichne einige Kreise (wie Anime-Highlights)
    paint.style = PaintingStyle.fill;
    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.2 + i * 0.15);
      final y = size.height * (0.3 + (i % 2) * 0.4);
      canvas.drawCircle(Offset(x, y), 4 + (i % 3) * 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Dialog Widget für Anime-Details mit asynchronem Laden der Beschreibung
class _AnimeDetailsDialog extends StatefulWidget {
  final AnimeRelease release;
  final CrunchyrollService crunchyrollService;
  final void Function(AnimeRelease release)? onAddToWatchlist;
  final WatchlistService? watchlistService;

  const _AnimeDetailsDialog({
    required this.release,
    required this.crunchyrollService,
    this.onAddToWatchlist,
    this.watchlistService,
  });

  @override
  State<_AnimeDetailsDialog> createState() => _AnimeDetailsDialogState();
}

class _AnimeDetailsDialogState extends State<_AnimeDetailsDialog> {
  String? _descriptionOriginal; // Englische Original-Beschreibung
  String? _descriptionTranslated; // Deutsche Übersetzung
  bool _isLoadingDescription = true;
  bool _isTranslating = false;
  bool _showGerman = true; // Zeige standardmäßig Deutsch
  bool _autoTranslateEnabled = true; // Steuert, ob der Sprach-Button angezeigt wird
  bool _isFavorite = false; // Track Favoriten-Status
  bool _isLoadingFavorite = true; // Loading State für Favoriten
  final _translator = GoogleTranslator();
  late final FavoritesRepository _favoritesRepository;
  bool _isInWatchlist = false;
  bool _isProcessingWatchlist = false;

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    _loadDescription();
    _checkIfFavorite();
    _updateWatchlistState();
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
        // Aus Favoriten entfernen
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
      } else {
        // Zu Favoriten hinzufügen
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
      // Alle anderen Cards benachrichtigen
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
    final description = await widget.crunchyrollService.fetchDescription(
      widget.release,
    );
    if (mounted) {
      setState(() {
        _descriptionOriginal = description;
        _isLoadingDescription = false;
      });
      // Automatisch übersetzen nur wenn Setting aktiviert ist
      final autoTranslate = await AppSettings.getAutoTranslate();
      _autoTranslateEnabled = autoTranslate;
      if (autoTranslate) {
        _translateDescription();
      } else {
        setState(() {
          _showGerman = false; // Zeige Original wenn Auto-Translate deaktiviert
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
                // Header mit Bild
                Stack(
                  children: [
                    if (release.imageUrl != null &&
                        release.imageUrl!.isNotEmpty)
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
                    // Favorite button removed from popup/overview
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
                    // Premiere Badge — position bottom-right of the cover
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
                        release.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Episode Info
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              release.episodeInfo,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
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

                      // Button: Crunchyroll
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
      ));
  }
}
