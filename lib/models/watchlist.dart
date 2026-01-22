import 'package:flutter/foundation.dart';

enum WatchStatus {
  watching,
  completed,
  paused,
  dropped,
}

class WatchlistEntry {
  final String animeId;
  final String title;
  final String? imageUrl;
  int episodesWatched;
  final int totalEpisodes;
  WatchStatus status;
  String? note;
  double? rating;

  WatchlistEntry({
    required this.animeId,
    required this.title,
    this.imageUrl,
    required this.episodesWatched,
    required this.totalEpisodes,
    this.status = WatchStatus.watching,
    this.note,
    this.rating,
  });
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

  /// Ersetzt alle Einträge in der Watchlist.
  void replaceAll(List<WatchlistEntry> entries) {
    _entries.clear();
    _entries.addAll(entries);
    notifyListeners();
  }
}
