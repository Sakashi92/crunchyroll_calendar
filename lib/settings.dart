import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'services/crunchyroll_service.dart';
import 'services/background_service.dart';
import 'services/battery_optimization_service.dart';
import 'services/permission_service.dart';
import 'repositories/notification_repository.dart';
import 'models/notification_log.dart';

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
    return prefs.getBool(_autoTranslateKey) ?? true; // Standard: aktiviert
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
    return prefs.getInt(_notificationDelayKey) ?? 0; // Standard: 0 (sofort)
  }

  /// Speichert die Benachrichtigungs-Verzögerung in Sekunden
  static Future<void> setNotificationDelaySeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationDelayKey, seconds);
  }

  /// Lädt ob Aktualisierungsmeldungen angezeigt werden sollen
  static Future<bool> getShowRefreshMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showRefreshMessageKey) ?? true; // Standard: aktiviert
  }

  /// Speichert ob Aktualisierungsmeldungen angezeigt werden sollen
  static Future<void> setShowRefreshMessage(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRefreshMessageKey, enabled);
  }

  /// Lädt ob der Kalender beim Scroll automatisch minimiert werden soll
  static Future<bool> getAutoMinimizeCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoMinimizeCalendarKey) ?? true; // Standard: aktiviert
  }

  /// Speichert die Einstellung für automatisches Minimieren des Kalenders
  static Future<void> setAutoMinimizeCalendar(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoMinimizeCalendarKey, enabled);
  }

  /// Lädt den kumulativen Scroll-Schwellenwert (in Pixel) bevor der Kalender minimiert wird
  static Future<double> getAutoMinimizeScrollThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_autoMinimizeScrollThresholdKey) ?? 200.0; // Standard: 200px
  }

  /// Speichert den Scroll-Schwellenwert (in Pixel)
  static Future<void> setAutoMinimizeScrollThreshold(double pixels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_autoMinimizeScrollThresholdKey, pixels);
  }

  /// Lädt, ob doppelte Releases ausgeblendet werden sollen
  static Future<bool> getHideDuplicateReleases() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideDuplicateReleasesKey) ?? true; // Standard: an
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
    // entferne vorhandene Vorkommen
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
    return prefs.getInt(_watchlistSortModeKey) ?? 0; // default: addedAtDesc
  }

  /// Speichert die Sortier-Einstellung für die Watchlist (als Index des SortMode)
  static Future<void> setWatchlistSortModeIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_watchlistSortModeKey, index);
  }

  /// Lädt den aktuell gewählten Episode-Provider (z.B. 'crunchyroll' oder 'anilist')
  static Future<String> getEpisodeProviderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_episodeProviderKey) ?? 'crunchyroll';
  }

  /// Speichert den Episode-Provider Namen
  static Future<void> setEpisodeProviderName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_episodeProviderKey, name);
  }
}

/// Einstellungs-Seite
class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final CrunchyrollService? crunchyrollService;
  
  const SettingsPage({super.key, this.onSettingsChanged, this.crunchyrollService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _imageQuality = 'original';
  int _updateIntervalMinutes = 20;
  bool _autoTranslate = true;
  Color _accentColor = Colors.orange;
  int _notificationDelaySeconds = 0;
  bool _showRefreshMessage = true;
  bool _autoMinimizeCalendar = true;
  double _autoMinimizeScrollThreshold = 200.0;
  bool _hideDuplicateReleases = true;
  String _episodeProvider = 'crunchyroll';
  bool _isLoading = true;
  Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final imageQuality = await AppSettings.getImageQuality();
    final updateInterval = await AppSettings.getUpdateIntervalMinutes();
    final autoTranslate = await AppSettings.getAutoTranslate();
    final accentColor = await AppSettings.getAccentColor();
    final notificationDelay = await AppSettings.getNotificationDelaySeconds();
    final showRefreshMessage = await AppSettings.getShowRefreshMessage();
    final autoMinimizeCalendar = await AppSettings.getAutoMinimizeCalendar();
    final autoMinimizeScrollThreshold = await AppSettings.getAutoMinimizeScrollThreshold();
    final hideDuplicateReleases = await AppSettings.getHideDuplicateReleases();
    final episodeProvider = await AppSettings.getEpisodeProviderName();
    final permissions = await PermissionService().checkAllPermissions();
    
    setState(() {
      _imageQuality = imageQuality;
      _updateIntervalMinutes = updateInterval;
      _autoTranslate = autoTranslate;
      _accentColor = accentColor;
      _notificationDelaySeconds = notificationDelay;
      _showRefreshMessage = showRefreshMessage;
      _autoMinimizeCalendar = autoMinimizeCalendar;
      _autoMinimizeScrollThreshold = autoMinimizeScrollThreshold;
      _hideDuplicateReleases = hideDuplicateReleases;
      _episodeProvider = episodeProvider;
      _permissions = permissions;
      _isLoading = false;
    });
  }

  Future<void> _saveEpisodeProvider(String name) async {
    await AppSettings.setEpisodeProviderName(name);
    setState(() {
      _episodeProvider = name;
    });
    widget.onSettingsChanged?.call();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Datenanbieter gesetzt: $name'), duration: const Duration(seconds: 2)));
  }

  Future<void> _saveImageQuality(String quality) async {
    await AppSettings.setImageQuality(quality);
    setState(() {
      _imageQuality = quality;
    });
    widget.onSettingsChanged?.call();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bildqualität geändert. Neue Bilder werden in dieser Qualität geladen.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveUpdateInterval(int minutes) async {
    // Read previous saved value to decide whether to restart background task
    final previous = await AppSettings.getUpdateIntervalMinutes();
    await AppSettings.setUpdateIntervalMinutes(minutes);
    setState(() {
      _updateIntervalMinutes = minutes;
    });
    widget.onSettingsChanged?.call();
    // Restart background scraper only when effective interval increases above previous
    try {
      final prevEffective = previous < 15 ? 15 : previous;
      final newEffective = minutes < 15 ? 15 : minutes;
      if (newEffective > prevEffective) {
        await BackgroundService().stopPeriodicScraperTask();
        await BackgroundService().startPeriodicScraperTask(intervalMinutes: newEffective);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error restarting background service: $e');
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update-Intervall auf ${AppSettings.updateIntervals[minutes]} geändert.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAutoMinimizeCalendar(bool enabled) async {
    await AppSettings.setAutoMinimizeCalendar(enabled);
    setState(() {
      _autoMinimizeCalendar = enabled;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'Automatisches Minimieren aktiviert' : 'Automatisches Minimieren deaktiviert'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAutoMinimizeScrollThreshold(double pixels) async {
    await AppSettings.setAutoMinimizeScrollThreshold(pixels);
    setState(() {
      _autoMinimizeScrollThreshold = pixels;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scroll-Schwelle gesetzt: ${pixels.toStringAsFixed(0)} px'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveHideDuplicateReleases(bool enabled) async {
    await AppSettings.setHideDuplicateReleases(enabled);
    setState(() {
      _hideDuplicateReleases = enabled;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'Doppelte Releases werden ausgeblendet' : 'Doppelte Releases werden angezeigt'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearImageCache() async {
    // Lösche In-Memory-Cache im Service (wichtig!)
    if (widget.crunchyrollService != null) {
      await widget.crunchyrollService!.clearImageCache();
    } else {
      // Fallback: Nur SharedPreferences löschen
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_anime_images');
      await prefs.remove('processed_anime_titles_v4');
    }
    
    widget.onSettingsChanged?.call();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bild-Cache gelöscht. Bilder werden neu heruntergeladen.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _showNotificationDbOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('Historie anzeigen'),
                onTap: () {
                  Navigator.pop(context);
                  _showNotificationHistory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Datenbank leeren', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Datenbank leeren?'),
                      content: const Text('Alle gespeicherten Benachrichtigungen werden gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await NotificationRepository().deleteAllNotifications();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Benachrichtigungs‑DB geleert')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showNotificationHistory() async {
    final repo = NotificationRepository();
    final history = await repo.getHistory(limit: 200);

    if (kDebugMode) {
      print('📊 [SETTINGS] Loaded ${history.length} notification history entries from DB');
      if (history.isNotEmpty) {
        for (final entry in history.take(5)) {
          print('  - ${entry.favoriteTitle} / ${entry.releaseTitle} (ep: ${entry.episodeNumber}) @ ${entry.notifyTime}');
        }
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Benachrichtigungs‑Historie'),
        content: SizedBox(
          width: double.maxFinite,
          child: history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Einträge in der Benachrichtigungs‑DB',
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Benachrichtigungen werden hier gespeichert, nachdem sie versendet wurden.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return ListTile(
                      title: Text('${entry.favoriteTitle} — ${entry.releaseTitle}'),
                      subtitle: Text('Ep: ${entry.episodeNumber ?? '-'} • ${entry.notifyTime.toLocal().toString().split('.')[0]}'),
                      isThreeLine: false,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _testLogNotification() async {
    try {
      final repo = NotificationRepository();
      final testNotification = NotificationLog(
        favoriteTitle: 'Tune In to the Midnight Heart',
        releaseTitle: 'Episode 1',
        episodeNumber: '1',
        notifyTime: DateTime.now(),
        isShown: true,
      );

      final contentHash = testNotification.generateContentHash();
      final withHash = testNotification.copyWith(contentHash: contentHash);

      await repo.logNotification(withHash);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Test-Benachrichtigung geloggt (prüfe Logs: flutter logs)'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        
        if (kDebugMode) {
          print('✅ [TEST] Logged test notification:');
          print('   - favoriteTitle: ${testNotification.favoriteTitle}');
          print('   - releaseTitle: ${testNotification.releaseTitle}');
          print('   - episodeNumber: ${testNotification.episodeNumber}');
          print('   - contentHash: $contentHash');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fehler beim Loggen: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (kDebugMode) print('❌ [TEST] Error logging test notification: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Einstellungen'),
          backgroundColor: theme.colorScheme.surface,
          toolbarHeight: 48,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        backgroundColor: theme.colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          // Berechtigungen
          _buildSectionHeader('Berechtigungen'),
          _buildPermissionsOverviewTile(),
          // Hintergrund-Einstellungen
          _buildBatteryOptimizationTile(),

          const Divider(),

         // Anzeige
          _buildSectionHeader('Anzeige'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Kalender beim Scroll minimieren'),
              subtitle: const Text('Minimiert den Kalender-Header automatisch, wenn du in der Liste nach unten scrollst'),
              value: _autoMinimizeCalendar,
              onChanged: (v) => _saveAutoMinimizeCalendar(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Doppelte Releases ausblenden'),
              subtitle: const Text('Versteckt doppelte Einträge (gleiche Folge/URL) im Kalender'),
              value: _hideDuplicateReleases,
              onChanged: (v) => _saveHideDuplicateReleases(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Datenanbieter'),
              subtitle: Text('Aktuell: ${_episodeProvider}'),
              trailing: DropdownButton<String>(
                value: _episodeProvider,
                items: const [
                  DropdownMenuItem(value: 'crunchyroll', child: Text('Crunchyroll (Scraper)')),
                  DropdownMenuItem(value: 'anilist', child: Text('Anilist.co (GraphQL)')),
                ],
                onChanged: (v) {
                  if (v != null) _saveEpisodeProvider(v);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Scroll-Schwelle zum Minimieren'),
              subtitle: Text('Aktuell: ${_autoMinimizeScrollThreshold.toStringAsFixed(0)} px'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showScrollThresholdDialog(),
            ),
          ),
          _buildImageQualityTile(),
          _buildAccentColorTile(),
          
      //    const Divider(),
         
       //   const Divider(),
          
          // Bildqualität
    //      _buildSectionHeader('Bildqualität'),
   //       _buildImageQualityTile(),
          
          const Divider(),
          
          // Update-Intervall
          _buildSectionHeader('Aktualisierung'),
          _buildUpdateIntervalTile(),
          _buildShowRefreshMessageTile(),
          
          const Divider(),
          
          // Übersetzung
          _buildSectionHeader('Übersetzung'),
          _buildAutoTranslateTile(),
          
    //      const Divider(),
          
          // Accent-Farbe
  //        _buildSectionHeader('Design'),
   //       _buildAccentColorTile(),
          
          const Divider(),
          
          // Cache-Verwaltung
          _buildSectionHeader('Cache-Verwaltung'),
          _buildClearCacheTile(),
      if (kDebugMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Benachrichtigungs‑DB'),
              subtitle: const Text('Historie anzeigen oder Datenbank leeren'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotificationDbOptions(),
            ),
          ),
          
      if (kDebugMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('🧪 Test: Benachrichtigung loggen'),
                subtitle: const Text('Fügt eine Test-Benachrichtigung zur DB hinzu'),
                onTap: () => _testLogNotification(),
              ),
            ),
          
          const Divider(),
          
          // Test
      if (kDebugMode) _buildSectionHeader('Test'),
      if (kDebugMode) _buildNotificationDelayTile(),
      if (kDebugMode) _buildTestFavoritesNotificationsTile(),
      if (kDebugMode) _buildTestNotificationTile(),
      if (kDebugMode) _buildBackgroundTaskStatusTile(),
      if (kDebugMode) _buildWorkmanagerTestTile(),
      if (kDebugMode) _buildBackgroundScraperTestTile(),
          
      if (kDebugMode)    const Divider(),
          
          // Info
          _buildSectionHeader('Info'),
          _buildInfoTile(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildPermissionsOverviewTile() {
    // Zähle gewährte Permissions
    final grantedCount = _permissions.values.where((p) => p == PermissionStatus.granted).length;
    final totalCount = _permissions.length;
    final allGranted = grantedCount == totalCount;
    
    return ListTile(
      leading: Icon(
        allGranted ? Icons.verified : Icons.warning,
        color: allGranted ? Colors.green : Colors.orange,
      ),
      title: const Text('Status der Berechtigungen'),
      subtitle: Text('$grantedCount/$totalCount Berechtigungen aktiviert'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPermissionsDetailsDialog(),
    );
  }
  
  void _showPermissionsDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Berechtigungen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _permissions.entries.map((entry) {
              final name = entry.key;
              final status = entry.value;
              final description = PermissionService.getPermissionDescriptions()[name] ?? '';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: status.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                status.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (description.isNotEmpty)
                                Text(
                                  description,
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (entry != _permissions.entries.last)
                      const Divider(height: 16),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Aktualisiere die Permissions
              final permissions = await PermissionService().checkAllPermissions();
              setState(() {
                _permissions = permissions;
              });
            },
            child: const Text('Aktualisieren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageQualityTile() {
    return ListTile(
      leading: const Icon(Icons.high_quality),
      title: const Text('Cover-Bildqualität'),
      subtitle: Text(AppSettings.imageQualities[_imageQuality] ?? 'Unbekannt'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageQualityDialog(),
    );
  }

  Widget _buildUpdateIntervalTile() {
    return ListTile(
      leading: const Icon(Icons.refresh),
      title: const Text('Update-Intervall'),
      subtitle: Text(
        'Crunchyroll wird alle ${AppSettings.updateIntervals[_updateIntervalMinutes]} auf neue Einträge überprüft',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showUpdateIntervalDialog(),
    );
  }

  Widget _buildAutoTranslateTile() {
    return SwitchListTile(
      secondary: const Icon(Icons.translate),
      title: const Text('Automatische Übersetzung'),
      subtitle: const Text('Beschreibungen automatisch ins Deutsche übersetzen'),
      value: _autoTranslate,
      onChanged: (value) async {
        await AppSettings.setAutoTranslate(value);
        setState(() {
          _autoTranslate = value;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value 
                  ? 'Beschreibungen werden automatisch übersetzt'
                  : 'Beschreibungen bleiben im Original',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  Widget _buildClearCacheTile() {
    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: const Text('Bild-Cache löschen'),
      subtitle: const Text('Alle gecachten Cover-Bilder löschen und neu laden'),
      onTap: () => _showClearCacheDialog(),
    );
  }

  Widget _buildBatteryOptimizationTile() {
    // Nur auf Android anzeigen
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    
    return ListTile(
      leading: Icon(Icons.battery_saver, color: Colors.orange.shade700),
      title: const Text('Akku-Optimierung'),
      subtitle: const Text('Einstellungen für Hintergrund-Benachrichtigungen'),
      trailing: const Icon(Icons.open_in_new),
      onTap: () async {
        await BatteryOptimizationService.showBatteryOptimizationDialog(context);
      },
    );
  }

  Widget _buildShowRefreshMessageTile() {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_none),
      title: const Text('Aktualisierungsmeldung'),
      subtitle: const Text('Meldung nach dem Aktualisieren anzeigen'),
      value: _showRefreshMessage,
      onChanged: (value) async {
        await AppSettings.setShowRefreshMessage(value);
        setState(() {
          _showRefreshMessage = value;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value 
                  ? 'Meldung wird nach Aktualisierung angezeigt'
                  : 'Meldung wird nicht mehr angezeigt',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  Widget _buildTestNotificationTile() {
    return ListTile(
      leading: const Icon(Icons.notifications_active),
      title: const Text('Test Benachrichtigung'),
      subtitle: const Text('Benachrichtigung mit Verzögerung senden'),
      onTap: () => _showDelayedNotificationDialog(),
    );
  }

  void _showDelayedNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Benachrichtigung'),
        content: const Text('Wähle die Verzögerung bevor die Benachrichtigung erscheint:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendDelayedNotification(5);
            },
            child: const Text('5 Sekunden'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendDelayedNotification(10);
            },
            child: const Text('10 Sekunden'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendDelayedNotification(30);
            },
            child: const Text('30 Sekunden'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendDelayedNotification(60);
            },
            child: const Text('1 Minute'),
          ),
        ],
      ),
    );
  }

  void _sendDelayedNotification(int seconds) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏱️ Background-Test geplant für $seconds Sekunden\n✅ Funktioniert auch wenn App geschlossen ist!'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
    }

    // Verwende Workmanager für echte Background-Benachrichtigung
    final backgroundService = BackgroundService();
    await backgroundService.scheduleTestNotification(seconds);

    if (kDebugMode) {
      print('✓ Background test notification scheduled for $seconds seconds');
    }
  }

  Widget _buildBackgroundTaskStatusTile() {
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Background Task Status'),
      subtitle: const Text('Prüft ob Background-Scraping läuft'),
      onTap: () async {
        final backgroundService = BackgroundService();
        final isRunning = await backgroundService.isTaskRunning();
        
        if (kDebugMode) {
          print('📊 Background Task Status: ${isRunning ? 'Running ✓' : 'Stopped ✗'}');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRunning 
                  ? '✓ Background Task läuft (30 Min Intervall)' 
                  : '✗ Background Task nicht aktiv',
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: isRunning ? Colors.green : Colors.orange,
            ),
          );
        }
      },
    );
  }

  Widget _buildTestFavoritesNotificationsTile() {
    final delayText = AppSettings.notificationDelays[_notificationDelaySeconds] ?? 'Sofort';
    return ListTile(
      leading: const Icon(Icons.notifications_active),
      title: const Text('🔔 Test: Favoriten-Benachrichtigungen'),
      subtitle: Text('Verzögerung: $delayText'),
      onTap: () async {
        // Zeige Loading mit Verzögerungsinfo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⏳ Benachrichtigung in $delayText...'),
              duration: const Duration(seconds: 1),
            ),
          );
        }

        try {
          final backgroundService = BackgroundService();
          await backgroundService.sendTestNotificationsForTodaysFavorites(delaySeconds: _notificationDelaySeconds);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Benachrichtigung geplant (in $delayText)'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
          if (kDebugMode) print('❌ Error sending test notifications: $e');
        }
      },
    );
  }

  Widget _buildWorkmanagerTestTile() {
    return ListTile(
      leading: const Icon(Icons.schedule_send),
      title: const Text('🧪 Test: Workmanager (Sofort)'),
      subtitle: const Text('Testet ob Workmanager im Hintergrund funktioniert (1-2 Sekunden)'),
      onTap: () async {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏳ Starte Workmanager Test...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        try {
          final backgroundService = BackgroundService();
          await backgroundService.testWorkmanagerNow();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Workmanager Test gestartet - prüfe Logs in 2-3 Sekunden'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
          if (kDebugMode) print('❌ Error testing Workmanager: $e');
        }
      },
    );
  }

  Widget _buildBackgroundScraperTestTile() {
    return ListTile(
      leading: const Icon(Icons.sync),
      title: const Text('🔄 Test: Background Scraper'),
      subtitle: const Text('Testet ob der periodische Crunchyroll-Scraper funktioniert'),
      onTap: () async {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⏳ Starte Background Scraper Test...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        try {
          final backgroundService = BackgroundService();
          await backgroundService.testBackgroundScraperNow();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Background Scraper gestartet - schließe App und prüfe Logs'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
          if (kDebugMode) print('❌ Error testing background scraper: $e');
        }
      },
    );
  }

  Widget _buildNotificationDelayTile() {
    return ListTile(
      leading: const Icon(Icons.schedule),
      title: const Text('Benachrichtigungs-Verzögerung'),
      subtitle: Text('${AppSettings.notificationDelays[_notificationDelaySeconds] ?? 'Sofort'}'),
      trailing: DropdownButton<int>(
        value: _notificationDelaySeconds,
        underline: Container(),
        items: AppSettings.notificationDelays.entries.map((entry) {
          return DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
        onChanged: (int? newValue) async {
          if (newValue != null) {
            await AppSettings.setNotificationDelaySeconds(newValue);
            setState(() {
              _notificationDelaySeconds = newValue;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ Verzögerung auf ${AppSettings.notificationDelays[newValue]} eingestellt'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildInfoTile() {
    return const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Crunchyroll Kalender'),
      subtitle: Text('Version 0.8.0\nBilder werden von MyAnimeList.net geladen'),
      isThreeLine: true,
    );
  }

  void _showImageQualityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bildqualität wählen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppSettings.imageQualities.entries.map((entry) {
            return RadioListTile<String>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: _imageQuality,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveImageQuality(value);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  void _showScrollThresholdDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scroll-Schwelle wählen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<double>(
              title: const Text('Niedrig (100 px)'),
              value: 100.0,
              groupValue: _autoMinimizeScrollThreshold,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(value);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Standard (200 px)'),
              value: 200.0,
              groupValue: _autoMinimizeScrollThreshold,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(value);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Hoch (300 px)'),
              value: 300.0,
              groupValue: _autoMinimizeScrollThreshold,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(value);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Sehr hoch (500 px)'),
              value: 500.0,
              groupValue: _autoMinimizeScrollThreshold,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(value);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  void _showUpdateIntervalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update-Intervall wählen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppSettings.updateIntervals.entries.map((entry) {
            return RadioListTile<int>(
              title: Text(entry.value),
              value: entry.key,
              groupValue: _updateIntervalMinutes,
              onChanged: (value) {
                if (value != null) {
                  Navigator.pop(context);
                  _saveUpdateInterval(value);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bild-Cache löschen?'),
        content: const Text(
          'Alle gecachten Cover-Bilder werden gelöscht und beim nächsten Laden in der aktuell eingestellten Qualität neu heruntergeladen.\n\n'
          'Dies kann je nach Anzahl der Anime einige Zeit dauern.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearImageCache();
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentColorTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Accent-Farbe',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppSettings.accentColors.map((color) {
              final isSelected = _accentColor.value == color.value;
              return GestureDetector(
                onTap: () => _selectAccentColor(color),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.grey.shade800,
                            width: 3,
                          ),
                        ),
                      ),
                    if (isSelected)
                      Icon(
                        Icons.check,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: 28,
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAccentColor(Color color) async {
    await AppSettings.setAccentColor(color);
    setState(() {
      _accentColor = color;
    });
    widget.onSettingsChanged?.call();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Accent-Farbe geändert'),
          duration: const Duration(seconds: 1),
          backgroundColor: color,
        ),
      );
    }
  }}