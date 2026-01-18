import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  factory PermissionService() {
    return _instance;
  }

  PermissionService._internal();

  /// Request necessary permissions on app startup
  /// On Android 13+ this requests POST_NOTIFICATIONS permission
  /// On iOS this requests notification permissions
  Future<void> requestInitialPermissions() async {
    try {
      if (Platform.isAndroid) {
        // Initialize Android plugin first
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/hime');
        
        final InitializationSettings initializationSettings =
            InitializationSettings(android: initializationSettingsAndroid);
        
        await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

        // Request permission by trying to show a notification
        // This will trigger the permission dialog on Android 13+
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>();

        if (androidImplementation != null) {
          // Android 13+ (API 33+): Explizit POST_NOTIFICATIONS Permission anfragen
          final bool? granted = await androidImplementation.requestNotificationsPermission();
          
          if (granted == true) {
            print('✅ Notification Permission erteilt');
            
            // Erstelle Notification Channel
            const AndroidNotificationChannel channel = AndroidNotificationChannel(
              'permission_request_channel',
              'Permission Requests',
              description: 'Used for initial permission request',
              importance: Importance.high,
            );
            await androidImplementation.createNotificationChannel(channel);
            
            // Zeige Bestätigungs-Notification
            const AndroidNotificationDetails androidDetails =
                AndroidNotificationDetails(
              'permission_request_channel',
              'Permission Requests',
              channelDescription: 'Used for initial permission request',
              importance: Importance.high,
              priority: Priority.high,
              autoCancel: true,
              timeoutAfter: 2000,
            );

            const NotificationDetails notificationDetails =
                NotificationDetails(android: androidDetails);

            await _flutterLocalNotificationsPlugin.show(
              999,
              'Crunchyroll Kalender',
              '✓ Benachrichtigungen aktiviert',
              notificationDetails,
            );
            
            // Auto-entfernen nach 2 Sekunden
            Future.delayed(const Duration(milliseconds: 2500), () {
              _flutterLocalNotificationsPlugin.cancel(999);
            });
          } else if (granted == false) {
            print('❌ Notification Permission abgelehnt');
          } else {
            print('⚠️ Notification Permission bereits entschieden (granted=$granted)');
          }
        }
      } else if (Platform.isIOS) {
        // iOS permission request
        const DarwinInitializationSettings initializationSettingsIOS =
            DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        
        final InitializationSettings initializationSettings =
            InitializationSettings(iOS: initializationSettingsIOS);
        
        await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
        
        print('✓ iOS notification permissions requested');
      }
    } catch (e) {
      print('❌ Error requesting permissions: $e');
    }
  }
}


