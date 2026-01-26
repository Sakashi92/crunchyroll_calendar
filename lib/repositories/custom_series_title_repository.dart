import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class CustomSeriesTitleRepository extends ChangeNotifier {
  static const String _storageKey = 'custom_series_titles';
  static final CustomSeriesTitleRepository _instance =
      CustomSeriesTitleRepository._internal();

  factory CustomSeriesTitleRepository() {
    return _instance;
  }

  CustomSeriesTitleRepository._internal();

  Map<String, String> _titles = {};
  bool _initialized = false;

  Future<void> reload() async {
    _initialized = false;
    await _init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final map = json.decode(jsonString) as Map<String, dynamic>;
        _titles = map.map((key, value) => MapEntry(key, value.toString()));
      }
      _initialized = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing CustomSeriesTitleRepository: $e');
      }
    }
  }

  Future<void> setTitle(String seriesUrl, String? title) async {
    await _init();
    if (title == null || title.isEmpty) {
      _titles.remove(seriesUrl);
    } else {
      _titles[seriesUrl] = title;
    }
    notifyListeners();
    await _save();
  }

  Future<String?> getTitle(String seriesUrl) async {
    await _init();
    return _titles[seriesUrl];
  }

  String? getTitleSync(String seriesUrl) {
    if (!_initialized) return null;
    return _titles[seriesUrl];
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json.encode(_titles));
    } catch (e) {
      if (kDebugMode) print('❌ Error saving CustomSeriesTitleRepository: $e');
    }
  }

  Future<void> loadCache() async {
    await _init();
  }
}
