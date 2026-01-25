import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/anime_metadata.dart';
import 'package:flutter/foundation.dart';

class AnilistCache {
  static const String _storageKey = 'anilist_metadata_cache_v1';

  // Singleton instance
  static final AnilistCache _instance = AnilistCache._internal();
  factory AnilistCache() => _instance;
  AnilistCache._internal();

  // In-memory cache
  Map<String, AnimeMetadata>? _memoryCache;

  // Debouncer for disk writes
  Timer? _saveDebouncer;
  bool _isDirty = false;

  /// Ensures the cache is loaded from disk into memory.
  Future<void> _ensureLoaded() async {
    if (_memoryCache != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) {
        _memoryCache = {};
        return;
      }

      final Map<String, dynamic> map = json.decode(raw) as Map<String, dynamic>;
      _memoryCache = {};

      map.forEach((key, val) {
        if (val is Map) {
          _memoryCache![key] = AnimeMetadata.fromJson(
            Map<String, dynamic>.from(val),
          );
        } else if (val is String) {
          try {
            final decoded = json.decode(val);
            _memoryCache![key] = AnimeMetadata.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          } catch (_) {}
        }
      });

      if (kDebugMode) {
        print('📦 [CACHE] Loaded ${_memoryCache!.length} entries into memory');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [CACHE] Load error: $e');
      }
      _memoryCache = {};
    }
  }

  Future<AnimeMetadata?> get(String key) async {
    await _ensureLoaded();
    return _memoryCache![key];
  }

  Future<void> save(String key, AnimeMetadata meta) async {
    await _ensureLoaded();

    _memoryCache![key] = meta;
    _isDirty = true;

    // Debounce save to disk
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(seconds: 2), _flushToDisk);
  }

  /// Writes current memory state to disk
  Future<void> _flushToDisk() async {
    if (!_isDirty || _memoryCache == null) return;

    try {
      if (kDebugMode) {
        print('💾 [CACHE] Flushing ${_memoryCache!.length} entries to disk...');
      }

      final prefs = await SharedPreferences.getInstance();

      // Convert all meta objects to JSON maps
      final Map<String, dynamic> exportMap = {};
      _memoryCache!.forEach((key, val) {
        exportMap[key] = val.toJson();
      });

      await prefs.setString(_storageKey, json.encode(exportMap));
      _isDirty = false;

      if (kDebugMode) {
        print('✅ [CACHE] Flushed successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [CACHE] Flush error: $e');
      }
    }
  }

  Future<void> clear() async {
    _memoryCache = {};
    _isDirty = false;
    _saveDebouncer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
