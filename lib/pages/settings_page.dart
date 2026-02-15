import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
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
import '../services/github_update_service.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pages/hidden_anime_page.dart';

/// Einstellungs-Seite
class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final CrunchyrollService? crunchyrollService;
  final String? initialUpdateUrl;

  const SettingsPage({
    super.key,
    this.onSettingsChanged,
    this.crunchyrollService,
    this.initialUpdateUrl,
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
  bool _fullDateInPill = false;
  String _appVersion = '';

  // Backup Settings
  String? _backupPath;
  int _backupFrequencyDays = 0;
  int _backupMaxCount = 5;
  bool _backupIncludeCache = false;

  bool _isLoading = true;
  Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();

    // Automatisches Update starten, wenn eine URL übergeben wurde
    if (widget.initialUpdateUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startUpdate(widget.initialUpdateUrl!);
      });
    }
  }

  Future<void> _showChangelogDialog() async {
    try {
      final changelog = await rootBundle.loadString('CHANGELOG.md');
      final versionNotes = _parseChangelog(changelog, _appVersion);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Changelog v$_appVersion'),
          content: SingleChildScrollView(
            child: Text(
              versionNotes ?? 'Keine Einträge für diese Version gefunden.',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final url = Uri.parse(
                  'https://github.com/Sakashi92/crunchyroll_calendar',
                );
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('GitHub (Sakashi92)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (kDebugMode) print('Error loading changelog: $e');
    }
  }

  String? _parseChangelog(String content, String targetVersion) {
    // Normalisiere Version für Suche (0.9.9+1 -> 0.9.9)
    final baseVersion = targetVersion.split('+')[0];
    final lines = content.split('\n');
    bool inVersion = false;
    final List<String> notes = [];

    for (var line in lines) {
      // Suche nach Header-Zeilen wie "## [0.9.9]"
      if (line.startsWith('## ')) {
        if (inVersion) break; // Nächste Version erreicht

        if (line.contains('[$baseVersion]') ||
            line.contains('[$targetVersion]')) {
          inVersion = true;
          continue;
        }
      }

      if (inVersion) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          notes.add(line);
        }
      }
    }

    return notes.isEmpty ? null : notes.join('\n');
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
    final fullDateInPill = await AppSettingsService.getFullDateInPill();

    final backupPath = await AppSettingsService.getBackupPath();
    final backupFrequency = await AppSettingsService.getBackupFrequencyDays();
    final backupMaxCount = await AppSettingsService.getBackupMaxCount();
    final backupIncludeCache = await AppSettingsService.getBackupIncludeCache();

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
      _fullDateInPill = fullDateInPill;

      _backupPath = backupPath;
      _backupFrequencyDays = backupFrequency;
      _backupMaxCount = backupMaxCount;
      _backupIncludeCache = backupIncludeCache;

      _permissions = permissions;
      _isLoading = false;
    });

    // Version separat laden, falls es etwas länger dauert
    _loadAppVersion();

    // Migriere alte Backups falls möglich (asynchron)
    if (permissions['Speicherzugriff'] == PermissionStatus.granted) {
      BackupService().migrateOldBackups();
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      });
    }
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

  Future<void> _saveFullDateInPill(bool enabled) async {
    await AppSettingsService.setFullDateInPill(enabled);
    setState(() {
      _fullDateInPill = enabled;
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

  Future<void> _pickBackupPath() async {
    // Request storage permission first
    final hasPermission = await PermissionService().requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          const SnackBar(
            content: Text('Speicherzugriff erforderlich für Backups.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await AppSettingsService.setBackupPath(selectedDirectory);
      setState(() {
        _backupPath = selectedDirectory;
      });
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(content: Text('Backup-Pfad gesetzt: $selectedDirectory')),
        );
      }
      widget.onSettingsChanged?.call();
    }
  }

  Future<void> _saveBackupFrequency(int days) async {
    // Berechtigung anfragen wenn Auto-Backup aktiviert wird
    if (days > 0 && Platform.isAndroid) {
      final hasPermission = await PermissionService()
          .requestStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(
              content: Text(
                'Berechtigung abgelehnt. Automatische Backups deaktiviert.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        // Fallback auf 0 (deaktiviert)
        days = 0;
      }
    }

    await AppSettingsService.setBackupFrequencyDays(days);
    setState(() {
      _backupFrequencyDays = days;
    });

    // If we enable logic to reschedule background tasks specifically for backups, do it here.
    // For now, the existing background service picks up the frequency check logic internally.
    if ((Platform.isAndroid || Platform.isIOS) && days > 0) {
      // Periodic scraper task handles backup checks
    }

    widget.onSettingsChanged?.call();
  }

  Future<void> _saveBackupMaxCount(int count) async {
    await AppSettingsService.setBackupMaxCount(count);
    setState(() {
      _backupMaxCount = count;
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _saveBackupIncludeCache(bool include) async {
    await AppSettingsService.setBackupIncludeCache(include);
    setState(() {
      _backupIncludeCache = include;
    });
    widget.onSettingsChanged?.call();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text(
            include
                ? 'Automatische Backups: Vollständig (mit Cache)'
                : 'Automatische Backups: Standard (ohne Cache)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _triggerManualBackup() async {
    // Permission check for Android
    if (Platform.isAndroid) {
      final hasPermission = await PermissionService()
          .requestStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(content: Text('Keine Speicherberechtigung.')),
          );
        }
        return;
      }
    }

    // Ask for backup type
    final bool? includeCache = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup erstellen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Standard Backup'),
              subtitle: const Text('Einstellungen, Watchlist, Verlauf, Titel'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Vollständiges Backup'),
              subtitle: const Text('Zusätzlich: Offline-Cache (Bilder)'),
              onTap: () => Navigator.pop(context, true),
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

    if (includeCache == null) return;

    setState(() => _isLoading = true);
    try {
      // Force a "auto" backup manually but using the auto logic (or manual logic?)
      // Use performAutoBackup but bypass time check? No, performAutoBackup checks time.
      // Let's call BackupService().performAutoBackup() but we might want to force it.
      // Or just valid manual export to that folder.
      // Let's make a manual trigger that respects the path.

      final service = BackupService();

      // Request permission again just in case
      if (Platform.isAndroid) {
        final hasPermission = await PermissionService()
            .requestStoragePermission();
        if (!hasPermission) {
          throw Exception(
            'Keine Speicherberechtigung (Manage External Storage erforderlich für Android 11+)',
          );
        }
      }

      // We want to save to the configured path, similar to auto backup but forced.
      final jsonString = await service.generateBackupJson(
        includeCache: includeCache,
      );
      final path = await AppSettingsService.getEffectiveBackupPath();
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];

      final typeSuffix = includeCache ? '_full' : '';
      final filename = 'backup_manual$typeSuffix\_$timestamp.json';

      // Sanitized path handling
      String fullPath = directory.path;
      if (!fullPath.endsWith(Platform.pathSeparator)) {
        fullPath += Platform.pathSeparator;
      }
      fullPath += filename;

      final file = File(fullPath);

      if (kDebugMode) {
        print('📂 Manual Backup: Writing to $fullPath');
      }

      await file.writeAsString(jsonString);

      // Enforce retention limit
      await service.cleanupOldBackups(directory);

      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(content: Text('Backup erstellt: $filename\n$fullPath')),
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ Manual Backup Error: $e');
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showRestoreInternalDialog() async {
    // Check permission
    if (Platform.isAndroid) {
      final hasPermission = await PermissionService()
          .requestStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          UIUtils.showSnackBar(
            context,
            const SnackBar(content: Text('Keine Speicherberechtigung.')),
          );
        }
        return;
      }
    }

    // Zeige Lade-Indikator oder warte kurz
    final files = await BackupService().getAvailableBackups();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Backup wiederherstellen'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Datei auswählen...'),
                  subtitle: const Text('Backup von anderem Ort laden'),
                  onTap: () async {
                    // File picking logic
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null && result.files.single.path != null) {
                        Navigator.pop(context);
                        _restoreFromFile(File(result.files.single.path!));
                      }
                    } catch (e) {
                      print('Error picking file: $e');
                    }
                  },
                ),
                const Divider(),
                Flexible(
                  child: files.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Keine Backups im Standard-Ordner gefunden.',
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: files.length,
                          itemBuilder: (context, index) {
                            final file = files[index];
                            final name = file.path
                                .split(Platform.pathSeparator)
                                .last;
                            final stat = file.statSync();
                            final size =
                                (stat.size / 1024).toStringAsFixed(1) + ' KB';
                            final date = stat.modified.toString().split('.')[0];

                            return ListTile(
                              leading: const Icon(Icons.restore),
                              title: Text(
                                name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                '$date • $size',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _restoreFromFile(file);
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.share),
                                onPressed: () => _shareFile(file),
                                tooltip: 'Exportieren / Teilen',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _restoreFromFile(File file) async {
    try {
      final backupData = await BackupService().parseBackupFromFile(file);

      if (!mounted) return;

      // Use existing import selection dialog
      // Note: ImportSelectionDialog returns List<String>? when popped with selection
      final List<dynamic>? result = await showDialog(
        context: context,
        builder: (context) => ImportSelectionDialog(backupData: backupData),
      );

      if (result != null && result.isNotEmpty) {
        final categories = result.cast<String>();
        await BackupService().importData(backupData, categories);

        if (categories.contains(BackupService.catSettings)) {
          await _loadSettings();
          widget.onSettingsChanged?.call();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup erfolgreich wiederhergestellt!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('Fehler beim Laden des Backups: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareFile(File file) async {
    try {
      final xFile = XFile(file.path);
      await Share.shareXFiles([xFile], text: 'Backup exportieren');
    } catch (e) {
      if (mounted) {
        UIUtils.showSnackBar(
          context,
          SnackBar(
            content: Text('Fehler beim Teilen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              title: const Text('Vollständiges Datum in Pillenform'),
              subtitle: const Text(
                'Zeigt das vollständige Datum (z.B. "Mittwoch, 5. Februar") statt der Kurzform (z.B. "Mi, 5. Feb") in der minimierten Kalenderansicht an',
              ),
              value: _fullDateInPill,
              onChanged: (v) => _saveFullDateInPill(v),
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
            child: ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Versteckte Anime verwalten'),
              subtitle: const Text(
                'Liste aller ausgeblendeten Anime anzeigen und bearbeiten',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HiddenAnimePage(),
                  ),
                ).then((_) => widget.onSettingsChanged?.call());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SwitchListTile(
              title: const Text('Aktuelle Episodenanzahl bevorzugen'),
              subtitle: const Text(
                'Bevorzugt den Crunchyroll-Kalender (für Simulcasts). Bei beendeten Serien oder Ausnahmen wird die Metadaten-Datenbank (AniList/Kitsu) verwendet.',
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
              leading: const Icon(Icons.folder),
              title: const Text('Backup-Pfad wählen'),
              subtitle: Text(
                _backupPath ??
                    (Platform.isAndroid
                        ? 'Standard (Download/CrunchyrollBackup)'
                        : 'Standard (App-Daten)'),
                style: TextStyle(
                  fontStyle: _backupPath == null ? FontStyle.italic : null,
                ),
              ),
              trailing: const Icon(Icons.edit),
              onTap: _pickBackupPath,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Automatische Backups'),
              subtitle: Text(
                _backupFrequencyDays == 0
                    ? 'Deaktiviert'
                    : _backupFrequencyDays == 1
                    ? 'Täglich'
                    : 'Alle $_backupFrequencyDays Tage',
              ),
              trailing: DropdownButton<int>(
                value: _backupFrequencyDays,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Nie')),
                  DropdownMenuItem(value: 1, child: Text('Täglich')),
                  DropdownMenuItem(value: 3, child: Text('Alle 3 Tage')),
                  DropdownMenuItem(value: 7, child: Text('Wöchentlich')),
                  DropdownMenuItem(value: 30, child: Text('Monatlich')),
                ],
                onChanged: (v) {
                  if (v != null) _saveBackupFrequency(v);
                },
              ),
            ),
          ),
          if (_backupFrequencyDays > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Anzahl zu behaltender Backups'),
                subtitle: Text('$_backupMaxCount Backups'),
                trailing: DropdownButton<int>(
                  value: _backupMaxCount,
                  underline: const SizedBox(),
                  items: [3, 5, 10, 20, 50]
                      .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _saveBackupMaxCount(v);
                  },
                ),
              ),
            ),
          if (_backupFrequencyDays > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SwitchListTile(
                secondary: const Icon(Icons.save_as),
                title: const Text('Backup-Typ: Vollständig'),
                subtitle: const Text(
                  'Sichert auch Bilder-Cache (größere Datei)',
                ),
                value: _backupIncludeCache,
                onChanged: (v) => _saveBackupIncludeCache(v),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Backup jetzt erstellen'),
              subtitle: const Text(
                'Erstellt sofort ein Backup im gewählten Ordner',
              ),
              onTap: _triggerManualBackup,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              leading: const Icon(Icons.restore_page),
              title: const Text('Backup wiederherstellen'),
              subtitle: const Text(
                'Wähle ein Backup aus dem Ordner zur Wiederherstellung',
              ),
              onTap: _showRestoreInternalDialog,
            ),
          ),

          const Divider(),
          _buildSectionHeader('Info'),
          _buildUpdateCheckTile(),
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

  Widget _buildUpdateCheckTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        leading: const Icon(Icons.system_update),
        title: const Text('Auf Updates prüfen'),
        subtitle: const Text('Prüft GitHub auf eine neuere Version der App'),
        onTap: () => _checkForUpdates(manual: true),
      ),
    );
  }

  Future<void> _checkForUpdates({bool manual = false}) async {
    final updateService = GitHubUpdateService();

    if (manual) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    final updateInfo = await updateService.checkForUpdate();

    if (manual && mounted) {
      Navigator.pop(context); // Lade-Dialog schließen
    }

    if (updateInfo != null) {
      if (mounted) {
        _showUpdateDialog(updateInfo);
      }
    } else if (manual && mounted) {
      UIUtils.showSnackBar(
        context,
        const SnackBar(
          content: Text('App ist bereits auf dem neuesten Stand.'),
        ),
      );
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update verfügbar: v${updateInfo['version']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Eine neue Version der App wurde auf GitHub gefunden.',
              ),
              if (updateInfo['body'] != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Änderungen:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(updateInfo['body']),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startUpdate(updateInfo['url']);
            },
            child: const Text('Jetzt aktualisieren'),
          ),
        ],
      ),
    );
  }

  void _startUpdate(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return StreamBuilder<OtaEvent>(
              stream: GitHubUpdateService().executeUpdate(url),
              builder: (context, snapshot) {
                String message = 'Update wird vorbereitet...';
                double? progress;

                if (snapshot.hasData) {
                  switch (snapshot.data!.status) {
                    case OtaStatus.DOWNLOADING:
                      message = 'Downloade Update...';
                      progress =
                          double.tryParse(snapshot.data!.value ?? '0') ?? 0;
                      progress = progress / 100;
                      break;
                    case OtaStatus.INSTALLING:
                      message = 'Starte Installation...';
                      break;
                    case OtaStatus.ALREADY_RUNNING_ERROR:
                      message = 'Update läuft bereits.';
                      break;
                    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                      message = 'Keine Berechtigung zur Installation.';
                      break;
                    case OtaStatus.INTERNAL_ERROR:
                      message = 'Interner Fehler beim Update.';
                      break;
                    case OtaStatus.DOWNLOAD_ERROR:
                      message = 'Fehler beim Herunterladen.';
                      break;
                    case OtaStatus.CHECKSUM_ERROR:
                      message = 'Prüfsummenfehler.';
                      break;
                    default:
                      message = 'Status: ${snapshot.data!.status}';
                      break;
                  }
                } else if (snapshot.hasError) {
                  message = 'Fehler: ${snapshot.error}';
                }

                return AlertDialog(
                  title: const Text('Update wird installiert'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progress),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        Text('${(progress * 100).toStringAsFixed(0)}%'),
                      ],
                    ],
                  ),
                  actions: [
                    if (snapshot.hasError ||
                        (snapshot.hasData &&
                            (snapshot.data!.status ==
                                    OtaStatus.INTERNAL_ERROR ||
                                snapshot.data!.status ==
                                    OtaStatus.DOWNLOAD_ERROR ||
                                snapshot.data!.status ==
                                    OtaStatus.PERMISSION_NOT_GRANTED_ERROR ||
                                snapshot.data!.status ==
                                    OtaStatus.ALREADY_RUNNING_ERROR ||
                                snapshot.data!.status ==
                                    OtaStatus.CHECKSUM_ERROR)))
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Schließen'),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInfoTile() {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Crunchyroll Kalender'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version $_appVersion'),
          const Text(
            'Made by Sakashi92',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          Text(
            'Bilder werden von Kitsu.app geladen',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tippen für Changelog',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.blue,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: _showChangelogDialog,
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
}
