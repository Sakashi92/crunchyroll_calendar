import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watchlist.dart';

class WatchlistService {
  static const _storageKey = 'watchlist_data';
  final Watchlist watchlist;

  WatchlistService(this.watchlist);

  Future<void> loadWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      final parsed = jsonList.map((e) => WatchlistEntry(
        animeId: e['animeId'],
        title: e['title'],
        imageUrl: e['imageUrl'],
        episodesWatched: e['episodesWatched'],
        totalEpisodes: e['totalEpisodes'],
        status: WatchStatus.values[e['status']],
        note: e['note'],
        rating: (e['rating'] as num?)?.toDouble(),
      )).toList();
      watchlist.replaceAll(parsed);
    }
  }

  Future<void> saveWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = watchlist.entries.map((e) => {
      'animeId': e.animeId,
      'title': e.title,
      'imageUrl': e.imageUrl,
      'episodesWatched': e.episodesWatched,
      'totalEpisodes': e.totalEpisodes,
      'status': e.status.index,
      'note': e.note,
      'rating': e.rating,
    }).toList();
    await prefs.setString(_storageKey, json.encode(jsonList));
  }

  Future<String> exportToJson() async {
    final jsonList = watchlist.entries.map((e) => {
      'animeId': e.animeId,
      'title': e.title,
      'imageUrl': e.imageUrl,
      'episodesWatched': e.episodesWatched,
      'totalEpisodes': e.totalEpisodes,
      'status': e.status.index,
      'note': e.note,
      'rating': e.rating,
    }).toList();
    return json.encode(jsonList);
  }

  Future<void> importFromJson(String jsonString) async {
    final List<dynamic> jsonList = json.decode(jsonString);
    final parsed = jsonList.map((e) => WatchlistEntry(
      animeId: e['animeId'],
      title: e['title'],
      imageUrl: e['imageUrl'],
      episodesWatched: e['episodesWatched'],
      totalEpisodes: e['totalEpisodes'],
      status: WatchStatus.values[e['status']],
      note: e['note'],
      rating: (e['rating'] as num?)?.toDouble(),
    )).toList();
    watchlist.replaceAll(parsed);
    await saveWatchlist();
  }

  Future<File> exportToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/watchlist_export.json');
    final jsonString = await exportToJson();
    return file.writeAsString(jsonString);
  }

  Future<void> importFromFile(File file) async {
    final jsonString = await file.readAsString();
    await importFromJson(jsonString);
  }
}
