import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:device_info_plus/device_info_plus.dart';

enum PermissionStatus {
  granted('Aktiviert', Color(0xFF4CAF50)),
  denied('Deaktiviert', Color(0xFFf44336)),
  restricted('Eingeschränkt', Color(0xFFFFC107)),
  unknown('Unbekannt', Color(0xFF9E9E9E));

  final String label;
  final Color color;

  const PermissionStatus(this.label, this.color);
}

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _platform = MethodChannel(
    'de.sakashi.crunchyroll_calendar/battery',
  );

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

        await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
        );

        // Request permission by trying to show a notification
        // This will trigger the permission dialog on Android 13+
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();

        if (androidImplementation != null) {
          // Android 13+ (API 33+): Explizit POST_NOTIFICATIONS Permission anfragen
          final bool? granted = await androidImplementation
              .requestNotificationsPermission();

          if (granted == true) {
            if (kDebugMode) print('✅ Notification Permission erteilt');

            // Erstelle Notification Channel
            const AndroidNotificationChannel channel =
                AndroidNotificationChannel(
                  'permission_request_channel',
                  'Permission Requests',
                  description: 'Used for initial permission request',
                  importance: Importance.high,
                );
            await androidImplementation.createNotificationChannel(channel);
          } else if (granted == false) {
            if (kDebugMode) print('❌ Notification Permission abgelehnt');
          } else {
            if (kDebugMode) {
              print(
                '⚠️ Notification Permission bereits entschieden (granted=$granted)',
              );
            }
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

        await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
        );

        if (kDebugMode) print('✓ iOS notification permissions requested');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error requesting permissions: $e');
    }
  }

  /// Prüft den Status aller Permissions
  Future<Map<String, PermissionStatus>> checkAllPermissions() async {
    final Map<String, PermissionStatus> permissions = {};

    try {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();

        // Benachrichtigungen
        if (androidImplementation != null) {
          final bool? granted = await androidImplementation
              .areNotificationsEnabled();
          if (granted == true) {
            permissions['Benachrichtigungen'] = PermissionStatus.granted;
          } else if (granted == false) {
            permissions['Benachrichtigungen'] = PermissionStatus.denied;
          } else {
            permissions['Benachrichtigungen'] = PermissionStatus.unknown;
          }
        } else {
          permissions['Benachrichtigungen'] = PermissionStatus.unknown;
        }

        // Weitere Permissions die wir benötigen
        permissions['Internet'] =
            PermissionStatus.granted; // Wird über AndroidManifest geprüft

        // Hintergrund-Ausführung: prüfe ob das System Hintergrund-Restriktionen aktiv hat
        try {
          final bool? bgRestricted = await _platform.invokeMethod<bool>(
            'isBackgroundRestricted',
          );
          if (bgRestricted == true) {
            permissions['Hintergrund-Ausführung'] = PermissionStatus.restricted;
          } else if (bgRestricted == false) {
            permissions['Hintergrund-Ausführung'] = PermissionStatus.granted;
          } else {
            permissions['Hintergrund-Ausführung'] = PermissionStatus.unknown;
          }
        } catch (e) {
          permissions['Hintergrund-Ausführung'] = PermissionStatus.unknown;
        }

        // Akku-Optimierung: prüfe ob die App von Optimierungen ausgenommen ist
        try {
          final bool? isIgnoring = await _platform.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          );
          if (isIgnoring == true) {
            permissions['Akku-Optimierung'] = PermissionStatus.granted;
          } else if (isIgnoring == false) {
            permissions['Akku-Optimierung'] = PermissionStatus.denied;
          } else {
            permissions['Akku-Optimierung'] = PermissionStatus.unknown;
          }
        } catch (e) {
          permissions['Akku-Optimierung'] = PermissionStatus.unknown;
        }

        // Speicherzugriff prüfen
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.version.sdkInt >= 30) {
          if (await ph.Permission.manageExternalStorage.isGranted) {
            permissions['Speicherzugriff'] = PermissionStatus.granted;
          } else {
            permissions['Speicherzugriff'] = PermissionStatus.denied;
          }
        } else {
          if (await ph.Permission.storage.isGranted) {
            permissions['Speicherzugriff'] = PermissionStatus.granted;
          } else {
            permissions['Speicherzugriff'] = PermissionStatus.denied;
          }
        }
      } else if (Platform.isIOS) {
        permissions['Benachrichtigungen'] = PermissionStatus.granted;
      }
    } catch (e) {
      if (kDebugMode) print('Error checking permissions: $e');
    }

    return permissions;
  }

  /// Prüft und fragt Storage Permission an
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Android 11+ (API 30+)
      if (androidInfo.version.sdkInt >= 30) {
        var status = await ph.Permission.manageExternalStorage.status;
        if (status.isGranted) return true;

        status = await ph.Permission.manageExternalStorage.request();
        return status.isGranted;
      }
      // Android 10 (API 29) & darunter
      else {
        var status = await ph.Permission.storage.status;
        if (status.isGranted) return true;

        status = await ph.Permission.storage.request();
        return status.isGranted;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error requesting storage permission: $e');
      return false;
    }
  }

  /// Gibt eine lesbare Beschreibung für jede Permission
  static Map<String, String> getPermissionDescriptions() => {
    'Benachrichtigungen': 'Benötigt um Push-Benachrichtigungen zu erhalten',
    'Internet': 'Benötigt um Anime-Daten zu laden',
    'Hintergrund-Ausführung':
        'Benötigt für regelmäßige Benachrichtigungen im Hintergrund',
    'Akku-Optimierung':
        'Muss deaktiviert sein damit Hintergrund-Tasks funktionieren',
    'Speicherzugriff': 'Benötigt für Backups (Android)',
  };
}
