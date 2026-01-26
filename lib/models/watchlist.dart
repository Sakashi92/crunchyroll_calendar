import 'package:flutter/foundation.dart';

enum WatchStatus { watching, completed, paused, dropped }

class WatchlistEntry {
  String animeId; // Not final anymore to allow URL updates
  final String title;
  final String? imageUrl;
  int episodesWatched;
  int totalEpisodes;
  WatchStatus status;
  bool notificationsEnabled;
  bool autoSyncTotal;
  String? note;
  double? rating;
  int? anilistId; // Added field for manual linking
  DateTime? addedAt;
  bool? isCrunchyroll;
  bool predictionsEnabled;
  String? airingStatus; // Added field for airing status (e.g. FINISHED)
  String? customTitle; // Added field for user-defined anime title

  WatchlistEntry({
    required this.animeId,
    required this.title,
    this.imageUrl,
    required this.episodesWatched,
    required this.totalEpisodes,
    this.status = WatchStatus.watching,
    this.notificationsEnabled = false,
    this.autoSyncTotal = true,
    this.note,
    this.rating,
    this.anilistId,
    this.addedAt,
    this.isCrunchyroll,
    this.predictionsEnabled = true,
    this.airingStatus,
    this.customTitle,
  });

  WatchlistEntry copyWith({
    String? animeId,
    String? title,
    String? imageUrl,
    int? episodesWatched,
    int? totalEpisodes,
    WatchStatus? status,
    bool? notificationsEnabled,
    bool? autoSyncTotal,
    String? note,
    double? rating,
    int? anilistId,
    DateTime? addedAt,
    bool? isCrunchyroll,
    bool? predictionsEnabled,
    String? airingStatus,
    String? customTitle,
  }) {
    return WatchlistEntry(
      animeId: animeId ?? this.animeId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      episodesWatched: episodesWatched ?? this.episodesWatched,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      status: status ?? this.status,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoSyncTotal: autoSyncTotal ?? this.autoSyncTotal,
      note: note ?? this.note,
      rating: rating ?? this.rating,
      anilistId: anilistId ?? this.anilistId,
      addedAt: addedAt ?? this.addedAt,
      isCrunchyroll: isCrunchyroll ?? this.isCrunchyroll,
      predictionsEnabled: predictionsEnabled ?? this.predictionsEnabled,
      airingStatus: airingStatus ?? this.airingStatus,
      customTitle: customTitle ?? this.customTitle,
    );
  }
}

class Watchlist extends ChangeNotifier {
  final List<WatchlistEntry> _entries = [];

  List<WatchlistEntry> get entries => List.unmodifiable(_entries);

  void addEntry(WatchlistEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void removeEntry(String animeId) {
    _entries.removeWhere((e) => e.animeId == animeId);
    notifyListeners();
  }

  void updateEntry(WatchlistEntry entry) {
    final index = _entries.indexWhere((e) => e.animeId == entry.animeId);
    if (index != -1) {
      _entries[index] = entry;
      notifyListeners();
    }
  }

  /// Updates the ID of an entry and notifies listeners.
  void renameEntry(String oldId, String newId) {
    final index = _entries.indexWhere((e) => e.animeId == oldId);
    if (index != -1) {
      _entries[index].animeId = newId;
      notifyListeners();
    }
  }

  /// Ersetzt alle Einträge in der Watchlist.
  void replaceAll(List<WatchlistEntry> entries) {
    _entries.clear();
    _entries.addAll(entries);
    notifyListeners();
  }
}
