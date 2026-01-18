import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/crunchyroll_service.dart';
import 'services/background_service.dart';

/// Einstellungen für die App
class AppSettings {
  static const String _imageQualityKey = 'image_quality';
  static const String _updateIntervalKey = 'update_interval_minutes';
  static const String _autoTranslateKey = 'auto_translate';
  static const String _accentColorKey = 'accent_color';
  
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
    30: '30 Minuten',
    60: '1 Stunde',
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
    return prefs.getInt(_updateIntervalKey) ?? 5;
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
  int _updateIntervalMinutes = 5;
  bool _autoTranslate = true;
  Color _accentColor = Colors.orange;
  bool _isLoading = true;

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
    
    setState(() {
      _imageQuality = imageQuality;
      _updateIntervalMinutes = updateInterval;
      _autoTranslate = autoTranslate;
      _accentColor = accentColor;
      _isLoading = false;
    });
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
    await AppSettings.setUpdateIntervalMinutes(minutes);
    setState(() {
      _updateIntervalMinutes = minutes;
    });
    widget.onSettingsChanged?.call();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update-Intervall auf ${AppSettings.updateIntervals[minutes]} geändert.'),
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
          // Bildqualität
          _buildSectionHeader('Bildqualität'),
          _buildImageQualityTile(),
          
          const Divider(),
          
          // Update-Intervall
          _buildSectionHeader('Aktualisierung'),
          _buildUpdateIntervalTile(),
          
          const Divider(),
          
          // Übersetzung
          _buildSectionHeader('Übersetzung'),
          _buildAutoTranslateTile(),
          
          const Divider(),
          
          // Accent-Farbe
          _buildSectionHeader('Design'),
          _buildAccentColorTile(),
          
          const Divider(),
          
          // Cache-Verwaltung
          _buildSectionHeader('Cache-Verwaltung'),
          _buildClearCacheTile(),
          
          const Divider(),
          
          // Test
          _buildSectionHeader('Test'),
          _buildTestNotificationTile(),
          if (kDebugMode) _buildBackgroundTaskStatusTile(),
          
          const Divider(),
          
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

  Widget _buildInfoTile() {
    return const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Crunchyroll Kalender'),
      subtitle: Text('Version 1.0.0\nBilder werden von Kitsu.io geladen'),
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