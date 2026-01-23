import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
//import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import '../models/anime_release.dart';
import '../settings.dart';
import '../services/watchlist_service.dart';
import '../repositories/notification_repository.dart';
import '../models/notification_log.dart';
import '../utils/episode_parser.dart';
import '../models/watchlist.dart';

class CrunchyrollService {
  static const String calendarUrl = 'https://www.crunchyroll.com/de/simulcastcalendar?filter=premium';
  static const String _cacheKey = 'cached_anime_releases_v4'; // Kitsu images
  static const String _lastUpdateKey = 'last_update_time_v4';
  static const String _imageCacheKey = 'cached_anime_images'; // Bild-URL Cache
  static const String _releasesHashKey = 'releases_hash_v4'; // Hash für Änderungserkennung
  static const String _processedAnimeTitlesKey = 'processed_anime_titles_v4'; // Verarbeitete Anime-Titel
  Duration _updateInterval = const Duration(minutes: 5);
  
  Timer? _updateTimer;
  List<AnimeRelease> _cachedReleases = [];
  Map<String, String> _imageCache = {}; // Anime-Name -> Bild-URL
  String? _currentReleasesHash; // Hash der aktuellen Releases
  Set<String> _processedAnimeTitles = {}; // Anime-Titel die bereits verarbeitet wurden
  
  // Warteschlange für sequenzielle Bildladung
  bool _isLoadingImages = false;
  List<(List<AnimeRelease>, DateTime)> _imageLoadingQueue = [];
  
  // Callback für Bilder-Ladestatus
  Function(bool isLoading, int loaded, int total)? onImageLoadingChanged;
  
  // Callback wenn ein Bild geladen wurde - UI sollte sich aktualisieren
  Function()? onImageLoaded;
  
  /// Löscht den Bild-Cache (Memory und SharedPreferences)
  /// Damit Bilder in neuer Qualität neu geladen werden können
  Future<void> clearImageCache() async {
      if (kDebugMode) print('🗑️ Clearing image cache...');
    
    // Lösche In-Memory Cache
    _imageCache.clear();
    _processedAnimeTitles.clear();
    
    // Lösche auch imageUrl von allen gecachten Releases
    for (var release in _cachedReleases) {
      release.imageUrl = null;
    }
    
    // Lösche aus SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_anime_images');
    await prefs.remove('processed_anime_titles_v4');
    
    // Lösche auch alle Monats-Caches um imageUrls zu entfernen
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('cached_anime_releases_month_')) {
        await prefs.remove(key);
      }
    }
    
    if (kDebugMode) print('✓ Image cache cleared - ${_imageCache.length} images, ${_processedAnimeTitles.length} processed titles');
  }
  
  /// Berechnet ein Datum X Monate zurück (mit Jahr-Überlauf)
  /// Mit day=2 damit auch der exakte Monat-Grenzfall blockiert wird
  DateTime _getMonthsAgo(int months) {
    int year = DateTime.now().year;
    int month = DateTime.now().month - months;
    while (month <= 0) {
      year--;
      month += 12;
    }
    return DateTime(year, month, 2); // Tag 2 statt 1 für Grenzfall-Handling
  }
    Future<List<AnimeRelease>> getReleasesForWeek(DateTime startDate) async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final twoMonthsAgo = _getMonthsAgo(2);
      
      // Prüfe ZUERST ob der Monat älter als 2 Monate ist - dann ist er "eingefroren"
      final monthStart = DateTime(startDate.year, startDate.month, 1);
      if (monthStart.isBefore(twoMonthsAgo)) {
        if (kDebugMode) print('⛔ Month ${monthStart.month}/${monthStart.year} is frozen (older than 2 months) - loading only from cache');
        // Gebe Daten nur aus Cache zurück, scrapt nicht neu
        final cachedMonthData = await _loadMonthFromCache(startDate);
        if (cachedMonthData.isNotEmpty) {
          if (kDebugMode) print('✓ Loaded ${cachedMonthData.length} releases from frozen month cache');
          // Lade auch fehlende Bilder nach (aber nicht warten)
          _queueImageLoading(cachedMonthData, DateTime.now());
        } else {
          if (kDebugMode) print('⚠ No cached data available for frozen month');
        }
        return cachedMonthData;
      }
      
      // Wenn der angeforderte Monat älter als 30 Tage ist, lade ihn aus Cache oder nachträglich
      if (monthStart.isBefore(thirtyDaysAgo)) {
        if (kDebugMode) print('ℹ Month is older than 30 days - loading from cache or on-demand: ${monthStart.month}/${monthStart.year}');
        
        // Versuche zuerst aus Cache zu laden
        final cachedMonthData = await _loadMonthFromCache(startDate);
        if (cachedMonthData.isNotEmpty) {
          if (kDebugMode) print('✓ Loaded ${cachedMonthData.length} releases from cache for ${monthStart.month}/${monthStart.year}');
          // Lade auch fehlende Bilder nach (aber nicht warten)
          _queueImageLoading(cachedMonthData, DateTime.now());
          return cachedMonthData;
        }
        // Ansonsten scrapen
        if (kDebugMode) print('⏳ Scraping specific month: ${monthStart.month}/${monthStart.year}');
        final scrapedData = await _scrapeSpecificMonth(startDate);
        
        if (scrapedData.isEmpty) {
          if (kDebugMode) print('⚠ No anime found for ${monthStart.month}/${monthStart.year}');
        } else {
          if (kDebugMode) print('✓ Scraped ${scrapedData.length} releases for ${monthStart.month}/${monthStart.year}');
        }
        
        // In Cache speichern für zukünftige Abrufe (auch wenn leer)
        await _saveMonthToCache(startDate, scrapedData);
        return scrapedData;
      }
      
      // Für aktuelle Monatsdaten: Cache mit Änderungserkennung
      if (kDebugMode) print('Loading current month data');
      
      final today = DateTime(now.year, now.month, now.day);
      final isPastMonth = startDate.isBefore(today);
      
      // Wenn es vergangene Tage im aktuellen Monat sind: Cache-first
      if (isPastMonth && startDate.month == now.month && startDate.year == now.year) {
        if (kDebugMode) print('ℹ Loading past days in current month - cache-first approach');
        
        // Versuche zuerst aus Cache zu laden
        final cachedMonthData = await _loadMonthFromCache(startDate);
        if (cachedMonthData.isNotEmpty) {
          if (kDebugMode) print('✓ Using cached data for past days in current month (${cachedMonthData.length} releases)');
          // Lade auch fehlende Bilder nach (aber nicht warten)
          _queueImageLoading(cachedMonthData, DateTime.now());
          return cachedMonthData;
        }
        
        // Kein Cache vorhanden - scrapen
        if (kDebugMode) print('⏳ No cache for past days - scraping current month');
        final newReleases = await _scrapeCalendarCurrentMonth();
        await _saveMonthToCache(startDate, newReleases);
        _applyCachedImagesToReleases(newReleases);
        return newReleases;
      }
      
      // Für zukünftige Tage im aktuellen Monat: Normale Update-Logik
      // Versuche zuerst aus Cache zu laden
      if (await _isMonthCacheValid(startDate)) {
        final cachedMonthData = await _loadMonthFromCache(startDate);
        if (kDebugMode) print('✓ Using cached data for current month');
        // Lade auch fehlende Bilder nach (aber nicht warten)
        _queueImageLoading(cachedMonthData, DateTime.now());
        return cachedMonthData;
      }
      
      // Cache abgelaufen oder leer - neu scrapen
      if (kDebugMode) print('Cache expired or empty, loading fresh data');
      final newReleases = await _scrapeCalendarCurrentMonth();
      
      // Prüfe ob sich zukünftige Daten geändert haben
      if (await _hasChanges(newReleases)) {
        if (kDebugMode) print('✓ Changes detected in future releases - updating cache');
      } else {
        if (kDebugMode) print('ℹ No changes in future releases - but saving all month data to cache');
      }
      
      // Speichere monatsspezifisch
      await _saveMonthToCache(startDate, newReleases);
      
      // Wende gecachte Bilder an
      _applyCachedImagesToReleases(newReleases);
      
      // Lade fehlende Bilder nach (aber nicht warten - Queue übernimmt das)
      _queueImageLoading(newReleases, DateTime.now());
      
      return newReleases;
    } catch (e) {
      if (kDebugMode) print('Error loading releases: $e');
      // Fallback zu Cache
      final cachedMonthData = await _loadMonthFromCache(startDate);
      if (cachedMonthData.isNotEmpty) {
        if (kDebugMode) print('Returning cached data as fallback');
        // Lade auch fehlende Bilder für Cache-Fallback (aber nicht warten)
        _queueImageLoading(cachedMonthData, DateTime.now());
        return cachedMonthData;
      }
      return [];
    }
  }
  
  Future<List<AnimeRelease>> forceRefresh({DateTime? forMonth}) async {
    if (kDebugMode) print('Force refresh: Ignoring cache, loading fresh data');
    try {
      // Lade zuerst Bild-Cache falls nicht im Speicher
      if (_imageCache.isEmpty) {
        await _loadFromCache();
      }
      
      final now = DateTime.now();
      final thirtyDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final twoMonthsAgo = _getMonthsAgo(2);
      final monthToRefresh = forMonth ?? now;
      final monthStart = DateTime(monthToRefresh.year, monthToRefresh.month, 1);
      
      // Prüfe ob der Monat älter als 2 Monate ist - dann ist er "eingefroren"
      if (monthStart.isBefore(twoMonthsAgo)) {
        if (kDebugMode) print('⛔ Refresh blocked: Month ${monthStart.month}/${monthStart.year} is older than 2 months (frozen)');
        // Gebe Daten nur aus Cache zurück, scrapt nicht neu
        final cachedData = await _loadMonthFromCache(monthToRefresh);
        if (cachedData.isNotEmpty) {
          if (kDebugMode) print('✓ Returning cached data for frozen month (${cachedData.length} releases)');
          return cachedData;
        }
        if (kDebugMode) print('⚠ No cached data available for frozen month');
        return [];
      }
      
      // Bestimme ob es ein alter oder aktueller Monat ist
      List<AnimeRelease> newReleases;
      if (monthStart.isBefore(thirtyDaysAgo)) {
        // Alter Monat (aber nicht älter als 2 Monate): Scrape spezifischen Monat
        if (kDebugMode) print('Force refresh for old month: ${monthStart.month}/${monthStart.year}');
        newReleases = await _scrapeSpecificMonth(monthToRefresh);
        // Speichere in monatsspezifischen Cache
        await _saveMonthToCache(monthToRefresh, newReleases);
      } else {
        // Aktueller Monat: Scrape aktuellen Monat
        if (kDebugMode) print('Force refresh for current month');
        newReleases = await _scrapeCalendarCurrentMonth();
        // Speichere in globalem Cache
        await _saveToCache(newReleases);
      }
      
      // Wende gecachte Bilder auf neu gescrapte Releases an
      _applyCachedImagesToReleases(newReleases);
      
      // Lade fehlende Bilder nach (in der Queue)
      _queueImageLoading(newReleases, DateTime.now());
      
      return newReleases;
    } catch (e) {
      if (kDebugMode) print('Error during force refresh: $e');
      // Fallback zu gecachten Daten wenn vorhanden
      if (_cachedReleases.isNotEmpty) {
        if (kDebugMode) print('Returning cached data as fallback');
        return _cachedReleases;
      }
      return [];
    }
  }
  
  /// Lädt die Einstellungen und aktualisiert interne Variablen
  Future<void> loadSettings() async {
    _updateInterval = await AppSettings.getUpdateInterval();
    if (kDebugMode) print('⚙️ Settings loaded: Update interval = ${_updateInterval.inMinutes} minutes');
  }
  
  void startAutoUpdate(Function() onUpdate) async {
    _updateTimer?.cancel();
    
    // Lade aktuelle Einstellungen
    await loadSettings();
    
    _updateTimer = Timer.periodic(_updateInterval, (timer) async {
      if (kDebugMode) print('Auto-update triggered');
      try {
        final releases = await _scrapeCalendar();
        await _saveToCache(releases);
        onUpdate();
      } catch (e) {
        if (kDebugMode) print('Auto-update failed: $e');
      }
    });
  }
  
  /// Startet den Auto-Update Timer mit den aktuellen Einstellungen neu
  void restartAutoUpdate(Function() onUpdate) {
    startAutoUpdate(onUpdate);
  }
  
  void stopAutoUpdate() {
    _updateTimer?.cancel();
  }
  
  /// Adds image loading task to queue for sequential processing
  void _queueImageLoading(List<AnimeRelease> releases, DateTime today) {
    _imageLoadingQueue.add((releases, today));
    _processImageLoadingQueue();
  }

  /// Processes image loading queue sequentially
  Future<void> _processImageLoadingQueue() async {
    if (_isLoadingImages || _imageLoadingQueue.isEmpty) {
      return;
    }

    _isLoadingImages = true;

    while (_imageLoadingQueue.isNotEmpty) {
      final (releases, today) = _imageLoadingQueue.removeAt(0);
      await _loadMissingImagesFromAniList(releases, today);
    }

    _isLoadingImages = false;
  }

  /// Lädt alle gecachten Daten beim Start
  /// Einschließlich Bild-Cache und verarbeitete Anime-Titel
  /// Dies sollte BEVOR getReleasesForWeek aufgerufen wird geschehen
  Future<void> loadCacheOnStartup() async {
    if (kDebugMode) print('🚀 Loading cache on startup...');
    await _loadFromCache();
    if (kDebugMode) print('✓ Cache loaded - processed titles: ${_processedAnimeTitles.length}, image URLs: ${_imageCache.length}');
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      final imageCacheJson = prefs.getString(_imageCacheKey);
      final releasesHash = prefs.getString(_releasesHashKey);
      final processedTitlesJson = prefs.getString(_processedAnimeTitlesKey);
      
      // Lade Bild-Cache zuerst
      if (imageCacheJson != null) {
        final Map<String, dynamic> imageMap = json.decode(imageCacheJson);
        _imageCache = imageMap.map((key, value) => MapEntry(key, value.toString()));
        if (kDebugMode) print('Loaded ${_imageCache.length} cached image URLs');
        // Debug: Zeige erste 5 Keys
        if (_imageCache.isNotEmpty) {
          final sampleKeys = _imageCache.keys.take(5).toList();
          if (kDebugMode) print('  Sample image cache keys: $sampleKeys');
        }
      } else {
        if (kDebugMode) print('⚠ No image cache found in SharedPreferences');
      }
      
      // Lade verarbeitete Anime-Titel
      if (processedTitlesJson != null) {
        try {
          final List<dynamic> titlesList = json.decode(processedTitlesJson);
          _processedAnimeTitles = titlesList.cast<String>().toSet();
          if (kDebugMode) print('Loaded ${_processedAnimeTitles.length} processed anime titles');
        } catch (e) {
          if (kDebugMode) print('Error loading processed titles: $e');
          _processedAnimeTitles = {};
        }
      }
      
      if (cachedJson != null) {
        final List<dynamic> jsonList = json.decode(cachedJson);
        _cachedReleases = jsonList.map((item) => AnimeRelease.fromJson(item)).toList();
        if (kDebugMode) print('Loaded ${_cachedReleases.length} releases from cache');
        
        // Wende gecachte Bild-URLs auf die Releases an
        _applyCachedImagesToReleases(_cachedReleases);
      }
      
      // Lade den Hash der Releases
      if (releasesHash != null) {
        _currentReleasesHash = releasesHash;
      }
    } catch (e) {
      if (kDebugMode) print('Error loading from cache: $e');
      _cachedReleases = [];
    }
  }
  
  /// Generiert einen Hash der Releases für Änderungserkennung
  /// Berücksichtigt nur zukünftige Releases (ab morgen)
  String _generateReleasesHash(List<AnimeRelease> releases) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    
    // Filtere nur zukünftige Releases (ab morgen)
    final futureReleases = releases.where((r) {
      return r.releaseTime.isAfter(tomorrow);
    }).toList();
    
    // Sortiere für konsistente Hash-Generierung
    futureReleases.sort((a, b) => a.releaseTime.compareTo(b.releaseTime));
    
    // Erstelle Hash aus den wichtigen Feldern
    final buffer = StringBuffer();
    for (var release in futureReleases) {
      buffer.write('${release.title}|${release.episodeNumber}|${release.releaseTime}|');
    }
    
    // Einfacher Hash: Länge + erstes und letztes zeichen
    final str = buffer.toString();
    return '${str.length}_${str.hashCode}';
  }
  
  /// Prüft ob sich die Releases geändert haben
  /// Vergleicht Hashes und ignoriert vergangene Releases
  Future<bool> _hasChanges(List<AnimeRelease> newReleases) async {
    // Lade alte Hash falls noch nicht im Speicher
    if (_currentReleasesHash == null) {
      final prefs = await SharedPreferences.getInstance();
      _currentReleasesHash = prefs.getString(_releasesHashKey);
    }
    
    // Wenn kein Cache Hash existiert, ist das eine Änderung
    if (_currentReleasesHash == null) {
      if (kDebugMode) print('ℹ No previous hash found - treating as new data');
      return true;
    }
    
    // Generiere Hash der neuen Releases
    final newHash = _generateReleasesHash(newReleases);
    
    // Vergleiche mit altem Hash
    final hasChanged = newHash != _currentReleasesHash;
    
    if (hasChanged) {
      if (kDebugMode) print('✓ Hash changed: "$_currentReleasesHash" -> "$newHash"');
    } else {
      if (kDebugMode) print('✓ Hash unchanged: "$newHash"');
    }
    
    return hasChanged;
  }
  
  /// Wendet gecachte Bild-URLs auf die Releases an
  void _applyCachedImagesToReleases(List<AnimeRelease> releases, {bool notifyUI = false}) {
    if (kDebugMode) print('🔍 Applying cached images to ${releases.length} releases (imageCache has ${_imageCache.length} entries)');
    
    var appliedCount = 0;
    var notFoundCount = 0;
    var alreadyHaveCount = 0;
    
    for (var release in releases) {
      if ((release.imageUrl == null || release.imageUrl!.isEmpty)) {
        // Suche im Image-Cache nach einer passenden URL
        final cachedUrl = _findCachedImageUrl(release.title);
        if (cachedUrl != null && cachedUrl.isNotEmpty) {
          release.imageUrl = cachedUrl;
          appliedCount++;
        } else {
          notFoundCount++;
        }
      } else {
        alreadyHaveCount++;
      }
    }
    
    if (kDebugMode) print('📊 Results: $appliedCount applied, $alreadyHaveCount already had, $notFoundCount not found');
    
    if (appliedCount > 0) {
      if (kDebugMode) print('✓ Applied $appliedCount cached image URLs to releases');
      // Benachrichtige UI dass Bilder aus Cache angewendet wurden
      if (notifyUI) {
        onImageLoaded?.call();
      }
    }
    if (notFoundCount > 0) {
      if (kDebugMode) print('⚠ $notFoundCount releases still need image URLs');
    }
  }
  
  /// Findet eine gecachte Bild-URL für einen Anime-Titel
  String? _findCachedImageUrl(String title) {
    // Versuche exakten Match (nur wenn nicht leer)
    if (_imageCache.containsKey(title) && _imageCache[title]!.isNotEmpty) {
      if (kDebugMode) print('  📦 Cache exact match: $title');
      return _imageCache[title];
    }
    
    // Bereinige den Namen auf DIE GLEICHE WEISE wie in _fetchImageFromKitsu()
    var cleanedName = _cleanAnimeName(title);
    cleanedName = cleanedName.replaceAll(RegExp(r'[^\w\s\-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (_imageCache.containsKey(cleanedName) && _imageCache[cleanedName]!.isNotEmpty) {
      if (kDebugMode) print('  📦 Cache cleaned match: $title -> $cleanedName');
      return _imageCache[cleanedName];
    }
    
    // Versuche Case-Insensitive Match
    final cleanedLower = cleanedName.toLowerCase();
    for (final entry in _imageCache.entries) {
      if (entry.key.toLowerCase() == cleanedLower && entry.value.isNotEmpty) {
        if (kDebugMode) print('  📦 Cache case-insensitive match: $title -> ${entry.key}');
        return entry.value;
      }
    }
    
    // Versuche Partial Match - Cache-Key enthält den bereinigten Namen oder umgekehrt
    for (final entry in _imageCache.entries) {
      final keyLower = entry.key.toLowerCase();
      if ((keyLower.contains(cleanedLower) || cleanedLower.contains(keyLower)) && 
          entry.value.isNotEmpty && 
          keyLower.length > 3) {
        if (kDebugMode) print('  📦 Cache partial match: $title -> ${entry.key}');
        return entry.value;
      }
    }
    
    // Versuche erste 3 Wörter
    final words = cleanedName.split(' ');
    if (words.length > 3) {
      final shortName = words.take(3).join(' ').toLowerCase();
      for (final entry in _imageCache.entries) {
        if (entry.key.toLowerCase() == shortName && entry.value.isNotEmpty) {
          if (kDebugMode) print('  📦 Cache 3-word match: $title -> ${entry.key}');
          return entry.value;
        }
      }
    }
    
    // Versuche erste 2 Wörter
    if (words.length > 2) {
      final shortName = words.take(2).join(' ').toLowerCase();
      for (final entry in _imageCache.entries) {
        if (entry.key.toLowerCase() == shortName && entry.value.isNotEmpty) {
          if (kDebugMode) print('  📦 Cache 2-word match: $title -> ${entry.key}');
          return entry.value;
        }
      }
    }
    
    // Kein Match gefunden - zeige Debug-Info
    if (kDebugMode) print('  ❌ No cache match for: $title (cleaned: $cleanedName)');
    if (_imageCache.isNotEmpty) {
      // Zeige erste 3 Cache-Keys zum Vergleich
      final sampleKeys = _imageCache.keys.take(3).toList();
      if (kDebugMode) print('     Sample cache keys: $sampleKeys');
    }
    
    return null;
  }
  
  /// Bereinigt einen Anime-Namen für die Suche
  String _cleanAnimeName(String animeName) {
    return animeName
        .replaceAll(RegExp(r'Staffel \d+'), '')
        .replaceAll(RegExp(r'Season \d+'), '')
        .replaceAll(RegExp(r'\(English\)'), '')
        .replaceAll(RegExp(r'\(Deutsch\)'), '')
        .replaceAll(RegExp(r'\(German Dub\)'), '')
        .replaceAll(RegExp(r'\(Español.*?\)'), '')
        .replaceAll(RegExp(r'\(Portuguese.*?\)'), '')
        .replaceAll(RegExp(r'\(中文.*?\)'), '')  // Chinesisch
        .replaceAll(RegExp(r'Part \d+'), '')
        .replaceAll(RegExp(r'Teil \d+'), '')
        .replaceAll(RegExp(r'Cour \d+'), '')
        .replaceAll(':', '')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  
  Future<void> _saveToCache(List<AnimeRelease> releases) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Wenn das Scrapergebnis leer ist, überschreibe nicht den existierenden Cache.
      // Das verhindert kurzzeitiges Leeren der UI, falls Background-Scraper fehlschlägt.
      final existing = prefs.getString(_cacheKey);
      if (releases.isEmpty && existing != null && existing.isNotEmpty) {
        if (kDebugMode) print('⚠ Skipping saveToCache because releases is empty and existing cache present');
        return;
      }
      final jsonList = releases.map((r) => r.toJson()).toList();
      await prefs.setString(_cacheKey, json.encode(jsonList));
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
      
      // Speichere auch den Bild-Cache
      await prefs.setString(_imageCacheKey, json.encode(_imageCache));
      
      // Speichere verarbeitete Anime-Titel
      await prefs.setString(_processedAnimeTitlesKey, json.encode(_processedAnimeTitles.toList()));
      
      // Speichere Hash der Releases für Änderungserkennung
      final newHash = _generateReleasesHash(releases);
      await prefs.setString(_releasesHashKey, newHash);
      
      _cachedReleases = releases;
      _currentReleasesHash = newHash;
      if (kDebugMode) print('Saved ${releases.length} releases to cache');
      if (kDebugMode) print('Saved ${_imageCache.length} image URLs to cache');
      if (kDebugMode) print('Saved ${_processedAnimeTitles.length} processed anime titles');
    } catch (e) {
      if (kDebugMode) print('Error saving to cache: $e');
    }
  }
  
  /// Synchronisiert die Watchlist-Einträge mit den gecachten Releases.
  /// Aktualisiert `totalEpisodes` wenn eine höhere Folge bekannt ist und loggt neue Folgen in NotificationRepository.
  Future<void> syncWatchlistWithReleases(WatchlistService watchlistService, NotificationRepository notificationRepo) async {
    try {
      if (_cachedReleases.isEmpty) {
        await getReleasesForWeek(DateTime.now());
      }

      var updated = false;
      String normalize(String? s) => s == null ? '' : s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

      for (final entry in watchlistService.watchlist.entries) {
        final normEntryTitle = normalize(entry.title);
        final matches = _cachedReleases.where((r) {
          // Prefer exact seriesUrl match
          if (r.seriesUrl != null && entry.animeId != null && r.seriesUrl == entry.animeId) return true;
          // Normalize titles and allow contains / equality to be resilient to minor differences
          final rt = normalize(r.title);
          if (rt.isEmpty || normEntryTitle.isEmpty) return false;
          return rt == normEntryTitle || rt.contains(normEntryTitle) || normEntryTitle.contains(rt);
        }).toList();
        if (matches.isEmpty) continue;

        int maxEp = entry.totalEpisodes;
        AnimeRelease? maxRelease;
        for (final r in matches) {
          final parsed = parseEpisodeNumber(r.episodeNumber);
          if (parsed != null && parsed > maxEp) {
            maxEp = parsed;
            maxRelease = r;
          }
        }

        if (maxEp > entry.totalEpisodes && entry.autoSyncTotal) {
          // Create a new WatchlistEntry with the updated totalEpisodes (immutable field)
          final newEntry = WatchlistEntry(
            animeId: entry.animeId,
            title: entry.title,
            imageUrl: entry.imageUrl,
            episodesWatched: entry.episodesWatched,
            totalEpisodes: maxEp,
            status: entry.status,
            notificationsEnabled: entry.notificationsEnabled,
            autoSyncTotal: entry.autoSyncTotal,
            note: entry.note,
            rating: entry.rating,
          );
          // Replace the entry in the watchlist
          watchlistService.watchlist.updateEntry(newEntry);
          updated = true;

          if (maxRelease != null) {
            final log = NotificationLog(
              favoriteId: null,
              favoriteTitle: entry.title,
              releaseTitle: maxRelease.title,
              episodeNumber: normalizeEpisodeString(maxRelease.episodeNumber),
              notifyTime: DateTime.now(),
            );
            final hash = log.generateContentHash();
            final duplicate = await notificationRepo.isDuplicate(hash);
            if (!duplicate) {
              await notificationRepo.logNotification(log.copyWith(contentHash: hash));
            } else {
              if (kDebugMode) print('⏭️ Sync: notification duplicate for ${entry.title} ep ${log.episodeNumber}');
            }
          }
        }
      }

      if (updated) {
        await watchlistService.saveWatchlist();
        if (kDebugMode) print('✓ Watchlist totals updated from releases');
      } else {
        if (kDebugMode) print('✓ No watchlist updates needed');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error syncing watchlist with releases: $e');
    }
  }

  /// Liefert die höchste gefundene Episodennummer für eine Serie aus dem Cache
  /// Versucht zuerst nach `seriesUrl` zu matchen, fällt zurück auf `title`.
  Future<int?> getMaxEpisodeForSeries(String? seriesUrl, String? title) async {
    try {
      // Ensure some cached releases exist
      if (_cachedReleases.isEmpty) {
        if (kDebugMode) print('ℹ️ [CrunchyrollService] Cache empty, fetching week releases');
        await getReleasesForWeek(DateTime.now());
      }

      String normalize(String? s) => s == null ? '' : s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

      // First try exact seriesUrl match
      List<AnimeRelease> matches = [];
      if (seriesUrl != null) {
        matches = _cachedReleases.where((r) => r.seriesUrl != null && r.seriesUrl == seriesUrl).toList();
        if (kDebugMode) print('ℹ️ [CrunchyrollService] getMaxEpisodeForSeries: found ${matches.length} matches by seriesUrl=$seriesUrl');
      }

      // If none, try normalized/fuzzy title matching
      if (matches.isEmpty && title != null) {
        final normTitle = normalize(title);
        matches = _cachedReleases.where((r) {
          final rt = normalize(r.title);
          if (rt.isEmpty || normTitle.isEmpty) return false;
          return rt == normTitle || rt.contains(normTitle) || normTitle.contains(rt);
        }).toList();
        if (kDebugMode) print('ℹ️ [CrunchyrollService] getMaxEpisodeForSeries: found ${matches.length} matches by title="$title"');
      }

      // If still none, try a broader refresh (month) and retry once
      if (matches.isEmpty) {
        if (kDebugMode) print('ℹ️ [CrunchyrollService] No matches in cache, forcing month refresh');
        await forceRefresh(forMonth: DateTime.now());
        final normTitle = normalize(title);
        matches = _cachedReleases.where((r) {
          if (seriesUrl != null && r.seriesUrl != null && r.seriesUrl == seriesUrl) return true;
          final rt = normalize(r.title);
          if (rt.isEmpty || normTitle.isEmpty) return false;
          return rt == normTitle || rt.contains(normTitle) || normTitle.contains(rt);
        }).toList();
        if (kDebugMode) print('ℹ️ [CrunchyrollService] After refresh: found ${matches.length} matches');
      }

      if (matches.isEmpty) {
        if (kDebugMode) print('⚠️ [CrunchyrollService] getMaxEpisodeForSeries: no matches for seriesUrl=$seriesUrl title=$title');
        return null;
      }

      int maxEp = 0;
      for (final r in matches) {
        final parsed = parseEpisodeNumber(r.episodeNumber);
        if (kDebugMode) print('   - candidate: "${r.title}" ep="${r.episodeNumber}" parsed=$parsed');
        if (parsed != null && parsed > maxEp) maxEp = parsed;
      }

      if (kDebugMode) print('✅ [CrunchyrollService] getMaxEpisodeForSeries -> maxEp=$maxEp for title=$title');
      return maxEp > 0 ? maxEp : null;
    } catch (e) {
      if (kDebugMode) print('❌ Error getting max episode for series: $e');
      return null;
    }
  }

  /// Schnell: Liefert die höchste gefundene Episodennummer aus dem LOCALEN Cache (kein Network)
  /// Lädt bei Bedarf den persistenten Cache aus SharedPreferences, aber macht KEINE Scrape/Network-Calls.
  Future<int?> getMaxEpisodeFromCache(String? seriesUrl, String? title) async {
    try {
      if (_cachedReleases.isEmpty) {
        // Load cached releases from SharedPreferences only (no network)
        await _loadFromCache();
      }

      String normalize(String? s) => s == null ? '' : s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

      List<AnimeRelease> matches = [];
      if (seriesUrl != null) {
        matches = _cachedReleases.where((r) => r.seriesUrl != null && r.seriesUrl == seriesUrl).toList();
      }
      if (matches.isEmpty && title != null) {
        final normTitle = normalize(title);
        matches = _cachedReleases.where((r) {
          final rt = normalize(r.title);
          if (rt.isEmpty || normTitle.isEmpty) return false;
          return rt == normTitle || rt.contains(normTitle) || normTitle.contains(rt);
        }).toList();
      }

      if (matches.isEmpty) return null;

      int maxEp = 0;
      for (final r in matches) {
        final parsed = parseEpisodeNumber(r.episodeNumber);
        if (parsed != null && parsed > maxEp) maxEp = parsed;
      }
      return maxEp > 0 ? maxEp : null;
    } catch (e) {
      if (kDebugMode) print('❌ Error in getMaxEpisodeFromCache: $e');
      return null;
    }
  }

  /// Schedules an asynchronous background check to update a watchlist entry if a higher
  /// episode number is discovered. This returns immediately and performs network work
  /// in the background so UI add operations remain fast.
  Future<void> scheduleWatchlistEntryUpdate(WatchlistService watchlistService, WatchlistEntry entry) async {
    // Run in a microtask so caller isn't blocked
    Future.microtask(() async {
      try {
        final known = await getMaxEpisodeForSeries(entry.animeId, entry.title);
        if (known != null && known > entry.totalEpisodes && entry.autoSyncTotal) {
          final newEntry = WatchlistEntry(
            animeId: entry.animeId,
            title: entry.title,
            imageUrl: entry.imageUrl,
            episodesWatched: entry.episodesWatched,
            totalEpisodes: known,
            status: entry.status,
            notificationsEnabled: entry.notificationsEnabled,
            autoSyncTotal: entry.autoSyncTotal,
            note: entry.note,
            rating: entry.rating,
          );
          watchlistService.watchlist.updateEntry(newEntry);
          await watchlistService.saveWatchlist();

          // Log discovered newest episode into NotificationRepository
          try {
            final notificationRepo = NotificationRepository();
            AnimeRelease? candidate;
            try {
              candidate = _cachedReleases.firstWhere((r) => (r.seriesUrl != null && r.seriesUrl == entry.animeId) || r.title.toLowerCase().contains(entry.title.toLowerCase()));
            } catch (_) {
              candidate = null;
            }
            if (candidate != null) {
              final log = NotificationLog(
                favoriteId: null,
                favoriteTitle: entry.title,
                releaseTitle: candidate.title,
                episodeNumber: normalizeEpisodeString(candidate.episodeNumber),
                notifyTime: DateTime.now(),
              );
              final hash = log.generateContentHash();
              final duplicate = await notificationRepo.isDuplicate(hash);
              if (!duplicate) {
                await notificationRepo.logNotification(log.copyWith(contentHash: hash));
              }
            }
          } catch (e) {
            if (kDebugMode) print('❌ scheduleWatchlistEntryUpdate: failed to log notification: $e');
          }
        }
      } catch (e) {
        if (kDebugMode) print('❌ scheduleWatchlistEntryUpdate error: $e');
      }
    });
  }
  
  /// Generiert einen eindeutigen Cache-Key für einen Monat
  String _getMonthCacheKey(DateTime dateInMonth) {
    return 'cached_anime_releases_month_${dateInMonth.year}_${dateInMonth.month.toString().padLeft(2, '0')}_v4';
  }
  
  /// Generiert einen eindeutigen Update-Key für einen Monat
  String _getMonthUpdateKey(DateTime dateInMonth) {
    return 'last_update_month_${dateInMonth.year}_${dateInMonth.month.toString().padLeft(2, '0')}_v4';
  }
  
  /// Speichert Releases eines spezifischen Monats in Cache
  Future<void> _saveMonthToCache(DateTime dateInMonth, List<AnimeRelease> releases) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getMonthCacheKey(dateInMonth);
      final updateKey = _getMonthUpdateKey(dateInMonth);

      // Wenn das Scrapergebnis leer ist, überschreibe nicht den existierenden Monats-Cache.
      final existing = prefs.getString(cacheKey);
      if (releases.isEmpty && existing != null && existing.isNotEmpty) {
        if (kDebugMode) print('⚠ Skipping saveMonthToCache because releases is empty and existing month cache present');
        return;
      }

      final jsonList = releases.map((r) => r.toJson()).toList();
      await prefs.setString(cacheKey, json.encode(jsonList));
      await prefs.setString(updateKey, DateTime.now().toIso8601String());

      if (kDebugMode) print('✓ Saved ${releases.length} releases to month cache for ${dateInMonth.month}/${dateInMonth.year}');
    } catch (e) {
      if (kDebugMode) print('Error saving month to cache: $e');
    }
  }
  
  /// Lädt Releases eines Monats aus Cache
  Future<List<AnimeRelease>> _loadMonthFromCache(DateTime dateInMonth) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getMonthCacheKey(dateInMonth);
      
      // Lade Image-Cache falls noch nicht im Speicher
      if (_imageCache.isEmpty) {
        final imageCacheJson = prefs.getString(_imageCacheKey);
        if (imageCacheJson != null) {
          final Map<String, dynamic> imageMap = json.decode(imageCacheJson);
          _imageCache = imageMap.map((key, value) => MapEntry(key, value.toString()));
          if (kDebugMode) print('Loaded ${_imageCache.length} cached image URLs');
        }
      }
      
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null) {
        final List<dynamic> jsonList = json.decode(cachedJson);
        final releases = jsonList.map((item) => AnimeRelease.fromJson(item)).toList();
        
        // Zähle wie viele Releases noch keine imageUrl haben
        final missingImagesBefore = releases.where((r) => r.imageUrl == null || r.imageUrl!.isEmpty).length;
        
        // Wende gecachte Bilder an
        _applyCachedImagesToReleases(releases);
        
        // Zähle wie viele Releases jetzt noch keine imageUrl haben
        final missingImagesAfter = releases.where((r) => r.imageUrl == null || r.imageUrl!.isEmpty).length;
        
        // Wenn Bilder angewendet wurden, speichere die Releases mit den neuen imageUrls
        if (missingImagesBefore > missingImagesAfter) {
          if (kDebugMode) print('💾 Saving ${missingImagesBefore - missingImagesAfter} newly applied image URLs to month cache');
          await _saveMonthToCache(dateInMonth, releases);
          // Benachrichtige UI
          onImageLoaded?.call();
        }
        
        return releases;
      }
    } catch (e) {
      if (kDebugMode) print('Error loading month from cache: $e');
    }
    return [];
  }
  
  /// Prüft ob der Cache für einen Monat noch aktuell ist (5 Minuten)
  Future<bool> _isMonthCacheValid(DateTime dateInMonth) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updateKey = _getMonthUpdateKey(dateInMonth);
      final lastUpdateStr = prefs.getString(updateKey);
      
      if (lastUpdateStr == null) {
        return false;
      }
      
      final lastUpdate = DateTime.parse(lastUpdateStr);
      final timeSinceUpdate = DateTime.now().difference(lastUpdate);
      final isValid = timeSinceUpdate < _updateInterval;
      
      if (kDebugMode) print('Month cache age: ${timeSinceUpdate.inMinutes} minutes, valid: $isValid');
      return isValid;
    } catch (e) {
      if (kDebugMode) print('Error checking month cache validity: $e');
      return false;
    }
  }

  Future<List<AnimeRelease>> getReleasesForDay(DateTime date) async {
    final weekData = await getReleasesForWeek(date);
    final weekday = date.weekday; // 1 = Monday, 7 = Sunday
    
    return weekData.where((release) {
      return release.releaseTime.weekday == weekday;
    }).toList();
  }

  Future<List<AnimeRelease>> _scrapeCalendarCurrentMonth() async {
    final List<AnimeRelease> allReleases = [];
    
    try {
      if (kDebugMode) print('Scraping Crunchyroll calendar for current month');
      
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0); // Letzter Tag des Monats
      
      if (kDebugMode) print('Loading releases from ${monthStart.day}.${monthStart.month} to ${monthEnd.day}.${monthEnd.month}');
      
      // Finde alle Montage (Wochenstart) im Monat
      DateTime currentWeekStart = monthStart.subtract(Duration(days: monthStart.weekday - 1));
      
      while (currentWeekStart.isBefore(monthEnd) || currentWeekStart.month == now.month) {
        final weekStartStr = '${currentWeekStart.year}-${currentWeekStart.month.toString().padLeft(2, '0')}-${currentWeekStart.day.toString().padLeft(2, '0')}';
        if (kDebugMode) print('Scraping week starting $weekStartStr');
        
        final weekReleases = await _scrapeWeek(currentWeekStart);
        
        // Filtere nur Releases die im aktuellen Monat sind
        final monthReleases = weekReleases.where((release) {
          return release.releaseTime.month == now.month && release.releaseTime.year == now.year;
        }).toList();
        
        allReleases.addAll(monthReleases);
        if (kDebugMode) print('Found ${monthReleases.length} releases in this week for current month');
        
        currentWeekStart = currentWeekStart.add(const Duration(days: 7));
        
        // Verhindere Endlosschleife
        if (currentWeekStart.isAfter(monthEnd.add(const Duration(days: 7)))) {
          break;
        }
      }
      
      if (kDebugMode) print('Total found ${allReleases.length} anime releases for the current month');
      
      // WICHTIG: Zeige ALLE Releases des aktuellen Monats (auch die in der Vergangenheit)
      // Die _generateReleasesHash() und _hasChanges() kümmern sich um zukünftige
      // Die UI wird alle anzeigen können
      
      // Lade fehlende Bilder im Hintergrund (Queue)
      _queueImageLoading(allReleases, now);
      
      return allReleases;
    } catch (e) {
      if (kDebugMode) print('Error scraping calendar: $e');
    }
    
    return allReleases;
  }
  
  /// Scraped einen spezifischen Monat on-demand (für vergangene Monate)
  /// Diese Daten werden NICHT gecacht, nur beim Abruf geladen
  Future<List<AnimeRelease>> _scrapeSpecificMonth(DateTime dateInMonth) async {
    final List<AnimeRelease> allReleases = [];
    
    try {
      if (kDebugMode) print('Scraping Crunchyroll calendar for specific month: ${dateInMonth.month}/${dateInMonth.year}');
      
      final monthStart = DateTime(dateInMonth.year, dateInMonth.month, 1);
      final monthEnd = DateTime(dateInMonth.year, dateInMonth.month + 1, 0); // Letzter Tag des Monats
      
      if (kDebugMode) print('Loading releases from ${monthStart.day}.${monthStart.month} to ${monthEnd.day}.${monthEnd.month}');
      
      // Finde alle Montage (Wochenstart) im Monat
      DateTime currentWeekStart = monthStart.subtract(Duration(days: monthStart.weekday - 1));
      
      while (currentWeekStart.isBefore(monthEnd) || currentWeekStart.month == dateInMonth.month) {
        final weekStartStr = '${currentWeekStart.year}-${currentWeekStart.month.toString().padLeft(2, '0')}-${currentWeekStart.day.toString().padLeft(2, '0')}';
        if (kDebugMode) print('Scraping week starting $weekStartStr');
        
        final weekReleases = await _scrapeWeek(currentWeekStart);
        
        // Filtere nur Releases die im angefragten Monat sind
        final monthReleases = weekReleases.where((release) {
          return release.releaseTime.month == dateInMonth.month && release.releaseTime.year == dateInMonth.year;
        }).toList();
        
        allReleases.addAll(monthReleases);
        if (kDebugMode) print('Found ${monthReleases.length} releases in this week');
        
        currentWeekStart = currentWeekStart.add(const Duration(days: 7));
        
        // Verhindere Endlosschleife
        if (currentWeekStart.isAfter(monthEnd.add(const Duration(days: 7)))) {
          break;
        }
      }
      
      if (kDebugMode) print('Total found ${allReleases.length} anime releases for ${dateInMonth.month}/${dateInMonth.year}');
      
      // WICHTIG: Wende gecachte Bilder an (falls vorhanden)
      _applyCachedImagesToReleases(allReleases);
      
      // Lade neue Bilder im Hintergrund (Queue)
      _queueImageLoading(allReleases, DateTime.now());
      
      return allReleases;
    } catch (e) {
      if (kDebugMode) print('Error scraping specific month: $e');
    }
    
    return allReleases;
  }
  
  /// Alte _scrapeCalendar - für force refresh
  Future<List<AnimeRelease>> _scrapeCalendar() async {
    return _scrapeCalendarCurrentMonth();
  }
  
  Future<List<AnimeRelease>> _scrapeWeek(DateTime weekStart) async {
    final List<AnimeRelease> weekReleases = [];
    
    try {
      // Formatiere Datum für URL: YYYY-MM-DD
      final dateStr = '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
      final weekUrl = '$calendarUrl&date=$dateStr';
      
      if (kDebugMode) print('Loading week from: $weekUrl');
      
      final response = await http.get(
        Uri.parse(weekUrl),
        headers: {
          'User-Agent': 'MeineApp/1.0',
        },
      );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        // Map von Selector zu Tag-Offset (basierend auf weekStart)
        final daySelectors = {
          '.day:first-child': 0,      // Montag
          '.day:nth-child(3)': 1,     // Dienstag
          '.day:nth-child(5)': 2,     // Mittwoch
          '.day:nth-child(7)': 3,     // Donnerstag
          '.day:nth-child(9)': 4,     // Freitag
          '.day:nth-child(11)': 5,    // Samstag
          '.day:nth-child(13)': 6,    // Sonntag
        };
        
        // Sammle alle Releases der Woche - basierend auf der alten funktionierenden Logik
        for (var entry in daySelectors.entries) {
          final selector = entry.key;
          final dayOffset = entry.value;
          final dayDate = weekStart.add(Duration(days: dayOffset));
          
          final dayElements = document.querySelectorAll(selector);
          
          for (var dayElement in dayElements) {
            // Sammle alle Infos separat wie in der alten Implementierung
            
            // 1. Anime Namen sammeln (aus .season-name mit itemprop="name")
            final List<String> animeNames = [];
            final List<String> animeLinks = [];
            final seasonNameElements = dayElement.querySelectorAll('.season-name');
            for (var seasonElement in seasonNameElements) {
              final nameElement = seasonElement.querySelector('[itemprop="name"]');
              if (nameElement != null) {
                animeNames.add(nameElement.text.trim());
              }
              
              final linkElements = seasonElement.querySelectorAll('a');
              for (var anchor in linkElements) {
                final url = anchor.attributes['href'];
                if (url != null && url.isNotEmpty) {
                  animeLinks.add(url);
                  break; // nur erster Link pro Anime
                }
              }
            }
            
            // 2. Episode-Infos aus .availability sammeln
            final List<String> episodeInfos = [];
            final availabilityElements = dayElement.querySelectorAll('.availability');
            for (var availElement in availabilityElements) {
              final linkElements = availElement.querySelectorAll('a');
              for (var link in linkElements) {
                final text = link.text.trim().replaceAll('\n', '').replaceAll('Verfügbar', '').trim();
                episodeInfos.add(text);
              }
            }
            
            // 3. Uhrzeiten aus .available-time sammeln
            final List<String> times = [];
            final timeElements = dayElement.querySelectorAll('.available-time');
            for (var timeElement in timeElements) {
              times.add(timeElement.text.trim());
            }
            
            // Kombiniere die Daten
            for (var i = 0; i < animeNames.length; i++) {
              try {
                final animeName = animeNames[i];
                final animeLink = i < animeLinks.length ? animeLinks[i] : '';
                final episodeInfo = i < episodeInfos.length ? episodeInfos[i] : '';
                final timeStr = i < times.length ? times[i] : '';
                
                // Prüfe auf Premiere
                final isPremiere = episodeInfo.toLowerCase().contains('premiere') || 
                                   episodeInfo.toLowerCase().contains('folge 1') ||
                                   episodeInfo.contains('Folge 1');
                
                // Extrahiere Episode-Nummer
                var episodeNumber = '1';
                final episodeMatch = RegExp(r'[Ff]olge[n]?\s*(\d+)|[Ee]pisode[sn]?\s*(\d+)').firstMatch(episodeInfo);
                if (episodeMatch != null) {
                  episodeNumber = episodeMatch.group(1) ?? episodeMatch.group(2) ?? '1';
                }
                
                // Parse Zeit
                var releaseTime = dayDate;
                if (timeStr.isNotEmpty) {
                  // Format: "2:30pm" oder "14:30"
                  final timeMatch = RegExp(r'(\d{1,2}):(\d{2})\s*(am|pm)?', caseSensitive: false).firstMatch(timeStr);
                  if (timeMatch != null) {
                    var hour = int.parse(timeMatch.group(1)!);
                    final minute = int.parse(timeMatch.group(2)!);
                    final period = timeMatch.group(3)?.toLowerCase();
                    
                    if (period != null) {
                      // AM/PM Format
                      if (period == 'pm' && hour != 12) {
                        hour += 12;
                      } else if (period == 'am' && hour == 12) {
                        hour = 0;
                      }
                    }
                    
                    releaseTime = DateTime(dayDate.year, dayDate.month, dayDate.day, hour, minute);
                  }
                }
                
                // Release hinzufügen
                weekReleases.add(AnimeRelease(
                  title: animeName,
                  episodeNumber: episodeNumber,
                  episodeTitle: episodeInfo,
                  releaseTime: releaseTime,
                  imageUrl: null,
                  seriesUrl: animeLink.startsWith('http') ? animeLink : 'https://www.crunchyroll.com$animeLink',
                  episodeUrl: animeLink.startsWith('http') ? animeLink : 'https://www.crunchyroll.com$animeLink',
                  isPremiere: isPremiere,
                ));
                
              } catch (e) {
                if (kDebugMode) print('Error parsing anime at index $i: $e');
                continue;
              }
            }
          }
        }
        
      } else {
        if (kDebugMode) print('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('Error scraping week: $e');
    }
    
    return weekReleases;
  }
  
  Future<void> _loadMissingImagesFromAniList(List<AnimeRelease> releases, DateTime today) async {
    // Lade verarbeitete Titel Falls nicht im Speicher (bei Start)
    if (_processedAnimeTitles.isEmpty) {
      await _loadProcessedAnimeTitles();
    }
    
    // Wende zuerst gecachte Bilder an
    _applyCachedImagesToReleases(releases);
    
    // Finde alle Releases ohne Bild (die nicht im Cache waren)
    final releasesNeedingImages = releases.where((r) => 
      r.imageUrl == null || r.imageUrl!.isEmpty
    ).toList();
    
    // Filtere alle Releases die BEREITS verarbeitet wurden
    final newReleasesToProcess = releasesNeedingImages.where((r) => 
      !_processedAnimeTitles.contains(r.title)
    ).toList();
    
    // Sortiere: Heute zuerst, dann andere Tage
    newReleasesToProcess.sort((a, b) {
      final aIsToday = a.releaseTime.day == today.day && 
                       a.releaseTime.month == today.month && 
                       a.releaseTime.year == today.year;
      final bIsToday = b.releaseTime.day == today.day && 
                       b.releaseTime.month == today.month && 
                       b.releaseTime.year == today.year;
      
      if (aIsToday && !bIsToday) return -1;
      if (!aIsToday && bIsToday) return 1;
      return 0;
    });
    
    final total = newReleasesToProcess.length;
    final alreadyProcessed = releasesNeedingImages.length - total;
    
    if (alreadyProcessed > 0) {
      if (kDebugMode) print('⏩ Skipping ${alreadyProcessed} already processed anime titles (${_processedAnimeTitles.length} total in memory)');
    }
    
    if (total == 0) {
      if (kDebugMode) print('✓ All anime image titles already processed');
      return;
    }
    
    if (kDebugMode) print('📥 Loading $total missing images from Kitsu (${_processedAnimeTitles.length} already processed)...');
    
    // Signalisiere Start des Ladens
    onImageLoadingChanged?.call(true, 0, total);
    
    var loaded = 0;
    
    // Lade Bilder von Kitsu im Hintergrund
    for (var release in newReleasesToProcess) {
      try {
        final imageUrl = await _fetchImageFromKitsu(release.title);
        if (imageUrl.isNotEmpty) {
          // Update das Release-Objekt
          release.imageUrl = imageUrl;
          if (kDebugMode) print('✓ Kitsu: Found cover for ${release.title}');
          
          // Benachrichtige UI dass ein Bild geladen wurde
          onImageLoaded?.call();
        } else {
          if (kDebugMode) print('✗ Kitsu: No cover found for ${release.title}');
        }
      } catch (e) {
        if (kDebugMode) print('✗ Kitsu: Failed for ${release.title}: $e');
      }
      
      // Markiere diesen Titel als verarbeitet (egal ob erfolgreich oder nicht)
      _processedAnimeTitles.add(release.title);
      
      // Speichere verarbeiteten Titel UND Image-Cache SOFORT nach jedem Bild
      // damit bei App-Abbruch der Fortschritt nicht verloren geht
      await _saveProcessedTitles();
      await _saveImageCache();
      
      loaded++;
      onImageLoadingChanged?.call(true, loaded, total);
      
      // Kleine Pause um Kitsu API nicht zu überlasten
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // Signalisiere Ende des Ladens
    onImageLoadingChanged?.call(false, total, total);
    
    // Speichere aktualisierten Cache inkl. verarbeitete Titel
    if (total > 0) {
      await _saveToCache(releases);
    }
  }
  
  /// Lädt die Liste der bereits verarbeiteten Anime-Titel aus dem Speicher
  Future<void> _loadProcessedAnimeTitles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final processedTitlesJson = prefs.getString(_processedAnimeTitlesKey);
      
      if (processedTitlesJson != null) {
        final List<dynamic> titlesList = json.decode(processedTitlesJson);
        _processedAnimeTitles = titlesList.cast<String>().toSet();
        if (kDebugMode) print('Loaded ${_processedAnimeTitles.length} processed anime titles');
      } else {
        _processedAnimeTitles = {};
      }
    } catch (e) {
      if (kDebugMode) print('Error loading processed anime titles: $e');
      _processedAnimeTitles = {};
    }
  }
  
  /// Speichert die verarbeiteten Anime-Titel sofort persistent
  Future<void> _saveProcessedTitles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_processedAnimeTitlesKey, json.encode(_processedAnimeTitles.toList()));
    } catch (e) {
      if (kDebugMode) print('Error saving processed titles: $e');
    }
  }
  
  /// Speichert den Image-Cache persistent
  Future<void> _saveImageCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_imageCacheKey, json.encode(_imageCache));
    } catch (e) {
      if (kDebugMode) print('Error saving image cache: $e');
    }
  }
  
  Future<String> _fetchImageFromKitsu(String animeName) async {
    try {
      // Bereinige den Anime-Namen für bessere Suchergebnisse
      var searchName = _cleanAnimeName(animeName);
      
      // Entferne Sonderzeichen außer Leerzeichen, Buchstaben und Zahlen
      searchName = searchName.replaceAll(RegExp(r'[^\w\s\-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      
      if (searchName.isEmpty) {
        return '';
      }
      
      // Prüfe zuerst ob wir das Bild bereits im Cache haben (und nicht leer)
      if (_imageCache.containsKey(searchName) && _imageCache[searchName]!.isNotEmpty) {
        if (kDebugMode) print('📦 Cache hit for: $searchName');
        return _imageCache[searchName]!;
      }
      
      // Versuche zuerst mit dem bereinigten Namen
      var imageUrl = await _queryKitsu(searchName);
      if (imageUrl.isNotEmpty) {
        // Speichere im Cache
        _imageCache[searchName] = imageUrl;
        return imageUrl;
      }
      
      // Spezialfall: Entferne einzelne Buchstaben wie "x" (z.B. "SPY x FAMILY" -> "SPY FAMILY")
      final wordsNoSingle = searchName.split(' ').where((w) => w.length > 1).toList();
      if (wordsNoSingle.length != searchName.split(' ').length && wordsNoSingle.isNotEmpty) {
        final nameNoSingle = wordsNoSingle.join(' ');
        imageUrl = await _queryKitsu(nameNoSingle);
        if (imageUrl.isNotEmpty) {
          _imageCache[searchName] = imageUrl;
          return imageUrl;
        }
      }
      
      // Fallback: Wenn mehr als 3 Wörter, versuche nur die ersten 3
      final words = searchName.split(' ');
      if (words.length > 3) {
        final shortName = words.take(3).join(' ');
        imageUrl = await _queryKitsu(shortName);
        if (imageUrl.isNotEmpty) {
          _imageCache[searchName] = imageUrl;
          return imageUrl;
        }
      }
      
      // Fallback: Versuche nur die ersten 2 Wörter
      if (words.length > 2) {
        final shortName = words.take(2).join(' ');
        imageUrl = await _queryKitsu(shortName);
        if (imageUrl.isNotEmpty) {
          _imageCache[searchName] = imageUrl;
          return imageUrl;
        }
      }
      
      // Fallback: Versuche nur die ersten 2 Wörter (ohne einzelne Buchstaben)
      if (wordsNoSingle.length > 2) {
        final shortName = wordsNoSingle.take(2).join(' ');
        imageUrl = await _queryKitsu(shortName);
        if (imageUrl.isNotEmpty) {
          _imageCache[searchName] = imageUrl;
          return imageUrl;
        }
      }
      
      // Kein Bild gefunden - als leer cachen um erneute Suche zu vermeiden
      _imageCache[searchName] = '';
      
    } catch (e) {
      // Fehler ignorieren
    }
    return '';
  }
  
  Future<String> _queryKitsu(String searchName) async {
    try {
      // Lade Bildqualität aus Einstellungen
      final imageQuality = await AppSettings.getImageQuality();
      
      // Kitsu API - Text Suche
      final encodedSearch = Uri.encodeComponent(searchName);
      final url = 'https://kitsu.io/api/edge/anime?filter[text]=$encodedSearch&page[limit]=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        },
      );
      
      if (response.statusCode == 200) {
        // Parse JSON Response - suche nach posterImage
        final body = response.body;
        
        // Versuche gewünschte Qualität zu finden
        var imageMatch = RegExp('"posterImage":\\s*\\{[^}]*"$imageQuality":\\s*"([^"]+)"').firstMatch(body);
        if (imageMatch != null) {
          final imageUrl = imageMatch.group(1)!.replaceAll(r'\/', '/');
          return imageUrl;
        }
        
        // Fallback-Reihenfolge: original -> large -> medium -> small
        final fallbackOrder = ['original', 'large', 'medium', 'small'];
        for (final quality in fallbackOrder) {
          if (quality == imageQuality) continue; // Schon versucht
          imageMatch = RegExp('"posterImage":\\s*\\{[^}]*"$quality":\\s*"([^"]+)"').firstMatch(body);
          if (imageMatch != null) {
            final imageUrl = imageMatch.group(1)!.replaceAll(r'\/', '/');
            return imageUrl;
          }
        }
      }
    } catch (e) {
      // Fehler ignorieren
    }
    return '';
  }
  
  /// Lädt die Beschreibung eines Anime von Kitsu API
  Future<String> fetchDescription(AnimeRelease release) async {
    // Prüfe ob bereits geladen
    if (release.description != null && release.description!.isNotEmpty && 
        release.description != 'Keine Beschreibung verfügbar') {
      return release.description!;
    }
    
    final animeName = release.title;
    if (kDebugMode) print('Fetching description for: $animeName');
    
    try {
      // Verwende Kitsu API - gleiche Logik wie für Bilder
      final searchName = _cleanAnimeName(animeName);
      
      // Kitsu API - Text Suche
      final encodedSearch = Uri.encodeComponent(searchName);
      final url = 'https://kitsu.io/api/edge/anime?filter[text]=$encodedSearch&page[limit]=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final data = jsonData['data'] as List?;
        
        if (data != null && data.isNotEmpty) {
          final attributes = data[0]['attributes'];
          
          // Versuche deutsche Beschreibung (synopsis_de) oder englische (synopsis)
          String? synopsis = attributes['synopsis'];
          
          if (synopsis != null && synopsis.isNotEmpty) {
            release.description = synopsis.trim();
            if (kDebugMode) print('✓ Found description from Kitsu: ${synopsis.substring(0, synopsis.length > 50 ? 50 : synopsis.length)}...');
            return release.description!;
          }
        }
      }
      
      // Fallback: Versuche mit kürzerem Namen
      final words = searchName.split(' ');
      if (words.length > 3) {
        final shortName = words.take(3).join(' ');
        final shortDesc = await _queryKitsuDescription(shortName);
        if (shortDesc.isNotEmpty) {
          release.description = shortDesc;
          return release.description!;
        }
      }
      
    } catch (e) {
      if (kDebugMode) print('Error fetching description from Kitsu: $e');
    }
    
    release.description = 'Keine Beschreibung verfügbar';
    return release.description!;
  }
  
  Future<String> _queryKitsuDescription(String searchName) async {
    try {
      final encodedSearch = Uri.encodeComponent(searchName);
      final url = 'https://kitsu.io/api/edge/anime?filter[text]=$encodedSearch&page[limit]=1';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final data = jsonData['data'] as List?;
        
        if (data != null && data.isNotEmpty) {
          final synopsis = data[0]['attributes']?['synopsis'];
          if (synopsis != null && synopsis.isNotEmpty) {
            return synopsis.trim();
          }
        }
      }
    } catch (e) {
      // Fehler ignorieren
    }
    return '';
  }

  /// Lädt einen spezifischen Monat aus dem Cache
  /// Wird von main.dart verwendet um Punkte in allen Monaten anzuzeigen
  Future<List<AnimeRelease>> getReleasesForMonthFromCache(DateTime dateInMonth) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getMonthCacheKey(dateInMonth);
      
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null) {
        final List<dynamic> jsonList = json.decode(cachedJson);
        final releases = jsonList.map((item) => AnimeRelease.fromJson(item)).toList();
        
        // Wende gecachte Bilder an
        _applyCachedImagesToReleases(releases);
        
        return releases;
      }
    } catch (e) {
      if (kDebugMode) print('Error loading month from cache: $e');
    }
    return [];
  }
  
  /// Gibt alle verfügbaren Monate zurück, die gecacht sind (Jahr, Monat)
  Future<List<(int, int)>> getCachedMonths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      final regex = RegExp(r'cached_anime_releases_month_(\d{4})_(\d{2})_v4');
      final months = <(int, int)>{};
      
      for (String key in allKeys) {
        final match = regex.firstMatch(key);
        if (match != null) {
          final year = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          months.add((year, month));
        }
      }
      
      return months.toList();
    } catch (e) {
      if (kDebugMode) print('Error getting cached months: $e');
      return [];
    }
  }
}
