import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';

/// Hilfsklasse für UI-Elemente
class UIUtils {
  /// Zeigt eine SnackBar nur an, wenn In-App Benachrichtigungen in den Einstellungen aktiviert sind.
  static void showSnackBar(BuildContext context, SnackBar snackBar) {
    if (AppSettingsService.inAppNotificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  /// Versteckt die aktuelle SnackBar
  static void hideCurrentSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }
}
