/// Modell für ein Lieblings-Anime mit Metadaten für Benachrichtigungen
class FavoriteAnime {
  final int? id;
  final String title;
  final String? imageUrl;
  final String? seriesUrl;
  final DateTime addedDate;
  final DateTime? lastChecked;
  final bool notificationsEnabled;
  
  FavoriteAnime({
    this.id,
    required this.title,
    this.imageUrl,
    this.seriesUrl,
    required this.addedDate,
    this.lastChecked,
    this.notificationsEnabled = false,
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
      'notificationsEnabled': notificationsEnabled,
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
      notificationsEnabled: _parseNotificationFlag(json['notificationsEnabled']),
    );
  }

  /// Wandelt unterschiedliche JSON-Repräsentationen der Flagge in ein bool um
  static bool _parseNotificationFlag(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }
  
  /// Erstellt eine Kopie mit optionalen Änderungen
  FavoriteAnime copyWith({
    int? id,
    String? title,
    String? imageUrl,
    String? seriesUrl,
    DateTime? addedDate,
    DateTime? lastChecked,
    bool? notificationsEnabled,
  }) {
    return FavoriteAnime(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      seriesUrl: seriesUrl ?? this.seriesUrl,
      addedDate: addedDate ?? this.addedDate,
      lastChecked: lastChecked ?? this.lastChecked,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }
  
  @override
  String toString() => 'FavoriteAnime(id: $id, title: $title, lastChecked: $lastChecked, notificationsEnabled: $notificationsEnabled)';
}
