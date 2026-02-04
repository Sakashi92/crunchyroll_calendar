import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/app_settings_service.dart';
import 'models/watchlist.dart';
import 'services/watchlist_service.dart';
import 'pages/calendar_page.dart';
import 'utils/ui_utils.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  Intl.defaultLocale = 'de_DE';

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(450, 850),
      minimumSize: Size(350, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Crunchyroll Anime Kalender',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Notification Service initialisieren (nur auf Mobilgeräten voll funktionsfähig)
  if (Platform.isAndroid || Platform.isIOS) {
    await NotificationService().initialize();
  }
  await AppSettingsService.init();

  // Background Service initialisieren (nur auf Mobilgeräten)
  if (Platform.isAndroid || Platform.isIOS) {
    await BackgroundService.initialize();
    await BackgroundService().startPeriodicScraperTask(intervalMinutes: 20);
  }

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Color _accentColor = Colors.orange;
  final Watchlist watchlist = Watchlist();
  WatchlistService? _watchlistService;
  WatchlistService get watchlistService {
    _watchlistService ??= WatchlistService(watchlist);
    return _watchlistService!;
  }

  @override
  void initState() {
    super.initState();
    // Load stored watchlist asynchronously so widgets reflect initial state
    watchlistService.loadWatchlist().catchError((e) {
      if (kDebugMode) {
        print('❌ Failed to load watchlist on startup: $e');
      }
    });
    _loadAccentColor();
    // Versuche einmalig Migration von Favoriten-Notification-Settings in die Watchlist
    _runWatchlistMigration();
  }

  void _runWatchlistMigration() async {
    try {
      final migrated = await watchlistService
          .migrateNotificationSettingsFromFavorites();
      if (migrated > 0) {
        if (kDebugMode) {
          print(
            '🔁 Migrated $migrated notification settings from favorites to watchlist',
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          UIUtils.showSnackBar(
            context,
            SnackBar(
              content: Text(
                '🔁 $migrated Favoriten-Benachrichtigungen in Watchlist übernommen',
              ),
            ),
          );
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Migration error: $e');
      }
    }
  }

  Future<void> _loadAccentColor() async {
    final color = await AppSettingsService.getAccentColor();
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
      home: CalendarPage(
        onAccentColorChanged: _loadAccentColor,
        watchlistService: watchlistService,
      ),
    );
  }
}
