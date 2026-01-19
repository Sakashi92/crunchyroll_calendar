import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service für Akku-Optimierung Einstellungen
/// Zeigt beim ersten Start einen Hinweis an und öffnet die richtigen Einstellungen
class BatteryOptimizationService {
  static const String _firstStartKey = 'battery_optimization_shown';
  static const MethodChannel _channel = MethodChannel('de.sakashi.crunchyroll_calendar/battery');
  
  /// Prüft ob der Hinweis bereits gezeigt wurde
  static Future<bool> hasShownDialog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstStartKey) ?? false;
  }
  
  /// Markiert den Hinweis als gezeigt
  static Future<void> markDialogAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstStartKey, true);
  }
  
  /// Ermittelt den Gerätehersteller
  static Future<String> getManufacturer() async {
    if (!Platform.isAndroid) return 'unknown';
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.manufacturer.toLowerCase();
    } catch (e) {
      return 'unknown';
    }
  }
  
  /// Öffnet die Akku-Einstellungen (plattformspezifisch)
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      // Versuche native Methode
      try {
        await _channel.invokeMethod('openBatteryOptimizationSettings');
      } catch (e) {
        // Fallback: Öffne allgemeine Einstellungen
        if (await canLaunchUrl(Uri.parse('app-settings:'))) {
          await launchUrl(Uri.parse('app-settings:'));
        }
      }
    } catch (e) {
      debugPrint('Error opening battery settings: $e');
    }
  }
  
  /// Gibt die herstellerspezifischen Anweisungen zurück
  static String getInstructionsForManufacturer(String manufacturer) {
    switch (manufacturer) {
      case 'samsung':
        return '''
**Samsung Geräte:**
1. Einstellungen → Apps → Crunchyroll Calendar
2. Akku → "Nicht eingeschränkt" wählen
3. Einstellungen → Akku → Grenzwerte für Hintergrundnutzung
4. "Nie in Standby versetzte Apps" → App hinzufügen

**Zusätzlich wichtig:**
• Einstellungen → Verbindungen → Datennutzung → App auswählen → "Hintergrunddaten zulassen"
''';
      
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return '''
**Xiaomi/Redmi/POCO Geräte:**
1. Einstellungen → Apps → App verwalten → Crunchyroll Calendar
2. Aktiviere "Autostart"
3. Akku-Sparmodus → Keine Einschränkungen
4. Berechtigungen → Hintergrund-Pop-ups erlauben

**MIUI-spezifisch:**
• Sicherheits-App → Berechtigungen → Autostart → App aktivieren
''';
      
      case 'huawei':
      case 'honor':
        return '''
**Huawei/Honor Geräte:**
1. Einstellungen → Apps → Crunchyroll Calendar
2. Akkuverbrauch → "App-Start manuell verwalten"
3. Aktiviere: Automatisch starten, Sekundärer Start, Im Hintergrund ausführen

**Zusätzlich:**
• Telefonmanager → App-Start → App auf "Manuell verwalten" setzen
''';
      
      case 'oppo':
      case 'realme':
      case 'oneplus':
        return '''
**OPPO/Realme/OnePlus Geräte:**
1. Einstellungen → Akku → Akkuoptimierung
2. Crunchyroll Calendar → "Nicht optimieren"
3. Einstellungen → Apps → Crunchyroll Calendar → Akkuverbrauch → Hintergrundaktivität erlauben

**ColorOS-spezifisch:**
• Telefonmanager → Energiesparen → App individuell einstellen
''';
      
      case 'vivo':
        return '''
**Vivo Geräte:**
1. Einstellungen → Akku → Hoher Hintergrund-Stromverbrauch
2. App hinzufügen
3. i Manager → App-Manager → Autostart-Manager → App aktivieren
''';
      
      case 'sony':
        return '''
**Sony Geräte:**
1. Einstellungen → Akku → Drei-Punkte-Menü → Akkuoptimierung
2. Alle Apps → Crunchyroll Calendar → "Nicht optimieren"
3. STAMINA-Modus → App als Ausnahme hinzufügen
''';
      
      case 'google':
        return '''
**Google Pixel Geräte:**
1. Einstellungen → Apps → Crunchyroll Calendar → Akku
2. Wähle "Nicht eingeschränkt"
3. Einstellungen → Akku → Akkuoptimierung → Alle Apps → App auf "Nicht optimieren"
''';
      
      default:
        return '''
**Allgemeine Android-Einstellungen:**
1. Einstellungen → Apps → Crunchyroll Calendar → Akku
2. Wähle "Nicht eingeschränkt" oder "Nicht optimieren"
3. Deaktiviere "Adaptiver Akku" für diese App
4. Erlaube "Hintergrunddatennutzung" in den Netzwerkeinstellungen

**Tipp:** Suche in deinen Einstellungen nach "Akkuoptimierung" oder "Hintergrundaktivität"
''';
    }
  }
  
  /// Zeigt den Hinweis-Dialog an
  static Future<void> showBatteryOptimizationDialog(BuildContext context) async {
    final manufacturer = await getManufacturer();
    final instructions = getInstructionsForManufacturer(manufacturer);
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final iconColor = theme.colorScheme.secondary;
        final cardBackground = isDark ? theme.colorScheme.surfaceVariant : Colors.orange.shade50;
        final cardBorder = isDark ? Colors.grey.shade700 : Colors.orange.shade200;
        final manufacturerColor = isDark ? theme.colorScheme.primary : Colors.orange.shade800;

        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.battery_alert, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Wichtig: Akku-Optimierung',
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Damit du Benachrichtigungen über neue Anime-Episoden erhältst, '
                  'musst du die Akkuoptimierung für diese App deaktivieren.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Erkanntes Gerät: ${manufacturer.toUpperCase()}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: manufacturerColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        instructions,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '⚠️ Ohne diese Einstellungen können Hintergrund-Benachrichtigungen '
                  'vom System blockiert werden.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await markDialogAsShown();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Später'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await markDialogAsShown();
                await openBatterySettings();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Einstellungen öffnen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        );
      },
    );
  }
}
