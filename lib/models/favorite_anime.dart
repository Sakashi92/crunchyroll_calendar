/// Modell für ein Lieblings-Anime mit Metadaten für Benachrichtigungen
class FavoriteAnime {
  final int? id;
  final String title;
  final String? imageUrl;
  final String? seriesUrl;
  final DateTime addedDate;
  final DateTime? lastChecked;
  
  FavoriteAnime({
    this.id,
    required this.title,
    this.imageUrl,
    this.seriesUrl,
    required this.addedDate,
    this.lastChecked,
  });
  
  /// Konvertiert das Modell zu JSON für Speicherung
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'imageUrl': imageUrl,
      'seriesUrl': seriesUrl,
      'addedDate': addedDate.toIso8601String(),
      'lastChecked': lastChecked?.toIso8601String(),
    };
  }
  
  /// Erstellt ein FavoriteAnime-Objekt aus JSON
  factory FavoriteAnime.fromJson(Map<String, dynamic> json) {
    return FavoriteAnime(
      id: json['id'] as int?,
      title: json['title'] as String,
      imageUrl: json['imageUrl'] as String?,
      seriesUrl: json['seriesUrl'] as String?,
      addedDate: DateTime.parse(json['addedDate'] as String),
      lastChecked: json['lastChecked'] != null 
        ? DateTime.parse(json['lastChecked'] as String)
        : null,
    );
  }
  
  /// Erstellt eine Kopie mit optionalen Änderungen
  FavoriteAnime copyWith({
    int? id,
    String? title,
    String? imageUrl,
    String? seriesUrl,
    DateTime? addedDate,
    DateTime? lastChecked,
  }) {
    return FavoriteAnime(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      seriesUrl: seriesUrl ?? this.seriesUrl,
      addedDate: addedDate ?? this.addedDate,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
  
  @override
  String toString() => 'FavoriteAnime(id: $id, title: $title, lastChecked: $lastChecked)';
}
