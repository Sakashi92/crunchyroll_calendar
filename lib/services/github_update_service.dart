import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class GitHubUpdateService {
  final String owner = 'Sakashi92';
  final String repo = 'crunchyroll_calendar';

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );
      final response = await http.get(
        url,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = data['tag_name'].toString().replaceAll('v', '');

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        if (_isNewerVersion(latestVersion, currentVersion)) {
          // Suche nach dem APK-Asset
          final List assets = data['assets'];
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );

          if (apkAsset != null) {
            return {
              'version': latestVersion,
              'url': apkAsset['browser_download_url'],
              'body': data['body'],
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error checking for update: $e');
    }
    return null;
  }

  bool _isNewerVersion(String latest, String current) {
    // Einfacher Versionsvergleich (z.B. 0.8.9 vs 0.8.8)
    final latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    final currentParts = current
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();

    for (var i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return latestParts.length > currentParts.length;
  }

  Stream<OtaEvent> executeUpdate(String url) {
    return OtaUpdate().execute(url, destinationFilename: 'app-release.apk');
  }
}
