import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';

/// Service für lokale Benachrichtigungen
/// Zeigt Benachrichtigungen an wenn neue Releases verfügbar sind
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() {
    return _instance;
  }
  
  NotificationService._internal();
  
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _isInitialized = false;
  
  /// Initialisiert den Notification Service für iOS und Android
  Future<bool> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) print('ℹ️  Notifications already initialized');
      return true;
    }
    
    try {
      _notificationsPlugin = FlutterLocalNotificationsPlugin();
      
      // Timezone initialisieren
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Berlin'));
      
      // Android Setup
      const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/hime');
      
      // iOS Setup
      const DarwinInitializationSettings iosSettings = 
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
      
      // Kombinierte Einstellungen
      final InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // Initialize mit Callback
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      
      // Notification Channels für Android
      await _setupAndroidNotificationChannels();
      
      _isInitialized = true;
      if (kDebugMode) print('✓ Notifications initialized successfully');
      
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ Error initializing notifications: $e');
      return false;
    }
  }
  
  /// Erstellt die erforderlichen Notification Channels für Android
  Future<void> _setupAndroidNotificationChannels() async {
    const AndroidNotificationChannel newReleaseChannel = 
      AndroidNotificationChannel(
        'new_releases',
        'Neue Anime Releases',
        description: 'Benachrichtigungen für neue Releases von favorisierten Anime',
        importance: Importance.high,
        enableVibration: true,
      );
    
    const AndroidNotificationChannel reminderChannel = 
      AndroidNotificationChannel(
        'reminders',
        'Erinnerungen',
        description: 'Erinnerungen für kommende Releases',
        importance: Importance.low,
        enableVibration: false,
      );
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(newReleaseChannel);
    
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(reminderChannel);
  }
  
  /// Zeigt eine sofortige Benachrichtigung an
  /// [title] - Haupttitel der Benachrichtigung
  /// [body] - Benachrichtigungstext
  /// [payload] - Optionale Daten (z.B. für Navigation)
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      if (kDebugMode) print('⚠️  Notifications not initialized');
      return;
    }
    
    try {
      const AndroidNotificationDetails androidDetails = 
        AndroidNotificationDetails(
          'new_releases',
          'Neue Anime Releases',
          channelDescription: 'Benachrichtigungen für neue Releases',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          enableVibration: true,
        );
      
      const DarwinNotificationDetails iosDetails = 
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
      
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: payload,
      );
      
      if (kDebugMode) print('✓ Notification shown: $title');
    } catch (e) {
      if (kDebugMode) print('❌ Error showing notification: $e');
    }
  }
  
  /// Plant eine Benachrichtigung für eine zukünftige Zeit
  /// [title] - Titel
  /// [body] - Text
  /// [scheduledTime] - Zeitpunkt der Benachrichtigung
  /// [payload] - Optionale Daten
  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (!_isInitialized) {
      if (kDebugMode) print('⚠️  Notifications not initialized');
      return;
    }
    
    try {
      // Prüfe ob Zeitpunkt in der Vergangenheit liegt
      if (scheduledTime.isBefore(DateTime.now())) {
        if (kDebugMode) print('⚠️  Scheduled time is in the past, showing immediately');
        await showNotification(
          title: title,
          body: body,
          payload: payload,
        );
        return;
      }
      
      const AndroidNotificationDetails androidDetails = 
        AndroidNotificationDetails(
          'new_releases',
          'Neue Anime Releases',
          channelDescription: 'Benachrichtigungen für neue Releases',
          importance: Importance.high,
          priority: Priority.high,
        );
      
      const DarwinNotificationDetails iosDetails = 
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
      
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notificationsPlugin.zonedSchedule(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: 
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      
      if (kDebugMode) {
        print('✓ Notification scheduled for: ${scheduledTime.toIso8601String()}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error scheduling notification: $e');
    }
  }
  
  /// Callback wenn auf eine Benachrichtigung geklickt wird
  void _onNotificationResponse(NotificationResponse response) {
    if (kDebugMode) {
      print('📲 Notification tapped with payload: ${response.payload}');
    }
    
    // Hier kann eine Navigation oder Action durchgeführt werden
    // z.B. zu der entsprechenden Anime-Detail-Seite navigieren
  }
  
  /// Löscht alle ausstehenden Benachrichtigungen
  Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
      if (kDebugMode) print('✓ All notifications cancelled');
    } catch (e) {
      if (kDebugMode) print('❌ Error cancelling notifications: $e');
    }
  }
  
  /// Löscht eine bestimmte Benachrichtigung anhand ihrer ID
  Future<void> cancel(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      if (kDebugMode) print('✓ Notification cancelled: $id');
    } catch (e) {
      if (kDebugMode) print('❌ Error cancelling notification: $e');
    }
  }
  
  /// Prüft ob Benachrichtigungen aktiviert sind (iOS)
  Future<bool> areNotificationsEnabled() async {
    try {
      final isEnabled = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ?? true;
      
      return isEnabled;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking notification permissions: $e');
      return false;
    }
  }
}
