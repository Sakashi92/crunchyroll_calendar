String stripCrunchyrollSuffixes(String title) {
  var t = title;
  // Remove Season/Staffel suffixes first (not in parentheses)
  t = t.replaceAll(RegExp(r'\s*Season\s+\d+', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s*Staffel\s+\d+', caseSensitive: false), '');
  // Remove ALL parenthesized content: (Simulcast), (Dub), (Spanish), (OmU), etc.
  t = t.replaceAll(RegExp(r'\s*\([^)]+\)'), '');
  return t.trim();
}

void main() {
  final titles = [
    'Gnosia',
    'Gnosia Staffel 1',
    'Gnosia Staffel 1 (Spanish)',
    'Gnosia (French)',
    'Fire Force',
    'Fire Force Staffel 3',
    'Fire Force Staffel 3 (English Dub)',
    'MF Ghost (Latin Spanish)',
  ];

  for (final title in titles) {
    final stripped = stripCrunchyrollSuffixes(title);
    print('"$title" -> "$stripped"');
  }
}
