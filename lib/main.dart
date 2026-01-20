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
import 'models/anime_release.dart';
import 'services/crunchyroll_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/permission_service.dart';
import 'services/battery_optimization_service.dart';
import 'repositories/favorites_repository.dart';
import 'models/favorite_anime.dart';
import 'settings.dart';
import 'pages/favorites_page.dart';
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

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Color _accentColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _loadAccentColor();
  }

  Future<void> _loadAccentColor() async {
    final color = await AppSettings.getAccentColor();
    setState(() {
      _accentColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
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
      home: CalendarPage(onAccentColorChanged: _loadAccentColor),
    );
  }
}

class CalendarPage extends StatefulWidget {
  final VoidCallback? onAccentColorChanged;

  const CalendarPage({super.key, this.onAccentColorChanged});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with TickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  
  DateTime? _selectedDay;
  Map<DateTime, List<AnimeRelease>> _releases = {};
  final CrunchyrollService _crunchyrollService = CrunchyrollService();
  bool _isLoadingImages = false;
  int _imagesLoaded = 0;
  int _imagesToLoad = 0;
  bool _cacheLoaded = false;
  // Accumulates vertical drag delta to allow repeated swipes without lifting
  double _verticalDragDelta = 0.0;
  // Threshold in logical pixels to trigger a format change while dragging
  // Increased to reduce accidental switches while swiping through the calendar
  final double _verticalDragThreshold = 260.0;
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
      if (mounted) {
        setState(() {
          // Trigger rebuild um neue Bilder anzuzeigen
        });
      }
    };

    _loadReleases();

    // Starte automatische Updates alle 5 Minuten
    _crunchyrollService.startAutoUpdate(() {
      if (mounted) {
        _loadReleases();
      }
    });
  }

  Future<void> _loadAutoMinimizeSetting() async {
    try {
      final enabled = await AppSettings.getAutoMinimizeCalendar();
      if (mounted) {
        setState(() {
          _isCalendarMinimized = _isCalendarMinimized; // keep current minimized state
        });
      }
      // store locally for quick checks
      _autoMinimizeEnabled = enabled;
    } catch (e) {
      if (kDebugMode) print('Error loading auto-minimize setting: $e');
      _autoMinimizeEnabled = true;
    }
  }

  // Cached toggle value for quicker checks
  bool _autoMinimizeEnabled = true;

  @override
  void dispose() {
    _crunchyrollService.stopAutoUpdate();
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

      setState(() {
        _releases = releasesByDay;
      });
      
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

      setState(() {
        _releases = releasesByDay;
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
            // Starte Auto-Update mit neuen Einstellungen neu und lade Releases neu
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
            const Text('Crunchyroll Anime Kalender'),
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
            icon: const Icon(Icons.favorite),
            tooltip: 'Meine Favoriten',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FavoritesPage(
                    onAccentColorChanged: widget.onAccentColorChanged,
                  ),
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
                  ? Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                tooltip: 'Vorheriger Monat',
                                onPressed: () {
                                  _goToPreviousMonth();
                                },
                              ),
                              Text(
                                DateFormat.yMMMM('de_DE').format(_focusedDay),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                tooltip: 'Nächster Monat',
                                onPressed: () {
                                  _goToNextMonth();
                                },
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isCalendarMinimized = false;
                              });
                            },
                            icon: Icon(Icons.expand_more, color: Theme.of(context).colorScheme.primary),
                            label: const Text('Kalender öffnen'),
                          ),
                        ],
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
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
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
                          markerDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          markersMaxCount: 3,
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          formatButtonShowsNext: false,
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
                    // Only minimize when user actually scrolls the list (not overscroll)
                    if (_autoMinimizeEnabled && !_isCalendarMinimized && notification.metrics.axis == Axis.vertical && notification.scrollDelta != 0) {
                      setState(() {
                        _isCalendarMinimized = true;
                      });
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
    final releases = _getReleasesForDay(_selectedDay ?? _focusedDay);

    if (releases.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.event_busy, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
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

  Widget _buildReleaseCard(AnimeRelease release) {
    return _ReleaseCard(
      key: ValueKey('${release.title}_${release.episodeInfo}'),
      release: release,
    );
  }
}

/// Stateful Widget für Release Card mit Favoriten-Status
class _ReleaseCard extends StatefulWidget {
  final AnimeRelease release;

  const _ReleaseCard({super.key, required this.release});

  @override
  State<_ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<_ReleaseCard> {
  bool _isFavorite = false;
  late final FavoritesRepository _favoritesRepository;

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    _checkIfFavorite();
    
    // Höre auf globale Favoriten-Änderungen
    favoritesChangeNotifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    favoritesChangeNotifier.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    // Lade Status neu wenn sich Favoriten ändern
    _checkIfFavorite();
  }

  Future<void> _checkIfFavorite() async {
    try {
      final isFav = await _favoritesRepository.isFavorite(widget.release.title);
      if (mounted) {
        setState(() {
          _isFavorite = isFav;
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error checking favorite: $e');
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
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return _AnimeDetailsDialog(
          release: widget.release,
          crunchyrollService: CrunchyrollService(),
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
                Positioned(
                  top: 8,
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 20,
                    child: IconButton(
                      icon: Icon(
                        _isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _isFavorite ? Colors.red : Colors.white,
                        size: 20,
                      ),
                      onPressed: _toggleFavorite,
                      padding: EdgeInsets.zero,
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

  const _AnimeDetailsDialog({
    required this.release,
    required this.crunchyrollService,
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

  @override
  void initState() {
    super.initState();
    _favoritesRepository = FavoritesRepository();
    _loadDescription();
    _checkIfFavorite();
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
                    // Premiere Badge (Rechts neben Favorit Button, wenn vorhanden)
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
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary.computeLuminance() > 0.5
                                      ? Colors.black87
                                      : Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  release.timeString,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary.computeLuminance() > 0.5
                                        ? Colors.black87
                                        : Colors.white,
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

                      // Button zu Crunchyroll
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
