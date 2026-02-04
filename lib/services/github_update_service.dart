import 'dart:convert';
import 'dart:io';
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
        final currentVersion =
            '${packageInfo.version}+${packageInfo.buildNumber}';

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
    // Teile Version (z.B. 0.9.5) und Build (z.B. 1)
    final latestMatch = RegExp(r'^([^+]+)(?:\+(.*))?$').firstMatch(latest);
    final currentMatch = RegExp(r'^([^+]+)(?:\+(.*))?$').firstMatch(current);

    if (latestMatch == null || currentMatch == null) return false;

    final latestVersion = latestMatch.group(1)!;
    final latestBuild = latestMatch.group(2) ?? '0';
    final currentVersion = currentMatch.group(1)!;
    final currentBuild = currentMatch.group(2) ?? '0';

    // 1. Versionsvergleich (x.y.z)
    final latestParts = latestVersion
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();
    final currentParts = currentVersion
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
        .toList();

    for (var i = 0; i < latestParts.length || i < currentParts.length; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }

    // 2. Build-Vergleich (wenn Version identisch)
    final latestBuildNum =
        int.tryParse(latestBuild.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final currentBuildNum =
        int.tryParse(currentBuild.replaceAll(RegExp(r'\D'), '')) ?? 0;

    return latestBuildNum > currentBuildNum;
  }

  Stream<OtaEvent> executeUpdate(String url) {
    if (Platform.isAndroid || Platform.isIOS) {
      return OtaUpdate().execute(url, destinationFilename: 'app-release.apk');
    } else {
      // Fallback for non-mobile platforms
      return Stream.value(OtaEvent(OtaStatus.INTERNAL_ERROR, '0'));
    }
  }
}
