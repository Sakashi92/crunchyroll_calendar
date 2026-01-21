import 'package:shared_preferences/shared_preferences.dart';

class SeenRepository {
  static const String _seenKey = 'seen_releases';

  Future<List<String>> getAllSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_seenKey)?.toList() ?? <String>[];
  }

  Future<bool> isSeen(String contentHash) async {
    if (contentHash.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_seenKey);
    if (list == null) return false;
    return list.contains(contentHash);
  }

  Future<void> markSeen(String contentHash) async {
    if (contentHash.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_seenKey)?.toList() ?? <String>[];
    if (!list.contains(contentHash)) {
      list.insert(0, contentHash);
      // keep list bounded
      if (list.length > 500) list.removeRange(500, list.length);
      await prefs.setStringList(_seenKey, list);
    }
  }

  Future<void> clearSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_seenKey);
  }
}
