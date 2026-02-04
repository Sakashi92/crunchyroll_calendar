import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/crunchyroll_service.dart';
import '../services/background_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/anilist_service.dart';
import '../services/next_episode_predictor.dart';
import '../services/prediction_notifier.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../services/permission_service.dart';
import '../repositories/notification_repository.dart';
import '../models/notification_log.dart';
import '../services/app_settings_service.dart';
import '../services/backup_service.dart';
import '../widgets/import_selection_dialog.dart';
import '../utils/ui_utils.dart';

/// Einstellungs-Seite
class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final CrunchyrollService? crunchyrollService;

  const SettingsPage({
    super.key,
    this.onSettingsChanged,
    this.crunchyrollService,
  });

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
  String _episodeProvider = 'anilist';
  bool _predictionEnabled = false;
  bool _preferCrunchyrollEpisodeCount = false;

  bool _isLoading = true;
  Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final imageQuality = await AppSettingsService.getImageQuality();
    final updateInterval = await AppSettingsService.getUpdateIntervalMinutes();
    final autoTranslate = await AppSettingsService.getAutoTranslate();
    final accentColor = await AppSettingsService.getAccentColor();
    final notificationDelay =
        await AppSettingsService.getNotificationDelaySeconds();
    final showRefreshMessage = await AppSettingsService.getShowRefreshMessage();
    final autoMinimizeCalendar =
        await AppSettingsService.getAutoMinimizeCalendar();
    final autoMinimizeScrollThreshold =
        await AppSettingsService.getAutoMinimizeScrollThreshold();
    final hideDuplicateReleases =
        await AppSettingsService.getHideDuplicateReleases();
    final episodeProvider = await AppSettingsService.getEpisodeProviderName();
    final predictionEnabled = await AppSettingsService.getPredictionEnabled();
    final preferCrunchyrollEpisodeCount =
        await AppSettingsService.getPreferCrunchyrollEpisodeCount();

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
      _predictionEnabled = predictionEnabled;
      _preferCrunchyrollEpisodeCount = preferCrunchyrollEpisodeCount;

      _permissions = permissions;
      _isLoading = false;
    });
  }

  Future<void> _saveEpisodeProvider(String name) async {
    await AppSettingsService.setEpisodeProviderName(name);
    setState(() {
      _episodeProvider = name;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text('Datenanbieter gesetzt: $name'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveImageQuality(String quality) async {
    await AppSettingsService.setImageQuality(quality);
    setState(() {
      _imageQuality = quality;
    });
    widget.onSettingsChanged?.call();

    if (mounted) {
      UIUtils.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Bildqualität geändert. Neue Bilder werden in dieser Qualität geladen.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveUpdateInterval(int minutes) async {
    final previous = await AppSettingsService.getUpdateIntervalMinutes();
    await AppSettingsService.setUpdateIntervalMinutes(minutes);
    setState(() {
      _updateIntervalMinutes = minutes;
    });
    widget.onSettingsChanged?.call();
    try {
      final prevEffective = previous < 15 ? 15 : previous;
      final newEffective = minutes < 15 ? 15 : minutes;
      if (newEffective != prevEffective) {
        await BackgroundService().stopPeriodicScraperTask();
        await BackgroundService().startPeriodicScraperTask(
          intervalMinutes: newEffective,
        );
        if (widget.crunchyrollService != null) {
          widget.crunchyrollService!.restartAutoUpdate(() {
            if (mounted) _loadSettings();
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error restarting background service or auto-update: $e');
      }
    }

    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Update-Intervall auf ${AppSettingsService.updateIntervals[minutes]} geändert.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAutoMinimizeCalendar(bool enabled) async {
    await AppSettingsService.setAutoMinimizeCalendar(enabled);
    setState(() {
      _autoMinimizeCalendar = enabled;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            enabled
                ? 'Automatisches Minimieren aktiviert'
                : 'Automatisches Minimieren deaktiviert',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAutoMinimizeScrollThreshold(double pixels) async {
    await AppSettingsService.setAutoMinimizeScrollThreshold(pixels);
    setState(() {
      _autoMinimizeScrollThreshold = pixels;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Scroll-Schwelle gesetzt: ${pixels.toStringAsFixed(0)} px',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveHideDuplicateReleases(bool enabled) async {
    await AppSettingsService.setHideDuplicateReleases(enabled);
    setState(() {
      _hideDuplicateReleases = enabled;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            enabled
                ? 'Doppelte Releases werden ausgeblendet'
                : 'Doppelte Releases werden angezeigt',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _savePreferCrunchyrollEpisodeCount(bool enabled) async {
    await AppSettingsService.setPreferCrunchyrollEpisodeCount(enabled);
    setState(() {
      _preferCrunchyrollEpisodeCount = enabled;
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _savePredictionEnabled(bool enabled) async {
    await AppSettingsService.setPredictionEnabled(enabled);
    setState(() {
      _predictionEnabled = enabled;
    });
    if (kDebugMode) {
      print(
        '🔎 [SETTINGS] Toggling predictions: ${enabled ? 'ENABLED' : 'DISABLED'}',
      );
    }
    if (enabled) {
      try {
        if (kDebugMode) {
          print('🔎 [SETTINGS] Preparing CrunchyrollService and predictor...');
        }
        final cs = widget.crunchyrollService ?? CrunchyrollService();
        await cs.removeAllPredictedReleases();
        await cs.loadCacheOnStartup();
        final anilist = AnilistService();
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(
              content: Text(
                'Vorhersage läuft... Dies kann einige Minuten dauern.',
              ),
            ),
          );
        }
        WatchlistService? ws;
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('watchlist_data');
          if (raw != null) {
            final wlObj = Watchlist();
            ws = WatchlistService(wlObj);
            await ws.loadWatchlist();
          }
        } catch (e) {
          if (kDebugMode) {
            print('🔎 [SETTINGS] Could not load watchlist entries: $e');
          }
        }
        await anilist.refreshMetadataForCrunchyroll(
          cs,
          usePredictDelay: true,
          entries: ws?.watchlist.entries,
        );
        try {
          if (ws != null) {
            final created = await ws.generateForecastForAllEntries();
            if (kDebugMode) {
              print(
                '🔎 [SETTINGS] Created $created predictions for watchlist entries',
              );
            }
            if (mounted) {
              UIUtils.showSnackBar(
                context,
                SnackBar(content: Text('Vorhersagen erstellt: $created')),
              );
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print(
              '🔎 [SETTINGS] Error running watchlist-based predictions: $e',
            );
          }
        }
        try {
          predictionsUpdated.value = true;
        } catch (_) {}
        widget.onSettingsChanged?.call();
      } catch (e) {
        if (kDebugMode) print('Error triggering predictor from settings: $e');
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            SnackBar(content: Text('Fehler beim Ausführen der Vorhersage: $e')),
          );
        }
      }
    } else {
      try {
        final cs = widget.crunchyrollService ?? CrunchyrollService();
        await cs.removeAllPredictedReleases();
        try {
          predictionsUpdated.value = true;
        } catch (_) {}
      } catch (e) {
        if (kDebugMode) {
          print('Error removing predicted releases from settings: $e');
        }
      }
    }
    widget.onSettingsChanged?.call();
  }

  Future<void> _clearImageCache() async {
    final cs = widget.crunchyrollService ?? CrunchyrollService();
    try {
      await cs.clearImageCache();
    } catch (e) {
      if (kDebugMode) print('Error clearing in-memory image cache: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_anime_images');
      await prefs.remove('processed_anime_titles_v4');
    } catch (e) {
      if (kDebugMode) print('Error clearing image cache in prefs: $e');
    }
    try {
      await cs.loadCacheOnStartup();
    } catch (e) {
      if (kDebugMode) print('Error reloading CrunchyrollService cache: $e');
    }
    try {
      final predictionEnabled = await AppSettingsService.getPredictionEnabled();
      if (predictionEnabled) {
        try {
          await cs.removeAllPredictedReleases();
        } catch (_) {}
        final predictor = NextEpisodePredictor(cs, AnilistService());
        await predictor.predictForAllKnownSeries();
        try {
          predictionsUpdated.value = true;
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error re-running predictions after clearing image cache: $e');
      }
    }
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Bild-Cache gelöscht. Kalender und Vorhersage werden neu geladen.',
          ),
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
                title: const Text(
                  'Datenbank leeren',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Datenbank leeren?'),
                      content: const Text(
                        'Alle gespeicherten Benachrichtigungen werden gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Abbrechen'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Löschen',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await NotificationRepository().deleteAllNotifications();
                    if (context.mounted) {
                      UIUtils.showSnackBar(
                        context,
                        const SnackBar(
                          content: Text('Benachrichtigungs‑DB geleert'),
                        ),
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
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Keine Einträge in der Benachrichtigungs‑DB',
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return ListTile(
                      title: Text(
                        '${entry.favoriteTitle} — ${entry.releaseTitle}',
                      ),
                      subtitle: Text(
                        'Ep: ${entry.episodeNumber ?? '-'} • ${entry.notifyTime.toLocal().toString().split('.')[0]}',
                      ),
                      isThreeLine: false,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
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
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: const Text(
              '✅ Test-Benachrichtigung geloggt (prüfe Logs: flutter logs)',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('❌ Fehler beim Loggen: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        body: const Center(child: CircularProgressIndicator()),
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
          _buildSectionHeader('Berechtigungen'),
          _buildPermissionsOverviewTile(),
          _buildBatteryOptimizationTile(),
          const Divider(),
          _buildSectionHeader('Anzeige'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Kalender beim Scroll minimieren'),
              subtitle: const Text(
                'Minimiert den Kalender-Header automatisch, wenn du in der Liste nach unten scrollst',
              ),
              value: _autoMinimizeCalendar,
              onChanged: (v) => _saveAutoMinimizeCalendar(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Doppelte Releases ausblenden'),
              subtitle: const Text(
                'Versteckt doppelte Einträge (gleiche Folge/URL) im Kalender',
              ),
              value: _hideDuplicateReleases,
              onChanged: (v) => _saveHideDuplicateReleases(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Aktuelle Episodenanzahl bevorzugen'),
              subtitle: const Text(
                'Zeigt nur die Anzahl der bereits veröffentlichten Folgen an (Kalender), statt der geplanten Gesamtanzahl (Info-Datenbank)',
              ),
              value: _preferCrunchyrollEpisodeCount,
              onChanged: (v) => _savePreferCrunchyrollEpisodeCount(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Datenanbieter'),
              subtitle: Text('Aktuell: $_episodeProvider'),
              trailing: DropdownButton<String>(
                value: _episodeProvider,
                items: const [
                  DropdownMenuItem(
                    value: 'crunchyroll',
                    child: Text('Kitsu.app'),
                  ),
                  DropdownMenuItem(
                    value: 'anilist',
                    child: Text('Anilist.co (GraphQL)'),
                  ),
                  DropdownMenuItem(
                    value: 'jikan',
                    child: Text('MyAnimeList (via Jikan)'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    _saveEpisodeProvider(v);
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Scroll-Schwelle zum Minimieren'),
              subtitle: Text(
                'Aktuell: ${_autoMinimizeScrollThreshold.toStringAsFixed(0)} px',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showScrollThresholdDialog(),
            ),
          ),
          _buildImageQualityTile(),
          _buildAccentColorTile(),
          const Divider(),
          _buildSectionHeader('Aktualisierung'),
          _buildUpdateIntervalTile(),
          _buildShowRefreshMessageTile(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Vorhersage für nächste Episoden'),
              subtitle: const Text(
                'Verwendet lokale Release-Historie und AniList, um nächste Episoden zu prognostizieren',
              ),
              trailing: Transform.translate(
                offset: const Offset(7, 0),
                child: Switch(
                  value: _predictionEnabled,
                  onChanged: (v) => _savePredictionEnabled(v),
                ),
              ),
              onTap: () => _savePredictionEnabled(!_predictionEnabled),
            ),
          ),
          const Divider(),

          _buildSectionHeader('Übersetzung'),
          _buildAutoTranslateTile(),
          const Divider(),
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
                subtitle: const Text(
                  'Fügt eine Test-Benachrichtigung zur DB hinzu',
                ),
                onTap: () => _testLogNotification(),
              ),
            ),
          const Divider(),
          if (kDebugMode) _buildSectionHeader('Test'),
          if (kDebugMode) _buildNotificationDelayTile(),
          if (kDebugMode) _buildTestFavoritesNotificationsTile(),
          if (kDebugMode) _buildTestNotificationTile(),
          if (kDebugMode) _buildBackgroundTaskStatusTile(),
          if (kDebugMode) _buildWorkmanagerTestTile(),
          if (kDebugMode) _buildBackgroundScraperTestTile(),
          if (kDebugMode) const Divider(),
          _buildSectionHeader('Datensicherung'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Daten exportieren'),
              subtitle: const Text(
                'Erstelle ein Backup deiner Einstellungen und Watchlist',
              ),
              onTap: () => _handleExport(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.download_for_offline),
              title: const Text('Daten importieren'),
              subtitle: const Text('Stelle Daten aus einem Backup wieder her'),
              onTap: () => _handleImport(),
            ),
          ),
          const Divider(),
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
    final grantedCount = _permissions.values
        .where((p) => p == PermissionStatus.granted)
        .length;
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
              final description =
                  PermissionService.getPermissionDescriptions()[name] ?? '';

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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
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
              final permissions = await PermissionService()
                  .checkAllPermissions();
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
      subtitle: Text(
        AppSettingsService.imageQualities[_imageQuality] ?? 'Unbekannt',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageQualityDialog(),
    );
  }

  Widget _buildUpdateIntervalTile() {
    return ListTile(
      leading: const Icon(Icons.refresh),
      title: const Text('Update-Intervall'),
      subtitle: Text(
        'Crunchyroll wird alle ${AppSettingsService.updateIntervals[_updateIntervalMinutes]} auf neue Einträge überprüft',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showUpdateIntervalDialog(),
    );
  }

  Widget _buildAutoTranslateTile() {
    return SwitchListTile(
      secondary: const Icon(Icons.translate),
      title: const Text('Automatische Übersetzung'),
      subtitle: const Text(
        'Beschreibungen automatisch ins Deutsche übersetzen',
      ),
      value: _autoTranslate,
      onChanged: (value) async {
        await AppSettingsService.setAutoTranslate(value);
        setState(() {
          _autoTranslate = value;
        });
        if (mounted) {
          UIUtils.showSnackBar(
            context,
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
      title: const Text('In-App Meldungen'),
      subtitle: const Text('Alle Snackbars und Status-Meldungen (unten)'),
      value: _showRefreshMessage,
      onChanged: (value) async {
        await AppSettingsService.setShowRefreshMessage(value);
        setState(() {
          _showRefreshMessage = value;
        });
        if (mounted) {
          UIUtils.showSnackBar(
            context,
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
        content: const Text(
          'Wähle die Verzögerung bevor die Benachrichtigung erscheint:',
        ),
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
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '⏱️ Background-Test geplant für $seconds Sekunden\n✅ Funktioniert auch wenn App geschlossen ist!',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
    }
    final backgroundService = BackgroundService();
    await backgroundService.scheduleTestNotification(seconds);
  }

  Widget _buildBackgroundTaskStatusTile() {
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Background Task Status'),
      subtitle: const Text('Prüft ob Background-Scraping läuft'),
      onTap: () async {
        final backgroundService = BackgroundService();
        final isRunning = await backgroundService.isTaskRunning();
        if (mounted) {
          UIUtils.showSnackBar(
            context,
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
    final delayText =
        AppSettingsService.notificationDelays[_notificationDelaySeconds] ??
        'Sofort';
    return ListTile(
      leading: const Icon(Icons.notifications_active),
      title: const Text('🔔 Test: Favoriten-Benachrichtigungen'),
      subtitle: Text('Verzögerung: $delayText'),
      onTap: () async {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            SnackBar(
              content: Text('⏳ Benachrichtigung in $delayText...'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        try {
          final backgroundService = BackgroundService();
          await backgroundService.sendTestNotificationsForTodaysFavorites(
            delaySeconds: _notificationDelaySeconds,
          );
          if (mounted) {
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text('✓ Benachrichtigung geplant (in $delayText)'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildWorkmanagerTestTile() {
    return ListTile(
      leading: const Icon(Icons.schedule_send),
      title: const Text('🧪 Test: Workmanager (Sofort)'),
      subtitle: const Text(
        'Testet ob Workmanager im Hintergrund funktioniert (1-2 Sekunden)',
      ),
      onTap: () async {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
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
            UIUtils.showSnackBar(
              context,
              const SnackBar(
                content: Text(
                  '✅ Workmanager Test gestartet - prüfe Logs in 2-3 Sekunden',
                ),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildBackgroundScraperTestTile() {
    return ListTile(
      leading: const Icon(Icons.sync),
      title: const Text('🔄 Test: Background Scraper'),
      subtitle: const Text(
        'Testet ob der periodische Crunchyroll-Scraper funktioniert',
      ),
      onTap: () async {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
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
            UIUtils.showSnackBar(
              context,
              const SnackBar(
                content: Text(
                  '✅ Background Scraper gestartet - schließe App und prüfe Logs',
                ),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            UIUtils.showSnackBar(
              context,
              SnackBar(
                content: Text('❌ Fehler: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildNotificationDelayTile() {
    return ListTile(
      leading: const Icon(Icons.schedule),
      title: const Text('Benachrichtigungs-Verzögerung'),
      subtitle: Text(
        AppSettingsService.notificationDelays[_notificationDelaySeconds] ??
            'Sofort',
      ),
      trailing: DropdownButton<int>(
        value: _notificationDelaySeconds,
        underline: Container(),
        items: AppSettingsService.notificationDelays.entries.map((entry) {
          return DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
        onChanged: (int? newValue) async {
          if (newValue != null) {
            await AppSettingsService.setNotificationDelaySeconds(newValue);
            setState(() {
              _notificationDelaySeconds = newValue;
            });
            if (mounted) {
              UIUtils.showSnackBar(
                context,
                SnackBar(
                  content: Text(
                    '✓ Verzögerung auf ${AppSettingsService.notificationDelays[newValue]} eingestellt',
                  ),
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
      subtitle: Text('Version 0.8.9\nBilder werden von Kitsu.app geladen'),
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
          children: AppSettingsService.imageQualities.entries.map((entry) {
            return RadioListTile<String>(
              title: Text(entry.value),
              value: entry.key,
              // ignore: deprecated_member_use
              groupValue: _imageQuality,
              // ignore: deprecated_member_use
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
              // ignore: deprecated_member_use
              groupValue: _autoMinimizeScrollThreshold,
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(v);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Standard (200 px)'),
              value: 200.0,
              // ignore: deprecated_member_use
              groupValue: _autoMinimizeScrollThreshold,
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(v);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Hoch (300 px)'),
              value: 300.0,
              // ignore: deprecated_member_use
              groupValue: _autoMinimizeScrollThreshold,
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(v);
                }
              },
            ),
            RadioListTile<double>(
              title: const Text('Sehr hoch (500 px)'),
              value: 500.0,
              // ignore: deprecated_member_use
              groupValue: _autoMinimizeScrollThreshold,
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) {
                  Navigator.pop(context);
                  _saveAutoMinimizeScrollThreshold(v);
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
          children: AppSettingsService.updateIntervals.entries.map((entry) {
            return RadioListTile<int>(
              title: Text(entry.value),
              value: entry.key,
              // ignore: deprecated_member_use
              groupValue: _updateIntervalMinutes,
              // ignore: deprecated_member_use
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
          'Alle gecachten Cover-Bilder werden gelöscht und beim nächsten Laden in der aktuell eingestellten Qualität neu heruntergeladen.\n\nDies kann je nach Anzahl der Anime einige Zeit dauern.',
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
            children: AppSettingsService.accentColors.map((color) {
              final isSelected = _accentColor.toARGB32() == color.toARGB32();
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
    await AppSettingsService.setAccentColor(color);
    setState(() {
      _accentColor = color;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: const Text('Accent-Farbe geändert'),
          duration: const Duration(seconds: 1),
          backgroundColor: color,
        ),
      );
    }
  }

  Future<void> _handleExport() async {
    try {
      final jsonString = await BackupService().generateBackupJson();
      final bytes = utf8.encode(jsonString);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final suggestedFileName = 'crunchyroll_calendar_backup_$timestamp.json';

      String? chosenPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Backup speichern',
        fileName: suggestedFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (chosenPath == null) return;

      if (chosenPath.startsWith('file://')) {
        chosenPath = Uri.parse(chosenPath).toFilePath();
      }

      final file = File(chosenPath);
      await file.writeAsBytes(bytes);

      if (mounted) {
        final actualFileName = file.path
            .split(Platform.isWindows ? '\\' : '/')
            .last;

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: CircleAvatar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.1),
              child: Icon(
                Icons.check,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: const Text('Backup erfolgreich'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Deine Daten wurden erfolgreich gesichert.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dateiname:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  actualFileName,
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Schließen'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Share.shareXFiles([
                    XFile(file.path),
                  ], subject: 'Crunchyroll Kalender Backup');
                },
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Teilen'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('Export fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleImport() async {
    try {
      final backup = await BackupService().pickAndParseBackup();
      if (backup == null) return;

      if (!mounted) return;
      final selectedCategories = await showDialog<List<String>>(
        context: context,
        builder: (context) => ImportSelectionDialog(backupData: backup),
      );

      if (selectedCategories == null || selectedCategories.isEmpty) return;

      if (mounted) {
        UIUtils.showSnackBar(
          context,
          const SnackBar(content: Text('Import wird ausgeführt...')),
        );
      }

      await BackupService().importData(backup, selectedCategories);

      if (mounted) {
        UIUtils.showSnackBar(
          context,
          const SnackBar(
            content: Text('Import erfolgreich! App wird neu geladen.'),
          ),
        );
        // Reload all settings
        await _loadSettings();
        widget.onSettingsChanged?.call();
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('Import fehlgeschlagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
