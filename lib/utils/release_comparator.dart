import '../models/anime_release.dart';
import '../models/notification_log.dart';
import 'package:flutter/foundation.dart';

/// Vergleicht neue Releases mit gecachten um Neuerungen zu identifizieren
/// Filtert nach Favoriten und vermeidet Duplikate
class ReleaseComparator {
  /// Findet neue Releases durch Vergleich mit der letzten bekannten Liste
  /// [newReleases] - neu gescrapte Releases
  /// [oldReleases] - zuvor gecachte Releases
  /// Gibt neue Releases zurück die vorher nicht in oldReleases waren
  static List<AnimeRelease> findNewReleases({
    required List<AnimeRelease> newReleases,
    required List<AnimeRelease> oldReleases,
  }) {
    if (oldReleases.isEmpty) {
      if (kDebugMode) print('📊 No old releases to compare against');
      return newReleases;
    }
    
    final oldSet = _createReleaseSet(oldReleases);
    
    final freshReleases = newReleases.where((release) {
      final key = _getReleaseKey(release);
      return !oldSet.contains(key);
    }).toList();
    
    if (kDebugMode) {
      print('📊 Found ${freshReleases.length} new releases out of ${newReleases.length} total');
    }
    
    return freshReleases;
  }
  
  /// Filtert Releases nach favorisierten Titeln
  /// [releases] - zu filternde Releases
  /// [favorites] - Liste der Favorit-Titel (Strings)
  static List<AnimeRelease> filterByFavorites({
    required List<AnimeRelease> releases,
    required List<String> favorites,
  }) {
    if (favorites.isEmpty) {
      return [];
    }
    
    final favoriteSet = favorites.map((f) => f.toLowerCase()).toSet();
    
    final filtered = releases.where((release) {
      return favoriteSet.contains(release.title.toLowerCase());
    }).toList();
    
    if (kDebugMode) {
      print('🎯 Filtered ${filtered.length} releases from ${releases.length} by favorites');
    }
    
    return filtered;
  }
  
  /// Vermeidet doppelte Benachrichtigungen durch Abgleich mit NotificationLog
  /// [releases] - zu prüfende Releases
  /// [recentNotifications] - kürzlich gesendete Benachrichtigungen
  static List<AnimeRelease> avoidDuplicates({
    required List<AnimeRelease> releases,
    required List<NotificationLog> recentNotifications,
  }) {
    if (recentNotifications.isEmpty) {
      return releases;
    }
    
    // Erstelle ein Set mit bereits benachrichtigten Release-Keys
    final notifiedSet = <String>{};
    for (final notif in recentNotifications) {
      final key = '${notif.favoriteTitle}|${notif.releaseTitle}|${notif.episodeNumber}';
      notifiedSet.add(key);
    }
    
    final unique = releases.where((release) {
      final key = '${release.title}|${release.episodeTitle}|${release.episodeNumber}';
      return !notifiedSet.contains(key);
    }).toList();
    
    if (kDebugMode) {
      print('🚫 Filtered out ${releases.length - unique.length} duplicate notifications');
    }
    
    return unique;
  }
  
  /// Sortiert Releases nach Relevanz
  /// - Premieren zuerst
  /// - Dann nach Release-Zeit (neueste zuerst)
  static List<AnimeRelease> sortByRelevance(List<AnimeRelease> releases) {
    final sorted = List<AnimeRelease>.from(releases);
    
    sorted.sort((a, b) {
      // Premieren zuerst
      if (a.isPremiere && !b.isPremiere) return -1;
      if (!a.isPremiere && b.isPremiere) return 1;
      
      // Dann nach Release-Zeit (neueste zuerst)
      return b.releaseTime.compareTo(a.releaseTime);
    });
    
    return sorted;
  }
  
  /// Erstellt einen eindeutigen Schlüssel für einen Release
  /// Wird für Deduplizierung verwendet
  static String _getReleaseKey(AnimeRelease release) {
    return '${release.title}|${release.episodeNumber}|${release.episodeTitle}';
  }
  
  /// Erstellt ein Set von Release-Keys aus einer Liste
  static Set<String> _createReleaseSet(List<AnimeRelease> releases) {
    return releases.map((r) => _getReleaseKey(r)).toSet();
  }
  
  /// Findet Releases für ein bestimmtes Favorit
  static List<AnimeRelease> filterByTitle(
    List<AnimeRelease> releases,
    String favoriteTitle,
  ) {
    return releases.where((release) {
      return release.title.toLowerCase() == favoriteTitle.toLowerCase();
    }).toList();
  }
  
  /// Prüft ob zwei Releases funktional identisch sind
  static bool areReleasesSame(AnimeRelease a, AnimeRelease b) {
    return a.title == b.title && 
           a.episodeNumber == b.episodeNumber &&
           a.releaseTime.difference(b.releaseTime).inMinutes < 1;
  }
}
