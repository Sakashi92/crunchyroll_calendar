import '../models/anime_release.dart';
import '../services/watchlist_service.dart';
import '../models/watchlist.dart';
import '../models/anime_metadata.dart';

/// Abstrakte Schnittstelle für Episode-/Release-Provider.
/// Implementierungen: `CrunchyrollService`, `AnilistService`, ...
abstract class EpisodeProvider {
  Future<void> loadCacheOnStartup();
  Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate);
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth});
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title);
  /// Fetch richer metadata (cover, description, total episodes, site url)
  Future<AnimeMetadata?> fetchSeriesMetadata(String? seriesUrl, String? title);
  Future<void> scheduleWatchlistEntryUpdate(WatchlistService watchlistService, WatchlistEntry entry);
  Future<void> clearImageCache();
}
