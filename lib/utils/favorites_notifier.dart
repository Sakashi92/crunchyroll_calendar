import 'package:flutter/material.dart';

/// Global ValueNotifier für Favoriten-Änderungen
/// Wird verwendet um alle Widgets zu benachrichtigen wenn sich Favoriten ändern
final favoritesChangeNotifier = ValueNotifier<int>(0);
