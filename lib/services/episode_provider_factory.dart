import 'package:flutter/foundation.dart';
import 'episode_provider.dart';
import 'crunchyroll_service.dart';
import 'anilist_service.dart';
import 'app_settings_service.dart';

class EpisodeProviderFactory {
  static const String PROVIDER_CRUNCHYROLL = 'crunchyroll';
  static const String PROVIDER_ANILIST = 'anilist';

  /// Returns an instance of the currently selected EpisodeProvider.
  /// By default returns `CrunchyrollService` to preserve current behavior.
  static Future<EpisodeProvider> getProvider() async {
    final name = await AppSettingsService.getEpisodeProviderName();
    if (kDebugMode) print('[EpisodeProviderFactory] selected provider: $name');
    switch (name) {
      case PROVIDER_ANILIST:
        return AnilistService();
      case PROVIDER_CRUNCHYROLL:
      default:
        return CrunchyrollService();
    }
  }
}
