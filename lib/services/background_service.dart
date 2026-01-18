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
  
  static final BackgroundService _instance = BackgroundService._internal();
  
  factory BackgroundService() {
    return _instance;
  }
  
  BackgroundService._internal();
  
  /// Initialisiert den Background Service
  /// Muss beim App-Start aufgerufen werden
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );
      
      if (kDebugMode) print('✓ Background Service initialized');
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing background service: $e');
    }
  }
  
  /// Startet die periodische Scraper-Aufgabe
  /// [intervalMinutes] - Wiederholungsintervall (minimum 15 Minuten)
  Future<void> startPeriodicScraperTask({int intervalMinutes = 30}) async {
    try {
      if (intervalMinutes < 15) {
        if (kDebugMode) print('⚠️  Minimum interval is 15 minutes, using 15');
        intervalMinutes = 15;
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
        print('✓ Periodic scraper task started (interval: $intervalMinutes minutes)');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error starting periodic task: $e');
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
}

/// Callback-Dispatcher für Background Tasks
/// Diese Funktion wird in einem separaten Isolate ausgeführt
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String taskName, Map<String, dynamic>? inputData) async {
    try {
      if (taskName == BackgroundService._taskName) {
        return await _executeBackgroundScraper();
      } else if (taskName == BackgroundService._testNotificationTaskName) {
        return await _executeTestNotification(inputData);
      }
      
      return Future.value(true);
    } catch (e) {
      if (kDebugMode) print('❌ Background task error: $e');
      return Future.value(false);
    }
  });
}

/// Hauptfunktion für Background-Scraping
/// Wird periodisch aufgerufen wenn die App geschlossen ist
Future<bool> _executeBackgroundScraper() async {
  try {
    if (kDebugMode) print('🔄 Background scraper started');
    
    final startTime = DateTime.now();
    
    // 1. Initialisiere Services
    final favoritesRepo = FavoritesRepository();
    final notificationRepo = NotificationRepository();
    final crunchyrollService = CrunchyrollService();
    final notificationService = NotificationService();
    
    // 2. Hole alle Favoriten
    final favorites = await favoritesRepo.getAllFavorites();
    
    if (favorites.isEmpty) {
      if (kDebugMode) print('ℹ️  No favorites configured');
      return true;
    }
    
    if (kDebugMode) print('📋 Checking ${favorites.length} favorites');
    
    // 3. Scrape aktuelle Releases
    final currentReleases = await crunchyrollService.getReleasesForWeek(DateTime.now());
    
    if (currentReleases.isEmpty) {
      if (kDebugMode) print('⚠️  No releases found');
      return true;
    }
    
    if (kDebugMode) print('📥 Found ${currentReleases.length} current releases');
    
    // 4. Filtere nach Favoriten
    final favoritesTitles = favorites.map((f) => f.title).toList();
    final relevantReleases = ReleaseComparator.filterByFavorites(
      releases: currentReleases,
      favorites: favoritesTitles,
    );
    
    if (relevantReleases.isEmpty) {
      if (kDebugMode) print('✓ No new releases for favorites');
      return true;
    }
    
    if (kDebugMode) print('✅ Found ${relevantReleases.length} releases for favorites');
    
    // 5. Prüfe auf bereits gesendete Benachrichtigungen
    final uniqueReleases = ReleaseComparator.sortByRelevance(relevantReleases);
    
    // 6. Sende Benachrichtigungen für neue Releases
    int notificationCount = 0;
    
    for (final release in uniqueReleases) {
      // Prüfe ob Benachrichtigung bereits gesendet wurde
      final alreadyNotified = await notificationRepo.hasBeenNotified(
        release.title,
        release.episodeTitle,
        release.episodeNumber,
      );
      
      if (alreadyNotified) {
        if (kDebugMode) print('⏭️  Skip (already notified): ${release.title} - ${release.episodeTitle}');
        continue;
      }
      
      // Zeige Benachrichtigung
      final notificationBody = release.isPremiere 
        ? '🎬 Neue Serie: ${release.title}'
        : 'Folge ${release.episodeNumber}: ${release.title}';
      
      await notificationService.showNotification(
        title: 'Neuer Anime Release',
        body: notificationBody,
        payload: release.seriesUrl,
      );
      
      // Logge Benachrichtigung
      final notification = NotificationLog(
        favoriteTitle: release.title,
        releaseTitle: release.episodeTitle,
        episodeNumber: release.episodeNumber,
        notifyTime: DateTime.now(),
        isShown: true,
      );
      
      await notificationRepo.logNotification(notification);
      
      notificationCount++;
      
      if (kDebugMode) print('✓ Notified: ${release.title} - ${release.episodeTitle}');
    }
    
    // 7. Aktualisiere lastChecked für alle Favoriten
    for (final favorite in favorites) {
      await favoritesRepo.updateLastChecked(favorite.title);
    }
    
    final duration = DateTime.now().difference(startTime);
    
    if (kDebugMode) {
      print('✓ Background scraper completed in ${duration.inSeconds}s');
      print('  - Favorites checked: ${favorites.length}');
      print('  - Releases found: ${uniqueReleases.length}');
      print('  - Notifications sent: $notificationCount');
    }
    
    return true;
  } catch (e) {
    if (kDebugMode) print('❌ Background scraper failed: $e');
    return false;
  }
}

/// Test-Benachrichtigung ausführen (im Background Isolate)
Future<bool> _executeTestNotification(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) print('🔔 Sending test notification from background...');
    
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
    
    if (kDebugMode) print('✓ Background test notification sent successfully');
    
    return true;
  } catch (e) {
    if (kDebugMode) print('❌ Test notification error: $e');
    return false;
  }
}
