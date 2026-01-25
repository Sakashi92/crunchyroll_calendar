import 'package:flutter/foundation.dart';
import 'episode_provider.dart';
import 'crunchyroll_service.dart';
import 'anilist_service.dart';
import 'jikan_service.dart';
import 'app_settings_service.dart';

class EpisodeProviderFactory {
  static const String providerCrunchyroll = 'crunchyroll';
  static const String providerAnilist = 'anilist';
  static const String providerJikan = 'jikan';

  /// Returns an instance of the currently selected EpisodeProvider.
  /// By default returns `CrunchyrollService` to preserve current behavior.
  static Future<EpisodeProvider> getProvider() async {
    final name = await AppSettingsService.getEpisodeProviderName();
    if (kDebugMode) print('[EpisodeProviderFactory] selected provider: $name');
    switch (name) {
      case providerAnilist:
        return AnilistService();
      case providerJikan:
        return JikanService();
      case providerCrunchyroll:
      default:
        return CrunchyrollService();
    }
  }
}
