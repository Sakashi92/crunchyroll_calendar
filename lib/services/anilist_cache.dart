import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/anime_metadata.dart';

class AnilistCache {
  static const String _storageKey = 'anilist_metadata_cache_v1';

  Future<AnimeMetadata?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return null;
      final Map<String, dynamic> map = json.decode(raw) as Map<String, dynamic>;
      if (!map.containsKey(key)) return null;
      final val = map[key];
      if (val is Map) {
        return AnimeMetadata.fromJson(Map<String, dynamic>.from(val));
      }
      if (val is String) {
        final decoded = json.decode(val);
        return AnimeMetadata.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> save(String key, AnimeMetadata meta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final Map<String, dynamic> map = raw != null ? json.decode(raw) as Map<String, dynamic> : <String, dynamic>{};
      map[key] = meta.toJson();
      await prefs.setString(_storageKey, json.encode(map));
    } catch (e) {
      // ignore cache failures
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
