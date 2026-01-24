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
  final Watchlist watchlist = Watchlist();
  late final WatchlistService watchlistService;

  @override
  void initState() {
    super.initState();
    watchlistService = WatchlistService(watchlist);
    // Load stored watchlist asynchronously so widgets reflect initial state
    watchlistService.loadWatchlist().catchError((e) {
      if (kDebugMode) print('❌ Failed to load watchlist on startup: $e');
    });
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
        watchlistService: watchlistService
      ),
    );
  }
}
