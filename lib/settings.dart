import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

/// Einstellungen für die App
class AppSettings {
  static const String _imageQualityKey = 'image_quality';
  static const String _updateIntervalKey = 'update_interval_minutes';
  static const String _autoTranslateKey = 'auto_translate';
  static const String _accentColorKey = 'accent_color';
  static const String _notificationDelayKey = 'notification_delay_seconds';
  static const String _showRefreshMessageKey = 'show_refresh_message';
  static const String _autoMinimizeCalendarKey = 'auto_minimize_calendar';
  static const String _autoMinimizeScrollThresholdKey = 'auto_minimize_scroll_threshold';
  static const String _hideDuplicateReleasesKey = 'hide_duplicate_releases';
  static const String _searchHistoryKey = 'search_history';
  static const String _watchlistSortModeKey = 'watchlist_sort_mode';
  static const String _episodeProviderKey = 'episode_provider';
  static const String _predictionEnabledKey = 'enable_next_episode_prediction';
  
  /// Verfügbare Bildqualitäten
  static const Map<String, String> imageQualities = {
    'original': 'Original (Höchste Qualität, ~2000x3000)',
    'large': 'Groß (~550x780)',
    'medium': 'Mittel (~390x554)',
    'small': 'Klein (~284x402)',
  };
  
  /// Verfügbare Update-Intervalle in Minuten
  static const Map<int, String> updateIntervals = {
    1: '1 Minute',
    2: '2 Minuten',
    5: '5 Minuten',
    10: '10 Minuten',
    15: '15 Minuten',
    20: '20 Minuten',
    30: '30 Minuten',
    60: '1 Stunde',
  };

  /// Verfügbare Verzögerungen für Benachrichtigungen in Sekunden
  static const Map<int, String> notificationDelays = {
    0: 'Sofort',
    10: '10 Sekunden',
    30: '30 Sekunden',
    60: '1 Minute',
    300: '5 Minuten',
    600: '10 Minuten',
  };
  
  /// Vordefinierte Accent-Farben
  static const List<Color> accentColors = [
    Colors.orange,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.amber,
  ];
  
  /// Lädt die aktuelle Bildqualität
  static Future<String> getImageQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_imageQualityKey) ?? 'original';
  }
  
  /// Speichert die Bildqualität
  static Future<void> setImageQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageQualityKey, quality);
  }
  
  /// Lädt das Update-Intervall in Minuten
  static Future<int> getUpdateIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_updateIntervalKey) ?? 20;
  }
  
  /// Speichert das Update-Intervall in Minuten
  static Future<void> setUpdateIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_updateIntervalKey, minutes);
  }
  
  /// Lädt das Update-Intervall als Duration
  static Future<Duration> getUpdateInterval() async {
    final minutes = await getUpdateIntervalMinutes();
    return Duration(minutes: minutes);
  }
  
  /// Lädt die automatische Übersetzung-Einstellung
  static Future<bool> getAutoTranslate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoTranslateKey) ?? true;
  }
  
  /// Speichert die automatische Übersetzung-Einstellung
  static Future<void> setAutoTranslate(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoTranslateKey, enabled);
  }
  
  /// Lädt die Accent-Farbe
  static Future<Color> getAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_accentColorKey) ?? Colors.orange.value;
    return Color(colorValue);
  }
  
  /// Speichert die Accent-Farbe
  static Future<void> setAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.value);
  }

  /// Lädt die Benachrichtigungs-Verzögerung in Sekunden
  static Future<int> getNotificationDelaySeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notificationDelayKey) ?? 0;
  }

  /// Speichert die Benachrichtigungs-Verzögerung in Sekunden
  static Future<void> setNotificationDelaySeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationDelayKey, seconds);
  }

  /// Lädt ob Aktualisierungsmeldungen angezeigt werden sollen
  static Future<bool> getShowRefreshMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showRefreshMessageKey) ?? true;
  }

  /// Speichert ob Aktualisierungsmeldungen angezeigt werden sollen
  static Future<void> setShowRefreshMessage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRefreshMessageKey, enabled);
  }

  /// Lädt ob der Kalender beim Scroll automatisch minimiert werden soll
  static Future<bool> getAutoMinimizeCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoMinimizeCalendarKey) ?? true;
  }

  /// Speichert die Einstellung für automatisches Minimieren des Kalenders
  static Future<void> setAutoMinimizeCalendar(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoMinimizeCalendarKey, enabled);
  }

  /// Lädt den kumulativen Scroll-Schwellenwert (in Pixel) bevor der Kalender minimiert wird
  static Future<double> getAutoMinimizeScrollThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_autoMinimizeScrollThresholdKey) ?? 200.0;
  }

  /// Speichert den Scroll-Schwellenwert (in Pixel)
  static Future<void> setAutoMinimizeScrollThreshold(double pixels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_autoMinimizeScrollThresholdKey, pixels);
  }

  /// Lädt, ob doppelte Releases ausgeblendet werden sollen
  static Future<bool> getHideDuplicateReleases() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideDuplicateReleasesKey) ?? true;
  }

  /// Speichert die Einstellung zum Ausblenden doppelter Releases
  static Future<void> setHideDuplicateReleases(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideDuplicateReleasesKey, enabled);
  }

  /// Lädt den Suchverlauf (neueste zuerst)
  static Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_searchHistoryKey)?.toList() ?? <String>[];
  }

  /// Fügt einen Eintrag zum Suchverlauf hinzu (an den Anfang). Max-Größe: 20
  static Future<void> addToSearchHistory(String term) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = term.trim();
    if (normalized.isEmpty) return;
    final list = prefs.getStringList(_searchHistoryKey)?.toList() ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == normalized.toLowerCase());
    list.insert(0, normalized);
    if (list.length > 20) list.removeRange(20, list.length);
    await prefs.setStringList(_searchHistoryKey, list);
  }

  /// Löscht den Suchverlauf
  static Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }

  /// Lädt die gespeicherte Sortier-Einstellung für die Watchlist (als Index des SortMode)
  static Future<int> getWatchlistSortModeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_watchlistSortModeKey) ?? 0;
  }

  /// Speichert die Sortier-Einstellung für die Watchlist (als Index des SortMode)
  static Future<void> setWatchlistSortModeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_watchlistSortModeKey, index);
  }

  /// Lädt den aktuell gewählten Episode-Provider (z.B. 'crunchyroll' oder 'anilist')
  static Future<String> getEpisodeProviderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_episodeProviderKey) ?? 'anilist';
  }

  /// Speichert den Episode-Provider Namen
  static Future<void> setEpisodeProviderName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_episodeProviderKey, name);
  }

  /// Lädt ob die Vorhersage für nächste Episoden aktiviert ist
  static Future<bool> getPredictionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_predictionEnabledKey) ?? true;
  }

  /// Speichert ob die Vorhersage für nächste Episoden aktiviert ist
  static Future<void> setPredictionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_predictionEnabledKey, enabled);
  }
}