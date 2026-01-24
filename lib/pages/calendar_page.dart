import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import '../models/anime_release.dart';
import '../models/notification_log.dart';
import '../services/crunchyroll_service.dart';
import '../services/watchlist_service.dart';
import '../services/prediction_notifier.dart';
import '../services/permission_service.dart';
import '../services/battery_optimization_service.dart';
import '../repositories/seen_repository.dart';
import '../services/app_settings_service.dart';
import '../utils/ui_utils.dart';
import '../widgets/calendar_app_bar.dart';
import '../widgets/calendar_display.dart';
import '../widgets/calendar_release_list.dart';
import 'settings_page.dart';

class CalendarPage extends StatefulWidget {
  final VoidCallback? onAccentColorChanged;
  final WatchlistService? watchlistService;

  const CalendarPage({
    super.key,
    this.onAccentColorChanged,
    this.watchlistService,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with TickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();

  DateTime? _selectedDay;
  // -1 = swiped left (next day), 1 = swiped right (previous day)
  int _lastSwipeDirection = 0;
  // Drag state for interactive swipe preview
  double _dragOffset =
      0.0; // pixels, positive = dragging right (show previous), negative = left (show next)
  bool _isDragging = false;
  bool _isSnapping = false;
  late AnimationController _dragAnimationController;
  Animation<double>?
  _currentSettleAnimation; // Track current animation to remove listeners
  VoidCallback? _currentSettleListener; // Track the setState listener
  Function(AnimationStatus)?
  _currentStatusListener; // Track the status listener
  DateTime? _dragSessionStartDay;
  // Wenn während des Drags bereits ein Seitenwechsel ausgeführt wurde,
  // verhindern wir beim Drag-Ende ein zweites Commit.
  bool _committedDuringDrag = false;
  Map<DateTime, List<AnimeRelease>> _releases = {};
  final CrunchyrollService _crunchyrollService = CrunchyrollService();
  bool _isLoadingReleases = false;
  // Image loading state tracked via CrunchyrollService callbacks
  bool _isLoadingImages = false;
  int _imagesLoaded = 0;
  int _imagesToLoad = 0;
  // Indicates whether the persistent cache has been loaded into memory
  bool _cacheLoaded = false;
  // Horizontal commit thresholds for day swipe
  // Fraction of width that must be dragged to commit (35% requested)
  final double _horizontalCommitFraction = 0.35;
  // Minimum velocity (px/s) to force a commit regardless of distance
  final double _horizontalVelocityCommit = 900.0;
  // Wenn true: Kalender ist minimiert und zeigt nur den Header (Monat + chevrons)
  bool _isCalendarMinimized = false;
  // Show calendar only after first frame to avoid package lifecycle race
  bool _showCalendar = false;

  @override
  void initState() {
    super.initState();

    // ✅ FIX: Controller direkt am Anfang initialisieren
    _dragAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _selectedDay = _focusedDay;
    _loadCalendarFormat();
    _loadAutoMinimizeSetting();

    // Berechtigungen nach dem ersten Frame anfragen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
      // Show the TableCalendar after first frame to avoid PageController race
      if (mounted) setState(() => _showCalendar = true);
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
      bool isHandlingPredictionUpdate = false;
      predictionsUpdated.addListener(() {
        if (!predictionsUpdated.value) {
          return;
        }
        if (isHandlingPredictionUpdate) {
          if (kDebugMode) {
            print(
              '⚠️ Predictions update already in progress, skipping recursive call',
            );
          }
          predictionsUpdated.value = false;
          return;
        }
        if (kDebugMode) {
          print('🔔 Predictions updated -> reloading cache and calendar');
        }
        if (!mounted) {
          predictionsUpdated.value = false;
          return;
        }
        isHandlingPredictionUpdate = true;
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
          isHandlingPredictionUpdate = false;
        });
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error registering predictionsUpdated listener: $e');
      }
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
      AppSettingsService.getPredictionEnabled().then((enabled) async {
        if (enabled && widget.watchlistService != null) {
          // First, wait for watchlist to load
          await widget.watchlistService!.loadWatchlist();

          // If watchlist is empty, CLEAR all predictions (ghost cleanup)
          if (widget.watchlistService!.watchlist.entries.isEmpty) {
            if (kDebugMode) {
              print('🧹 Watchlist is empty - clearing all stale predictions');
            }
            await _crunchyrollService.removeAllPredictedReleases();
            if (mounted) {
              _loadReleases();
            }
          } else {
            // Generate forecasts for non-empty watchlist
            widget.watchlistService!
                .generateForecastForAllEntries()
                .whenComplete(() {
                  if (mounted) {
                    _loadReleases();
                  }
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
        final enabled = await AppSettingsService.getPredictionEnabled();
        if (enabled && widget.watchlistService != null) {
          await widget.watchlistService!.generateForecastForAllEntries();
          if (mounted) await _loadReleases();
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error running predictor on auto-update: $e');
        }
      }
    });

  }

  Future<void> _loadAutoMinimizeSetting() async {
    try {
      final enabled = await AppSettingsService.getAutoMinimizeCalendar();
      final threshold =
          await AppSettingsService.getAutoMinimizeScrollThreshold();
      if (mounted) {
        setState(() {
          _isCalendarMinimized =
              _isCalendarMinimized; // keep current minimized state
        });
      }
      // store locally for quick checks
      _autoMinimizeEnabled = enabled;
      _autoMinimizeScrollThreshold = threshold;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading auto-minimize setting: $e');
      }
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
      if (currentIndex < formats.length - 1) {
        newIndex = currentIndex + 1;
      }
    } else {
      if (currentIndex > 0) {
        newIndex = currentIndex - 1;
      }
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
          await BatteryOptimizationService.showBatteryOptimizationDialog(
            context,
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Fehler beim Anfragen der Berechtigungen: $e');
      }
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

      if (kDebugMode) {
        print(
          'Loading releases for: ${dateToLoad.day}.${dateToLoad.month}.${dateToLoad.year}',
        );
      }

      final releases = await _crunchyrollService.getReleasesForWeek(dateToLoad);

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
        final predictionEnabled =
            await AppSettingsService.getPredictionEnabled();
        if (predictionEnabled) {
          final todayMidnight = DateTime(now.year, now.month, now.day);
          final horizonMidnight = todayMidnight.add(const Duration(days: 7));

          final monthDate = DateTime(_focusedDay.year, _focusedDay.month, 1);
          final cachedMonth = await _crunchyrollService
              .getReleasesForMonthFromCache(monthDate);

          for (final pred in cachedMonth.where((r) => r.isPredicted)) {
            final releaseDay = DateTime(
              pred.releaseTime.year,
              pred.releaseTime.month,
              pred.releaseTime.day,
            );
            if (releaseDay.isAfter(horizonMidnight)) {
              continue;
            }

            final date = DateTime(
              pred.releaseTime.year,
              pred.releaseTime.month,
              pred.releaseTime.day,
            );
            releasesByDay.putIfAbsent(date, () => []);
            final exists = releasesByDay[date]!.any(
              (r) =>
                  r.title == pred.title &&
                  r.episodeNumber == pred.episodeNumber &&
                  r.releaseTime == pred.releaseTime,
            );
            if (!exists) {
              releasesByDay[date]!.add(pred);
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print(
            'Error merging predicted releases into manual refresh results: $e',
          );
        }
      }

      // Optionally remove duplicate releases (same episode URL or same title+episode)
      final hideDup = await AppSettingsService.getHideDuplicateReleases();
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
            final urlPart = (r.episodeUrl.isNotEmpty)
                ? normalizeUrl(r.episodeUrl)
                : '';
            final titlePart =
                '${r.title.trim().toLowerCase()}_${r.episodeNumber.trim().toLowerCase()}';
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
      final predictionEnabled = await AppSettingsService.getPredictionEnabled();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final horizonMidnight = todayMidnight.add(const Duration(days: 7));

      final filtered = <DateTime, List<AnimeRelease>>{};
      finalByDay.forEach((date, list) {
        final kept = list.where((r) {
          if (!r.isPredicted) {
            return true;
          }
          if (!predictionEnabled) {
            return false;
          }
          final releaseDay = DateTime(
            r.releaseTime.year,
            r.releaseTime.month,
            r.releaseTime.day,
          );
          return !releaseDay.isAfter(horizonMidnight);
        }).toList();
        if (kept.isNotEmpty) {
          filtered[date] = kept;
        }
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
    } finally {
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
      final predictionEnabled = await AppSettingsService.getPredictionEnabled();
      // Vormonat laden
      final previousMonth = DateTime(
        referenceDate.year,
        referenceDate.month - 1,
        1,
      );
      if (kDebugMode)
        print(
          '📅 Preloading previous month: ${previousMonth.month}/${previousMonth.year}',
        );
      final previousMonthReleases = await _crunchyrollService
          .getReleasesForWeek(previousMonth);

      // Nächster Monat laden
      final nextMonth = DateTime(
        referenceDate.year,
        referenceDate.month + 1,
        1,
      );
      if (kDebugMode)
        print('📅 Preloading next month: ${nextMonth.month}/${nextMonth.year}');
      final nextMonthReleases = await _crunchyrollService.getReleasesForWeek(
        nextMonth,
      );

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

            final releaseDay = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );
            if (!release.isPredicted ||
                (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              // Verhindere Duplikate
              if (!_releases[date]!.any(
                (r) =>
                    r.title == release.title &&
                    r.episodeNumber == release.episodeNumber,
              )) {
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
            final releaseDay = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );
            if (!release.isPredicted ||
                (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              if (!_releases[date]!.any(
                (r) =>
                    r.title == release.title &&
                    r.episodeNumber == release.episodeNumber,
              )) {
                _releases[date]!.add(release);
              }
            }
          }
        });
      }

      if (kDebugMode) {
        print('✓ Adjacent months preloaded and added to calendar');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error preloading adjacent months: $e');
      }
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

    if (kDebugMode) {
      print(
        '🧊 Freeze check: monthStart=${monthStart.month}/${monthStart.year}, twoMonthsAgo=${twoMonthsAgo.month}/${twoMonthsAgo.year}, isBefore=${monthStart.isBefore(twoMonthsAgo)}',
      );
    }

    if (monthStart.isBefore(twoMonthsAgo)) {
      // Monat ist eingeforen - Refresh nicht erlaubt
      _showFrozenMonthMessage();
      return;
    }

    try {
      // Clear only predicted releases cache so real releases remain cached
      await _crunchyrollService.removeAllPredictedReleases();
      // Übergebe den angezeigten Monat für den Refresh
      final releases = await _crunchyrollService.forceRefresh(
        forMonth: _focusedDay,
      );

      // Rebuild predictions: use ONLY watchlist entries for predictions (single call, no duplicates)
      try {
        final ws = widget.watchlistService;
        if (ws != null && ws.watchlist.entries.isNotEmpty) {
          if (kDebugMode)
            print('🔮 Manual refresh: rebuilding predictions for watchlist...');
          await ws.generateForecastForAllEntries();
          if (kDebugMode) {
            print('✅ Manual refresh: predictions complete');
          }
        } else {
          if (kDebugMode) {
            print('🔮 Manual refresh: watchlist empty, skipping predictions');
          }
        }
      } catch (e) {
        if (kDebugMode)
          print(
            'Error running watchlist-based predictor during manual refresh: $e',
          );
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
      final hideDup = await AppSettingsService.getHideDuplicateReleases();
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
            final urlPart = (r.episodeUrl.isNotEmpty)
                ? normalizeUrl(r.episodeUrl)
                : '';
            final titlePart =
                '${r.title.trim().toLowerCase()}_${r.episodeNumber.trim().toLowerCase()}';
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
      if (kDebugMode) {
        print('Error during force refresh: $e');
      }
    }
  }

  /// Zeigt eine Meldung an, dass die Einträge aktualisiert wurden
  Future<void> _showRefreshSuccessMessage() async {
    if (mounted) {
      UIUtils.showSnackBar(
        context,
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
    if (!mounted) {
      return;
    }

    // remove any existing overlay
    _topDateOverlay?.remove();
    _topDateOverlay = null;

    final overlay = Overlay.of(context);
    if (overlay == null) {
      return;
    }

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
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
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
    UIUtils.showSnackBar(
      context,
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
    if (list == null || list.isEmpty) {
      return [];
    }

    // ROBUSTER CUTOFF: Vorhersagen auf heute + 7 Tage begrenzen
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final horizonMidnight = todayMidnight.add(const Duration(days: 7));

    return list.where((r) {
      if (!r.isPredicted) {
        return true;
      }
      final releaseDay = DateTime(
        r.releaseTime.year,
        r.releaseTime.month,
        r.releaseTime.day,
      );
      // Wenn der Tag des Releases NACH dem Horizont liegt -> ausblenden
      return !releaseDay.isAfter(horizonMidnight);
    }).toList();
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

      final prevYr = now.month <= 1 ? now.year - 1 : now.year;
      final prevMo = now.month - 1 <= 0 ? 12 : now.month - 1;
      final previousMonth = (prevYr, prevMo);

      final nextYr = now.month >= 12 ? now.year + 1 : now.year;
      final nextMo = now.month + 1 > 12 ? 1 : now.month + 1;
      final nextMonth = (nextYr, nextMo);

      // Filter: nur Monate laden die noch nicht geladen wurden
      final otherMonths = cachedMonths
          .where(
            (month) =>
                !(month == currentMonth ||
                    month == previousMonth ||
                    month == nextMonth),
          )
          .toList();

      if (kDebugMode)
        print(
          'Loading ${otherMonths.length} additional months sequentially...',
        );

      // Lade nacheinander SEQUENZIELL, nicht parallel
      final predictionEnabled = await AppSettingsService.getPredictionEnabled();
      for (var (year, month) in otherMonths) {
        final dateInMonth = DateTime(year, month, 1);
        if (kDebugMode) {
          print('📥 Loading cached month: $month/$year');
        }
        final releases = await _crunchyrollService.getReleasesForMonthFromCache(
          dateInMonth,
        );

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
            final releaseDay = DateTime(
              release.releaseTime.year,
              release.releaseTime.month,
              release.releaseTime.day,
            );

            if (!release.isPredicted ||
                (predictionEnabled && !releaseDay.isAfter(horizonMidnight))) {
              if (!_releases[date]!.any(
                (r) =>
                    r.title == release.title &&
                    r.episodeNumber == release.episodeNumber,
              )) {
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

      if (kDebugMode)
        print(
          '✓ Loaded ${_releases.length} days with anime releases from cache',
        );
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
      appBar: CalendarAppBar(
        releases: _releases,
        watchlistService: widget.watchlistService,
        isLoadingImages: _isLoadingImages,
        imagesLoaded: _imagesLoaded,
        imagesToLoad: _imagesToLoad,
        onOpenSettings: _openSettings,
        onRefresh: _forceRefresh,
      ),
      body: RefreshIndicator(
        onRefresh: _forceRefresh,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _showCalendar
                  ? CalendarDisplay(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                calendarFormat: _calendarFormat,
                isCalendarMinimized: _isCalendarMinimized,
                eventLoader: _getReleasesForDay,
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    final previous = _selectedDay ?? _focusedDay;
                    final diff = selectedDay.difference(previous).inDays;
                    if (diff > 0) {
                      _lastSwipeDirection = -1;
                    } else if (diff < 0) {
                      _lastSwipeDirection = 1;
                    }

                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                      _isLoadingReleases = true;
                    });
                    _loadReleases();
                  }
                },
                onFormatChanged: (format) {
                  if (_calendarFormat != format) {
                    setState(() => _calendarFormat = format);
                    _saveCalendarFormat(format);
                  }
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                  _loadReleases();
                },
                onExpand: () {
                  setState(() {
                    _isCalendarMinimized = false;
                    _cumulativeScrollDelta = 0.0;
                  });
                },
                onCycleFormat: ({required bool up}) =>
                    _cycleCalendarFormat(up: up),
                  )
                  : const SizedBox.shrink(),
            ),
            const Divider(height: 1),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    if (_autoMinimizeEnabled &&
                        notification.metrics.axis == Axis.vertical &&
                        (notification.scrollDelta ?? 0) != 0) {
                      if (_isCalendarMinimized) {
                        _cumulativeScrollDelta = 0.0;
                      } else {
                        _cumulativeScrollDelta +=
                            (notification.scrollDelta ?? 0).abs();
                        if (_cumulativeScrollDelta >=
                            _autoMinimizeScrollThreshold) {
                          _cumulativeScrollDelta = 0.0;
                          setState(() => _isCalendarMinimized = true);
                        }
                      }
                    }
                  }
                  return false;
                },
                child: _buildReleaseSwipeView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseSwipeView() {
    final dayKey = ValueKey((_selectedDay ?? _focusedDay).toIso8601String());

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        if (_dragAnimationController.isAnimating) {
          _dragAnimationController.stop();
        }
        setState(() {
          _isDragging = true;
          _dragOffset = 0.0;
          _dragSessionStartDay = _selectedDay ?? _focusedDay;
          _committedDuringDrag = false;
        });
      },
      onHorizontalDragCancel: () {
        if (_dragAnimationController.isAnimating) {
          _dragAnimationController.stop();
        }
        setState(() {
          _isDragging = false;
          _isSnapping = false;
          _dragOffset = 0.0;
          _committedDuringDrag = false;
        });
      },
      onHorizontalDragUpdate: (details) {
        if (_isSnapping || _committedDuringDrag) {
          return;
        }
        setState(() {
          _dragOffset += details.delta.dx;
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset.abs() < 100 &&
            details.primaryVelocity!.abs() < _horizontalVelocityCommit) {
          setState(() {
            _isDragging = false;
            _dragOffset = 0.0;
            _committedDuringDrag = false;
          });
          return;
        }

        final velocity = details.primaryVelocity ?? 0.0;
        final width = context.size?.width ?? 0.0;
        if (width <= 0) {
          return;
        }

        double target = 0.0;
        bool shouldCommit = false;
        final double clampedOffset = _dragOffset.clamp(-width, width);
        final double minOffsetForVelocityCommit =
            width * _horizontalCommitFraction;

        if (velocity.abs() > _horizontalVelocityCommit &&
            clampedOffset.abs() >= minOffsetForVelocityCommit) {
          target = velocity < 0 ? -width : width;
          shouldCommit = true;
        } else if (clampedOffset.abs() > width * _horizontalCommitFraction) {
          target = clampedOffset < 0 ? -width : width;
          shouldCommit = true;
        } else {
          target = 0.0;
          shouldCommit = false;
        }

        _isSnapping = true;
        if (shouldCommit) {
          _committedDuringDrag = true;
        }

        if (_currentSettleAnimation != null) {
          if (_currentSettleListener != null) {
            _currentSettleAnimation!.removeListener(_currentSettleListener!);
          }
          if (_currentStatusListener != null) {
            _currentSettleAnimation!.removeStatusListener(
              _currentStatusListener!,
            );
          }
        }

        const int baseDurationMs = 260;
        final double distance = (target - clampedOffset).abs();
        final double full = width > 0 ? width : 1.0;
        int durationMs = ((distance / full) * baseDurationMs).round();
        if (durationMs < 120) {
          durationMs = 120;
        }
        if (durationMs > 800) {
          durationMs = 800;
        }

        _dragAnimationController.duration = Duration(milliseconds: durationMs);
        _dragAnimationController.reset();
        final Animation<double> settle =
            Tween<double>(begin: clampedOffset, end: target).animate(
              CurvedAnimation(
                parent: _dragAnimationController,
                curve: Curves.easeOut,
              ),
            );

        _currentSettleAnimation = settle;
        _currentSettleListener = () =>
            setState(() => _dragOffset = settle.value);
        settle.addListener(_currentSettleListener!);

        _currentStatusListener = (status) {
          if (status == AnimationStatus.completed) {
            if (shouldCommit) {
              final base = _dragSessionStartDay ?? _selectedDay ?? _focusedDay;
              if (target < 0) {
                setState(() {
                  _lastSwipeDirection = -1;
                  _selectedDay = DateTime(
                    base.year,
                    base.month,
                    base.day,
                  ).add(const Duration(days: 1));
                  _focusedDay = _selectedDay!;
                });
              } else {
                setState(() {
                  _lastSwipeDirection = 1;
                  _selectedDay = DateTime(
                    base.year,
                    base.month,
                    base.day,
                  ).subtract(const Duration(days: 1));
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final currentReleases = _getReleasesForDay(
            _selectedDay ?? _focusedDay,
          );

          Widget currentChild = CalendarReleaseList(
            key: dayKey,
            releases: currentReleases,
            isLoading: _isLoadingReleases,
            watchlistService: widget.watchlistService,
          );

          if (!_isDragging && _dragOffset == 0.0) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                final isIncoming = child.key == dayKey;
                Offset incomingBegin = Offset.zero;
                if (_lastSwipeDirection == -1) {
                  incomingBegin = const Offset(1.0, 0.0);
                } else if (_lastSwipeDirection == 1) {
                  incomingBegin = const Offset(-1.0, 0.0);
                }

                if (isIncoming) {
                  final tween = Tween<Offset>(
                    begin: incomingBegin,
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeInOut));
                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                } else {
                  final outgoingEnd = Offset(-incomingBegin.dx, 0.0);
                  final tween = Tween<Offset>(
                    begin: Offset.zero,
                    end: outgoingEnd,
                  ).chain(CurveTween(curve: Curves.easeInOut));
                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                }
              },
              child: currentChild,
            );
          }

          final baseDay = _selectedDay ?? _focusedDay;
          final showingNext = _dragOffset < 0;
          final adjacentDay = DateTime(
            baseDay.year,
            baseDay.month,
            baseDay.day,
          ).add(Duration(days: showingNext ? 1 : -1));
          final adjacentReleases = _getReleasesForDay(adjacentDay);

          Widget adjacentChild = CalendarReleaseList(
            releases: adjacentReleases,
            isLoading: false, // Don't show loader in preview
            watchlistService: widget.watchlistService,
          );

          return Stack(
            children: [
              Transform.translate(
                offset: Offset(_dragOffset + (showingNext ? width : -width), 0),
                child: SizedBox(width: width, child: adjacentChild),
              ),
              Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: SizedBox(width: width, child: currentChild),
              ),
            ],
          );
        },
      ),
    );
  }
}
