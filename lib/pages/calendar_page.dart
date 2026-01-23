import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import '../models/anime_release.dart';
import '../models/watchlist.dart';
import '../models/notification_log.dart';
import '../services/crunchyroll_service.dart';
import '../services/watchlist_service.dart';
import '../services/anilist_service.dart';
import '../services/anilist_cache.dart';
import '../services/next_episode_predictor.dart';
import '../services/prediction_notifier.dart';
import '../services/permission_service.dart';
import '../services/battery_optimization_service.dart';
import '../repositories/seen_repository.dart';
import '../utils/title_utils.dart';
import '../settings.dart';
import '../widgets/anime_details_dialog.dart';
import '../widgets/release_card.dart';
import 'search_page.dart';
import 'watchlist_page.dart';
import 'settings_page.dart';

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

    // Listen for externally persisted predictions (AniList forecast page)
    try {
      // Listen for prediction changes: reload service cache then refresh UI
      // Use a flag to prevent recursive loops
      bool _isHandlingPredictionUpdate = false;
      predictionsUpdated.addListener(() {
        if (!predictionsUpdated.value) return;
        if (_isHandlingPredictionUpdate) {
          if (kDebugMode) print('⚠️ Predictions update already in progress, skipping recursive call');
          predictionsUpdated.value = false;
          return;
        }
        if (kDebugMode) print('🔔 Predictions updated -> reloading cache and calendar');
        if (!mounted) {
          predictionsUpdated.value = false;
          return;
        }
        _isHandlingPredictionUpdate = true;
        // Ensure the CalendarPage's CrunchyrollService reloads its in-memory cache from prefs
        _crunchyrollService.loadCacheOnStartup().whenComplete(() async {
          if (mounted) {
            setState(() {
              _releases.clear();
              _isLoadingReleases = true;
            });
            await _loadReleases();
          }
          // reset notifier after handling
          predictionsUpdated.value = false;
          _isHandlingPredictionUpdate = false;
        });
      });
    } catch (e) {
      if (kDebugMode) print('Error registering predictionsUpdated listener: $e');
    }

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
      // Wenn Vorhersage aktiv ist, direkt einmal ausführen (nicht blockierend)
      // NUR für Watchlist-Einträge, nicht alle bekannten Serien
      AppSettings.getPredictionEnabled().then((enabled) async {
        if (enabled && widget.watchlistService != null) {
          // First, wait for watchlist to load
          await widget.watchlistService!.loadWatchlist();
          
          // If watchlist is empty, CLEAR all predictions (ghost cleanup)
          if (widget.watchlistService!.watchlist.entries.isEmpty) {
            if (kDebugMode) print('🧹 Watchlist is empty - clearing all stale predictions');
            await _crunchyrollService.removeAllPredictedReleases();
            if (mounted) _loadReleases();
          } else {
            // Generate forecasts for non-empty watchlist
            widget.watchlistService!.generateForecastForAllEntries().whenComplete(() {
              if (mounted) _loadReleases();
            });
          }
        }
      });
    });

    // Starte automatische Updates alle 5 Minuten
    _crunchyrollService.startAutoUpdate(() async {
      if (mounted) {
        await _loadReleases();
      }
      // Nach jedem Auto-Update: optional Predictor ausführen und danach neu laden
      // NUR für Watchlist-Einträge
      try {
        final enabled = await AppSettings.getPredictionEnabled();
        if (enabled && widget.watchlistService != null) {
          await widget.watchlistService!.generateForecastForAllEntries();
          if (mounted) await _loadReleases();
        }
      } catch (e) {
        if (kDebugMode) print('Error running predictor on auto-update: $e');
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
      final now = DateTime.now();
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

      // Merge predicted releases from month cache for the focused month so they appear immediately
      try {
        final predictionEnabled = await AppSettings.getPredictionEnabled();
        if (predictionEnabled) {
          final todayMidnight = DateTime(now.year, now.month, now.day);
          final horizonMidnight = todayMidnight.add(const Duration(days: 7));
          
          final monthDate = DateTime(_focusedDay.year, _focusedDay.month, 1);
          final cachedMonth = await _crunchyrollService.getReleasesForMonthFromCache(monthDate);
          
          for (final pred in cachedMonth.where((r) => r.isPredicted)) {
            final releaseDay = DateTime(pred.releaseTime.year, pred.releaseTime.month, pred.releaseTime.day);
            if (releaseDay.isAfter(horizonMidnight)) continue;

            final date = DateTime(pred.releaseTime.year, pred.releaseTime.month, pred.releaseTime.day);
            releasesByDay.putIfAbsent(date, () => []);
            final exists = releasesByDay[date]!.any((r) => r.title == pred.title && r.episodeNumber == pred.episodeNumber && r.releaseTime == pred.releaseTime);
            if (!exists) releasesByDay[date]!.add(pred);
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error merging predicted releases into manual refresh results: $e');
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

      // Respect prediction toggle and 7-day window limit
      final predictionEnabled = await AppSettings.getPredictionEnabled();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final horizonMidnight = todayMidnight.add(const Duration(days: 7));
      
      final filtered = <DateTime, List<AnimeRelease>>{};
      finalByDay.forEach((date, list) {
        final kept = list.where((r) {
          if (!r.isPredicted) return true;
          if (!predictionEnabled) return false;
          final releaseDay = DateTime(r.releaseTime.year, r.releaseTime.month, r.releaseTime.day);
          return !releaseDay.isAfter(horizonMidnight);
        }).toList();
        if (kept.isNotEmpty) filtered[date] = kept;
      });
      finalByDay = filtered;

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
      final now = DateTime.now();
      final predictionEnabled = await AppSettings.getPredictionEnabled();
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
            // Respect prediction toggle and 7-day window limit
            final todayMidnight = DateTime(now.year, now.month, now.day);
            final horizonMidnight = todayMidnight.add(const Duration(days: 7));
            
            final releaseDay = DateTime(release.releaseTime.year, release.releaseTime.month, release.releaseTime.day);
            if (!release.isPredicted || (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              // Verhindere Duplikate
              if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
                _releases[date]!.add(release);
              }
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
            final todayMidnight = DateTime(now.year, now.month, now.day);
            final horizonMidnight = todayMidnight.add(const Duration(days: 7));
            final releaseDay = DateTime(release.releaseTime.year, release.releaseTime.month, release.releaseTime.day);
            if (!release.isPredicted || (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
                _releases[date]!.add(release);
              }
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
      // Clear only predicted releases cache so real releases remain cached
      await _crunchyrollService.removeAllPredictedReleases();
      // Übergebe den angezeigten Monat für den Refresh
      final releases = await _crunchyrollService.forceRefresh(forMonth: _focusedDay);

      // Rebuild predictions: use ONLY watchlist entries for predictions (single call, no duplicates)
      try {
        final ws = widget.watchlistService;
        if (ws != null && ws.watchlist.entries.isNotEmpty) {
          if (kDebugMode) print('🔮 Manual refresh: rebuilding predictions for watchlist...');
          await ws.generateForecastForAllEntries();
          if (kDebugMode) print('✅ Manual refresh: predictions complete');
        } else {
          if (kDebugMode) print('🔮 Manual refresh: watchlist empty, skipping predictions');
        }
      } catch (e) {
        if (kDebugMode) print('Error running watchlist-based predictor during manual refresh: $e');
      }

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
    final list = _releases[date];
    if (list == null || list.isEmpty) return [];

    // ROBUSTER CUTOFF: Vorhersagen auf heute + 7 Tage begrenzen
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final horizonMidnight = todayMidnight.add(const Duration(days: 7));
    
    return list.where((r) {
      if (!r.isPredicted) return true;
      final releaseDay = DateTime(r.releaseTime.year, r.releaseTime.month, r.releaseTime.day);
      // Wenn der Tag des Releases NACH dem Horizont liegt -> ausblenden
      return !releaseDay.isAfter(horizonMidnight);
    }).toList();
  }

  Widget _buildContentForDay(DateTime day, {bool previewOnly = false}) {
    var releases = _getReleasesForDay(day);

    // If previewOnly is requested and a WatchlistService was provided, filter
    // releases to only those present in the user's watchlist (match by seriesUrl).
    if (previewOnly && widget.watchlistService != null) {
      final wl = widget.watchlistService!.watchlist.entries;
      final ids = wl.map((e) => e.animeId).toSet();
      releases = releases.where((r) => ids.contains(r.seriesUrl)).toList();
    }

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
      final predictionEnabled = await AppSettings.getPredictionEnabled();
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
            
            // Respect prediction toggle and 7-day window limit
            final todayMidnight = DateTime(now.year, now.month, now.day);
            final horizonMidnight = todayMidnight.add(const Duration(days: 7));
            final releaseDay = DateTime(release.releaseTime.year, release.releaseTime.month, release.releaseTime.day);
            
            if (!release.isPredicted || (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              if (!_releases[date]!.any((r) => r.title == release.title && r.episodeNumber == release.episodeNumber)) {
                _releases[date]!.add(release);
              }
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
            // Ensure service cache is reloaded from prefs (matching manual refresh behavior)
            _crunchyrollService.loadCacheOnStartup().whenComplete(() async {
              // Direkt Releases neu laden (z.B. nach Aktivieren von "Doppelte Releases ausblenden")
              await _loadReleases();
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
            });
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
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

                      // Auto-link integration
                      int? autoId;
                      try {
                        final best = await AnilistService().findBestMatch(release.title);
                        if (best != null) {
                          autoId = best.id;
                          if (kDebugMode) print('✅ Auto-linked "${release.title}" to AniList ID: $autoId');
                          
                          // Save to cache so predictor can find it
                          final cache = AnilistCache();
                          final key = normalizeTitle(release.seriesUrl ?? release.title);
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
                      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Zur Watchlist hinzugefügt: ${release.title}${autoId != null ? " (Verknüpft)" : ""}')),
                      );
                      
                      // Trigger prediction refresh if auto-linked
                      if (autoId != null) {
                         try {
                            final predictor = NextEpisodePredictor(cs, AnilistService());
                            await predictor.predictNextForSeries(entry.animeId, entry.title);
                         } catch (_) {}
                      }
                      
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

                            final hasPrediction = events.any((e) => e.isPredicted);

                            return Stack(
                              children: [
                                Align(
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
                                ),
                                // Prediction badge restored per user request
                                if (hasPrediction)
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 6, right: 6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade700,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'V',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
              child: Container(
                padding: const EdgeInsets.all(16),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Lade Releases…',
                style: TextStyle(fontSize: 16, color: Colors.grey),
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
        final adjacentReleasesWidget = _buildContentForDay(adjacentDay, previewOnly: true);

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
    return ReleaseCard(
      key: ValueKey('${release.title}_${release.episodeInfo}'),
      release: release,
      watchlistService: widget.watchlistService,
    );
  }
}
