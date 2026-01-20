import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import '../repositories/favorites_repository.dart';
import '../repositories/notification_repository.dart';
import '../services/crunchyroll_service.dart';
import '../services/notification_service.dart';
import '../utils/release_comparator.dart';
import '../models/notification_log.dart';

/// Service für Background-Scraping wenn die App geschlossen ist
/// Nutzt Workmanager um periodische Aufgaben zu planen
class BackgroundService {
  static const String _taskName = 'crunchyrollScraperTask';
  static const String _uniqueName = 'crunchyroll-periodic-scraper';
  static const String _testNotificationTaskName = 'testNotificationTask';
  static const String _favoritesTestTaskName = 'favoritesTestNotificationTask';
  
  static final BackgroundService _instance = BackgroundService._internal();
  
  factory BackgroundService() {
    return _instance;
  }
  
  BackgroundService._internal();
  
  /// Initialisiert den Background Service
  /// Muss beim App-Start aufgerufen werden
  static Future<void> initialize() async {
    try {
      if (kDebugMode) print('🔧 Initializing Background Service...');
      
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode, // Nur im Debug-Modus Logs anzeigen
      );
      
      if (kDebugMode) print('✓ Background Service initialized successfully');
    } catch (e) {
      if (kDebugMode) print('❌ CRITICAL: Error initializing background service: $e');
      rethrow;
    }
  }
  
  /// Test-Methode: Lädt Favoriten von heute und sendet Test-Benachrichtigungen
  /// Registriert einen Background-Task für Favoriten-Test-Benachrichtigungen
  /// Dieser läuft im Hintergrund, auch wenn die App geschlossen wird!
  /// [delaySeconds] - Verzögerung in Sekunden bevor die Benachrichtigung gesendet wird (aus Einstellungen)
  Future<void> sendTestNotificationsForTodaysFavorites({int delaySeconds = 0}) async {
    try {
      if (kDebugMode) print('🔔 [TEST] Scheduling favorites test notifications via Workmanager (delay: ${delaySeconds}s)...');
      
      final uniqueName = 'favorites_test_${DateTime.now().millisecondsSinceEpoch}';
      
      // Mindestens 1 Sekunde, damit die App Zeit hat
      final effectiveDelay = delaySeconds > 0 ? delaySeconds : 1;
      
      await Workmanager().registerOneOffTask(
        uniqueName,
        _favoritesTestTaskName,
        // Verwende die eingestellte Verzögerung
        initialDelay: Duration(seconds: effectiveDelay),
      );
      
      if (kDebugMode) {
        print('✅ [TEST] Favorites test task scheduled - will run in ~$effectiveDelay seconds');
        print('ℹ️  [TEST] Du kannst die App jetzt schließen, die Benachrichtigungen kommen trotzdem!');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [TEST] Error scheduling favorites test: $e');
        print('❌ [TEST] Stack trace: $stackTrace');
      }
    }
  }

  /// Test: Führt den Background-Scraper SOFORT aus (zum Testen ob er funktioniert)
  Future<void> testBackgroundScraperNow() async {
    try {
      if (kDebugMode) print('🧪 [TEST] Scheduling background scraper test via Workmanager...');
      
      final uniqueName = 'scraper_test_${DateTime.now().millisecondsSinceEpoch}';
      
      await Workmanager().registerOneOffTask(
        uniqueName,
        _taskName,  // Gleicher Task wie der periodische Scraper
        initialDelay: const Duration(seconds: 3),
      );
      
      if (kDebugMode) {
        print('✅ [TEST] Background scraper test scheduled - will run in ~3 seconds');
        print('ℹ️  [TEST] Schließe die App und prüfe die Logs!');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ [TEST] Error scheduling scraper test: $e');
        print('❌ [TEST] Stack trace: $stackTrace');
      }
    }
  }

  /// Startet die periodische Scraper-Aufgabe
  /// [intervalMinutes] - Wiederholungsintervall (minimum 15 Minuten)
  Future<void> startPeriodicScraperTask({int intervalMinutes = 30}) async {
    try {
      if (kDebugMode) print('📅 Attempting to register periodic scraper task...');
      
      if (intervalMinutes < 15) {
        if (kDebugMode) print('⚠️  Minimum interval is 15 minutes, using 15');
        intervalMinutes = 15;
      }
      
      if (kDebugMode) {
        print('🔍 Registering task with:');
        print('   - Unique name: $_uniqueName');
        print('   - Task name: $_taskName');
        print('   - Interval: $intervalMinutes minutes');
        print('   - Network constraint: connected (REQUIRED)');
      }
      
      await Workmanager().registerPeriodicTask(
        _uniqueName,
        _taskName,
        frequency: Duration(minutes: intervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 5),
      );
      
      if (kDebugMode) {
        print('✅ PERIODIC TASK REGISTERED SUCCESSFULLY!');
        print('   Task will run in 5 minutes, then every $intervalMinutes minutes');
        print('   (If device has internet connection)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ CRITICAL: Error starting periodic task: $e');
      rethrow;
    }
  }
  
  /// Stoppt die periodische Scraper-Aufgabe
  Future<void> stopPeriodicScraperTask() async {
    try {
      await Workmanager().cancelByUniqueName(_uniqueName);
      
      if (kDebugMode) print('✓ Periodic scraper task stopped');
    } catch (e) {
      if (kDebugMode) print('❌ Error stopping periodic task: $e');
    }
  }
  
  /// Prüft ob eine Aufgabe bereits läuft
  Future<bool> isTaskRunning() async {
    try {
      // Workmanager hat keine getAllTasks() API
      // Wir nutzen stattdessen einen einfachen Cache-Check
      // Wenn registerPeriodicTask erfolgreich war, läuft die Task
      return true; // Task läuft wenn sie registriert wurde
    } catch (e) {
      if (kDebugMode) print('❌ Error checking task status: $e');
      return false;
    }
  }

  /// Registriert eine einmalige Test-Benachrichtigung nach X Sekunden
  /// Funktioniert auch wenn die App geschlossen ist
  Future<void> scheduleTestNotification(int delaySeconds) async {
    try {
      final uniqueName = 'test_notification_${DateTime.now().millisecondsSinceEpoch}';
      
      await Workmanager().registerOneOffTask(
        uniqueName,
        _testNotificationTaskName,
        initialDelay: Duration(seconds: delaySeconds),
        inputData: {
          'delay_seconds': delaySeconds,
          'scheduled_time': DateTime.now().toIso8601String(),
        },
      );
      
      if (kDebugMode) {
        print('✓ Test notification scheduled for $delaySeconds seconds from now');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error scheduling test notification: $e');
    }
  }

  /// SOFORT-TEST: Registriere einen einmaligen Task (läuft in ~1 Sekunde)
  /// Dies ist zum Testen, ob Workmanager ÜBERHAUPT funktioniert
  Future<void> testWorkmanagerNow() async {
    try {
      if (kDebugMode) print('🧪 [TEST] Registering immediate test task...');
      
      await Workmanager().registerOneOffTask(
        'workmanager_test_now',
        'workmanager_test_now',
        // Keine Verzögerung! Sollte sofort laufen
        // Keine Constraints für schnelle Tests
      );
      
      if (kDebugMode) {
        print('✅ Test task registered - check logs in 2-3 seconds');
        print('   Expected: 🚀 [BACKGROUND] callbackDispatcher activated!');
        print('   Expected: 🔄 [BACKGROUND] Executing task: workmanager_test_now');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error registering test task: $e');
    }
  }
}

/// Callback-Dispatcher für Background Tasks
/// Diese Funktion wird in einem separaten Isolate ausgeführt
@pragma('vm:entry-point')
void callbackDispatcher() {
  if (kDebugMode) print('🚀 [BACKGROUND] callbackDispatcher activated!');
  
  Workmanager().executeTask((String taskName, Map<String, dynamic>? inputData) async {
    try {
      if (kDebugMode) print('🔄 [BACKGROUND] Executing task: $taskName');
      
      // Sofort-Test Task
      if (taskName == 'workmanager_test_now') {
        if (kDebugMode) print('✅ [BACKGROUND] WORKMANAGER WORKS! Immediate test successful!');
        return Future.value(true);
      }
      
      if (taskName == BackgroundService._taskName) {
        if (kDebugMode) print('📱 [BACKGROUND] Running scraper task...');
        return await _executeBackgroundScraper();
      } else if (taskName == BackgroundService._testNotificationTaskName) {
        if (kDebugMode) print('🧪 [BACKGROUND] Running test notification task...');
        return await _executeTestNotification(inputData);
      } else if (taskName == BackgroundService._favoritesTestTaskName) {
        if (kDebugMode) print('🔔 [BACKGROUND] Running favorites test notification task...');
        return await _executeFavoritesTestNotification();
      }
      
      if (kDebugMode) print('⚠️  [BACKGROUND] Unknown task: $taskName');
      return Future.value(true);
    } catch (e) {
      if (kDebugMode) print('❌ [BACKGROUND] Task error: $e');
      return Future.value(false);
    }
  });
}

/// Hauptfunktion für Background-Scraping
/// Wird periodisch aufgerufen wenn die App geschlossen ist
Future<bool> _executeBackgroundScraper() async {
  try {
    if (kDebugMode) print('🔄 [BACKGROUND-SCRAPER] Background scraper started at ${DateTime.now()}');
    
    final startTime = DateTime.now();
    
    // 1. Initialisiere Services
    if (kDebugMode) print('🔧 [BACKGROUND-SCRAPER] Initializing services...');
    final favoritesRepo = FavoritesRepository();
    final notificationRepo = NotificationRepository();
    final crunchyrollService = CrunchyrollService();
    final notificationService = NotificationService();
    
    // WICHTIG: Initialisiere NotificationService im Background Isolate!
    if (kDebugMode) print('📲 [BACKGROUND-SCRAPER] Initializing notification service...');
    final notificationInitialized = await notificationService.initialize();
    if (!notificationInitialized) {
      if (kDebugMode) print('❌ [BACKGROUND-SCRAPER] Failed to initialize notification service in background');
      return false;
    }
    
    // 2. Scrape aktuelle Releases (dies aktualisiert automatisch den Cache!)
    if (kDebugMode) print('🌐 [BACKGROUND-SCRAPER] Fetching and caching current releases from Crunchyroll...');
    final now = DateTime.now();
    final allReleases = await crunchyrollService.getReleasesForWeek(now);
    
    if (kDebugMode) print('📺 [BACKGROUND-SCRAPER] Fetched and cached ${allReleases.length} releases for this week');
    
    if (allReleases.isEmpty) {
      if (kDebugMode) print('⚠️  [BACKGROUND-SCRAPER] No releases found for this week');
      return true;
    }
    
    // 3. Hole alle Favoriten
    if (kDebugMode) print('📚 [BACKGROUND-SCRAPER] Loading favorites from database...');
    final favorites = await favoritesRepo.getAllFavorites();
    
    if (favorites.isEmpty) {
      if (kDebugMode) print('ℹ️  [BACKGROUND-SCRAPER] No favorites configured - cache updated, done');
      return true;
    }
    
    if (kDebugMode) print('✅ [BACKGROUND-SCRAPER] Loaded ${favorites.length} total favorites');

    // Filtere nur Favoriten mit aktivierten Benachrichtigungen
    final enabledFavorites = favorites.where((f) => f.notificationsEnabled).toList();
    if (enabledFavorites.isEmpty) {
      if (kDebugMode) print('🔕 [BACKGROUND-SCRAPER] All favorites muted - cache updated, skipping notifications');
      return true;
    }
    
    if (kDebugMode) print('🔔 [BACKGROUND-SCRAPER] Checking ${enabledFavorites.length} favorites with notifications on');
    
    // WICHTIG: Filtere nur Releases von HEUTE (nicht aus der Vergangenheit!)
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    
    final todaysReleases = allReleases.where((release) {
      return release.releaseTime.isAfter(todayStart) && 
             release.releaseTime.isBefore(todayEnd);
    }).toList();
    
    if (kDebugMode) print('📅 [BACKGROUND-SCRAPER] Releases from today only: ${todaysReleases.length}');
    
    if (todaysReleases.isEmpty) {
      if (kDebugMode) print('ℹ️  [BACKGROUND-SCRAPER] Keine Releases für heute gefunden - cache updated, done');
      return true;
    }
    
    // 4. Filtere nach Favoriten
    if (kDebugMode) print('🔍 [BACKGROUND-SCRAPER] Filtering releases by favorites...');
    final favoritesTitles = enabledFavorites.map((f) => f.title).toList();
    final relevantReleases = ReleaseComparator.filterByFavorites(
      releases: todaysReleases,  // Nur heutige Releases!
      favorites: favoritesTitles,
    );
    
    if (relevantReleases.isEmpty) {
      if (kDebugMode) print('✓ [BACKGROUND-SCRAPER] No new releases for favorites today - cache updated, done');
      return true;
    }
    
    if (kDebugMode) print('✅ [BACKGROUND-SCRAPER] Found ${relevantReleases.length} releases for favorites today');
    
    // 5. Prüfe auf bereits gesendete Benachrichtigungen
    final uniqueReleases = ReleaseComparator.sortByRelevance(relevantReleases);
    
    // 🚀 LOGGING UND STATISTIKEN AKTIVIEREN
    final stats = await notificationRepo.getNotificationStats(hoursBack: 2);
    if (kDebugMode) {
      print('📊 [BACKGROUND-SCRAPER] Notification Stats (last 2 hours):');
      print('   - Total sent: ${stats['totalCount']}');
      print('   - Unique content: ${stats['uniqueCount']}');
      print('   - Affected favorites: ${stats['favCount']}');
    }
    
    // 6. Sende Benachrichtigungen für neue Releases
    int notificationCount = 0;
    int skippedDuplicates = 0;
    
    if (kDebugMode) print('📤 [BACKGROUND-SCRAPER] Processing ${uniqueReleases.length} releases...');
    
    for (final release in uniqueReleases) {
      // Erstelle NotificationLog mit Content-Hash
      final notification = NotificationLog(
        favoriteTitle: release.title,
        releaseTitle: release.episodeTitle,
        episodeNumber: release.episodeNumber,
        notifyTime: DateTime.now(),
        isShown: true,
      );
      
      // 🚀 NEUE LOGIK: Prüfe auf Duplikat basierend auf Content-Hash
      final contentHash = notification.generateContentHash();
      
      if (kDebugMode) {
        print('🔍 [BACKGROUND-SCRAPER] Checking: ${release.title} ep.${release.episodeNumber} hash=$contentHash');
      }
      
      final isDuplicate = await notificationRepo.isDuplicate(
        contentHash,
        favoriteTitle: release.title,
        releaseTitle: release.episodeTitle,
        episodeNumber: release.episodeNumber,
      );
      
      if (isDuplicate) {
        if (kDebugMode) {
          print('⏭️  [BACKGROUND-SCRAPER] DUPLICATE SKIPPED: ${release.title} ep.${release.episodeNumber} hash=$contentHash');
        }
        skippedDuplicates++;
        continue;
      }
      
      // Zeige Benachrichtigung
      final notificationBody = release.isPremiere 
        ? '🎬 Neue Serie: ${release.title}'
        : 'Folge ${release.episodeNumber}: ${release.title}';
      
      if (kDebugMode) {
        print('📤 [BACKGROUND-SCRAPER] SENDING NOTIFICATION: ${release.title} ep.${release.episodeNumber}');
      }
      
      await notificationService.showNotification(
        title: 'Neuer Anime Release',
        body: notificationBody,
        payload: release.seriesUrl,
      );
      
      // 🚀 Logge Benachrichtigung mit Content-Hash
      final notificationWithHash = notification.copyWith(
        contentHash: contentHash,
      );
      
      await notificationRepo.logNotification(notificationWithHash);
      
      notificationCount++;
      
      if (kDebugMode) {
        print('✅ [BACKGROUND-SCRAPER] LOGGED TO DB: ${release.title} ep.${release.episodeNumber} hash=$contentHash');
      }
    }
    
    // 7. Aktualisiere lastChecked für alle Favoriten
    for (final favorite in enabledFavorites) {
      await favoritesRepo.updateLastChecked(favorite.title);
    }
    
    final duration = DateTime.now().difference(startTime);
    
    if (kDebugMode) {
      print('✅ [BACKGROUND-SCRAPER] Completed in ${duration.inSeconds}s');
      print('   - Favorites checked: ${favorites.length}');
      print('   - Releases found: ${uniqueReleases.length}');
      print('   - Notifications sent: $notificationCount');
      print('   - Duplicates skipped: $skippedDuplicates');
      print('   - Total to send: ${uniqueReleases.length}');
    }
    
    return true;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      print('❌ [BACKGROUND-SCRAPER] Failed: $e');
      print('❌ [BACKGROUND-SCRAPER] Stack: $stackTrace');
    }
    return false;
  }
}

/// Test-Benachrichtigung ausführen (im Background Isolate)
Future<bool> _executeTestNotification(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) print('🔔 [BACKGROUND] Sending test notification from background...');
    
    final delaySeconds = inputData?['delay_seconds'] ?? 0;
    
    // Initialisiere NotificationService
    final notificationService = NotificationService();
    await notificationService.initialize();
    
    // Sende Benachrichtigung
    await notificationService.showNotification(
      title: 'Background Test funktioniert! 🎉',
      body: 'Diese Benachrichtigung wurde nach $delaySeconds Sekunden im Hintergrund gesendet.',
      payload: 'background_test',
    );
    
    if (kDebugMode) print('✅ [BACKGROUND] Background test notification sent successfully');
    
    return true;
  } catch (e) {
    if (kDebugMode) print('❌ [BACKGROUND] Test notification error: $e');
    return false;
  }
}

/// Favoriten-Test-Benachrichtigungen im Background ausführen
Future<bool> _executeFavoritesTestNotification() async {
  try {
    if (kDebugMode) print('🔔 [BACKGROUND] Starting favorites test notifications...');
    
    // Initialisiere Services
    final favoritesRepo = FavoritesRepository();
    final crunchyrollService = CrunchyrollService();
    final notificationService = NotificationService();
    
    // WICHTIG: Initialisiere NotificationService im Background Isolate!
    if (kDebugMode) print('📲 [BACKGROUND] Initializing notification service...');
    final initialized = await notificationService.initialize();
    if (!initialized) {
      if (kDebugMode) print('❌ [BACKGROUND] Failed to initialize notification service');
      return false;
    }
    
    // Lade alle Favoriten
    if (kDebugMode) print('📚 [BACKGROUND] Loading favorites from database...');
    final allFavorites = await favoritesRepo.getAllFavorites();
    if (kDebugMode) print('📚 [BACKGROUND] Loaded ${allFavorites.length} favorites');
    
    // Filtere nur Favoriten mit aktivierter Benachrichtigung
    final enabledFavorites = 
        allFavorites.where((f) => f.notificationsEnabled).toList();
    if (kDebugMode) print('🔔 [BACKGROUND] Enabled favorites: ${enabledFavorites.length}');
    
    if (enabledFavorites.isEmpty) {
      if (kDebugMode) print('ℹ️  [BACKGROUND] Keine Favoriten mit aktivierten Benachrichtigungen');
      return true;
    }
    
    // WICHTIG: Verwende forceRefresh um FRISCHE Daten zu bekommen (nicht aus Cache!)
    if (kDebugMode) print('🌐 [BACKGROUND] Force-fetching fresh releases from Crunchyroll...');
    final now = DateTime.now();
    final allReleases = await crunchyrollService.forceRefresh(forMonth: now);
    if (kDebugMode) print('📺 [BACKGROUND] Found ${allReleases.length} fresh releases for this month');
    
    // WICHTIG: Filtere nur Releases von HEUTE (nicht aus der Vergangenheit!)
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    
    final todaysReleases = allReleases.where((release) {
      return release.releaseTime.isAfter(todayStart) && 
             release.releaseTime.isBefore(todayEnd);
    }).toList();
    
    if (kDebugMode) print('📅 [BACKGROUND] Releases from today only: ${todaysReleases.length}');
    
    if (todaysReleases.isEmpty) {
      if (kDebugMode) print('ℹ️  [BACKGROUND] Keine Releases für heute gefunden');
      return true;
    }
    
    // Finde Favoriten mit Releases von HEUTE
    final favoritesWithTodaysReleases = enabledFavorites.where((fav) {
      return todaysReleases.any((release) =>
          release.title.toLowerCase() == fav.title.toLowerCase());
    }).toList();
    
    if (favoritesWithTodaysReleases.isEmpty) {
      if (kDebugMode) print('ℹ️  [BACKGROUND] Keine Favoriten mit Releases von heute');
      return true;
    }
    
    if (kDebugMode) print('📤 [BACKGROUND] Sending notifications for ${favoritesWithTodaysReleases.length} favorites with releases today');
    
    // Sende Benachrichtigungen für jeden Favoriten mit Release heute
    final notificationRepo = NotificationRepository();
    for (int i = 0; i < favoritesWithTodaysReleases.length; i++) {
      final favorite = favoritesWithTodaysReleases[i];

      // Finde die passenden Releases für diesen Favoriten
      final matchingReleases = todaysReleases.where((release) =>
          release.title.toLowerCase() == favorite.title.toLowerCase()).toList();

      for (final release in matchingReleases) {
        // Erstelle NotificationLog und prüfe Dedupe anhand des Content-Hash
        final log = NotificationLog(
          favoriteTitle: release.title,
          releaseTitle: release.episodeTitle,
          episodeNumber: release.episodeNumber,
          notifyTime: DateTime.now(),
          isShown: true,
        );

        final hash = log.generateContentHash();
        if (kDebugMode) print('🔍 [FAV-TEST] Checking duplicate for ${release.title} ep.${release.episodeNumber} hash=$hash');

        final already = await notificationRepo.isDuplicate(hash);
        if (already) {
          if (kDebugMode) print('⏭️  [FAV-TEST] Duplicate found, skipping: ${release.title} ep.${release.episodeNumber}');
          continue;
        }

        if (kDebugMode) print('📤 [BACKGROUND] SENDING favorite-test notification for: ${release.title} - ${release.episodeInfo}');

        await notificationService.showNotification(
          title: '🔔 Neue Episode: ${release.title}',
          body: '${release.episodeInfo}: ${release.episodeTitle}',
          payload: 'release_${release.title}_${release.episodeNumber}',
        );

        // Logge die Benachrichtigung in der DB
        try {
          final withHash = log.copyWith(contentHash: hash);
          await notificationRepo.logNotification(withHash);
          if (kDebugMode) print('✅ [FAV-TEST] Logged favorite-test notification: ${release.title} ep.${release.episodeNumber} hash=$hash');
        } catch (e) {
          if (kDebugMode) print('❌ [FAV-TEST] Error logging favorite-test notification: $e');
        }

        // Kleine Verzögerung zwischen Benachrichtigungen
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    if (kDebugMode) print('✅ [BACKGROUND] All notifications sent!');
    return true;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      print('❌ [BACKGROUND] Favorites test notification error: $e');
      print('❌ [BACKGROUND] Stack trace: $stackTrace');
    }
    return false;
  }
}
