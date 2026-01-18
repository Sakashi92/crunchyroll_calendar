/// Modell für eine Benachrichtigungs-Historie
/// Speichert alle gesendeten Benachrichtigungen zur Vermeidung von Duplikaten
class NotificationLog {
  final int? id;
  final int? favoriteId;
  final String favoriteTitle;
  final String releaseTitle;
  final String? episodeNumber;
  final DateTime notifyTime;
  final bool isShown;
  
  NotificationLog({
    this.id,
    this.favoriteId,
    required this.favoriteTitle,
    required this.releaseTitle,
    this.episodeNumber,
    required this.notifyTime,
    this.isShown = false,
  });
  
  /// Konvertiert das Modell zu JSON für Speicherung
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'favoriteId': favoriteId,
      'favoriteTitle': favoriteTitle,
      'releaseTitle': releaseTitle,
      'episodeNumber': episodeNumber,
      'notifyTime': notifyTime.toIso8601String(),
      'isShown': isShown ? 1 : 0,
    };
  }
  
  /// Erstellt ein NotificationLog-Objekt aus JSON
  factory NotificationLog.fromJson(Map<String, dynamic> json) {
    return NotificationLog(
      id: json['id'] as int?,
      favoriteId: json['favoriteId'] as int?,
      favoriteTitle: json['favoriteTitle'] as String,
      releaseTitle: json['releaseTitle'] as String,
      episodeNumber: json['episodeNumber'] as String?,
      notifyTime: DateTime.parse(json['notifyTime'] as String),
      isShown: (json['isShown'] as int?) == 1,
    );
  }
  
  /// Erstellt eine Kopie mit optionalen Änderungen
  NotificationLog copyWith({
    int? id,
    int? favoriteId,
    String? favoriteTitle,
    String? releaseTitle,
    String? episodeNumber,
    DateTime? notifyTime,
    bool? isShown,
  }) {
    return NotificationLog(
      id: id ?? this.id,
      favoriteId: favoriteId ?? this.favoriteId,
      favoriteTitle: favoriteTitle ?? this.favoriteTitle,
      releaseTitle: releaseTitle ?? this.releaseTitle,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      notifyTime: notifyTime ?? this.notifyTime,
      isShown: isShown ?? this.isShown,
    );
  }
  
  @override
  String toString() => 'NotificationLog('
      'favoriteTitle: $favoriteTitle, '
      'releaseTitle: $releaseTitle, '
      'episodeNumber: $episodeNumber, '
      'notifyTime: $notifyTime'
      ')';
}
