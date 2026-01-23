import 'dart:core';

/// Utilities for normalizing titles and computing simple similarity.

String normalizeTitle(String? s) {
  if (s == null) return '';
  var t = s.trim().toLowerCase();
  // remove HTML entities commonly found
  t = t.replaceAll('&amp;', '&');
  // replace common diacritics
  const replacements = {
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'é': 'e', 'è': 'e', 'ê': 'e', 'á': 'a', 'à': 'a', 'â': 'a',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'í': 'i', 'ì': 'i', 'î': 'i',
    'ñ': 'n', 'ç': 'c'
  };
  replacements.forEach((k, v) { t = t.replaceAll(k, v); });
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
  for (var i = 0; i <= n; i++) d[i][0] = i;
  for (var j = 0; j <= m; j++) d[0][j] = j;
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
      d[i][j] = [
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost
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
