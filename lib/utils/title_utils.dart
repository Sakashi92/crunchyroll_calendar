import 'dart:core';

/// Utilities for normalizing titles and computing simple similarity.

String normalizeTitle(String? s) {
  if (s == null) return '';
  var t = s.trim().toLowerCase();
  // remove HTML entities commonly found
  t = t.replaceAll('&amp;', '&');
  // replace common diacritics
  const replacements = {
    'ä': 'a',
    'ö': 'o',
    'ü': 'u',
    'ß': 'ss',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ñ': 'n',
    'ç': 'c',
  };
  replacements.forEach((k, v) {
    t = t.replaceAll(k, v);
  });
  // remove punctuation and extra spaces
  t = t.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
  t = t.replaceAll(RegExp(r"\s+"), ' ').trim();
  return t;
}

int _levenshtein(String s, String t) {
  final n = s.length;
  final m = t.length;
  if (n == 0) return m;
  if (m == 0) return n;
  List<List<int>> d = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
      d[i][j] = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return d[n][m];
}

/// Returns similarity between 0.0 and 1.0 (1.0 means identical)
double similarity(String a, String b) {
  final s = normalizeTitle(a);
  final t = normalizeTitle(b);
  if (s.isEmpty && t.isEmpty) return 1.0;
  if (s.isEmpty || t.isEmpty) return 0.0;
  final dist = _levenshtein(s, t);
  final maxLen = s.length > t.length ? s.length : t.length;
  if (maxLen == 0) return 0.0;
  return 1.0 - (dist / maxLen);
}

/// Checks if [target] is likely a sequel, movie or different version of [query].
/// e.g. "Dragon Ball Z" is a sequel of "Dragon Ball".
bool isLikelySequel(String query, String target) {
  final q = normalizeTitle(query);
  final t = normalizeTitle(target);
  if (q == t) return false;

  if (t.startsWith(q + ' ')) {
    final suffix = t.substring(q.length).trim();
    // Common sequel/version markers
    final markers = [
      'z',
      'gt',
      'kai',
      'super',
      's2',
      's3',
      's4',
      'part 2',
      'part 3',
      'season 2',
      'season 3',
      'movie',
      'film',
      'special',
      'ova',
    ];
    if (markers.contains(suffix) || RegExp(r'^\d+$').hasMatch(suffix)) {
      return true;
    }
  }
  return false;
}

bool isStrictMatch(String query, String result) {
  final q = normalizeTitle(query);
  final r = normalizeTitle(result);
  if (q == r) return true;

  // If result is longer than query and looks like a sequel/variation, it's NOT a strict match
  if (isLikelySequel(query, result)) return false;

  // Word set similarity: Ensures that "Dragon Ball" and "Dragon Raja" don't match
  // even if "Dragon" is shared.
  final set1 = q.split(' ').where((w) => w.length > 1).toSet();
  final set2 = r.split(' ').where((w) => w.length > 1).toSet();

  if (set1.isNotEmpty && set2.isNotEmpty) {
    final intersection = set1.intersection(set2);
    final overlap = intersection.length / set1.length;
    if (overlap < 0.7)
      return false; // Require at least 70% of query words to be present
  }

  return similarity(query, result) > 0.85;
}
