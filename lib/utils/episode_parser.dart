// Lightweight episode number parser utilities
int? parseEpisodeNumber(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();

  // Try SxxExx patterns first
  final seMatch = RegExp(r'[sS]\d{1,2}[eE](\d{1,4})').firstMatch(s);
  if (seMatch != null) {
    return int.tryParse(seMatch.group(1)!);
  }

  // Try common words: Ep, Ep., Episode, Folge
  final wordMatch = RegExp(r'(?:ep(?:isode)?|folg(?:e)?|ep\.?)[^0-9]*(\d{1,4})', caseSensitive: false).firstMatch(s);
  if (wordMatch != null) return int.tryParse(wordMatch.group(1)!);

  // Fallback: find all integer sequences and return the largest
  final all = RegExp(r'(\d{1,4})').allMatches(s).map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
  if (all.isEmpty) return null;
  return all.reduce((a, b) => a > b ? a : b);
}

// Normalize episode string for display / hashing: prefer original if numeric parse fails
String normalizeEpisodeString(String? raw) {
  if (raw == null) return '';
  final parsed = parseEpisodeNumber(raw);
  return parsed != null ? parsed.toString() : raw.trim();
}
