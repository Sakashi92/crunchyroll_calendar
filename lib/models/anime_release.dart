class AnimeRelease {
  final String title;
  final String episodeNumber;
  final String episodeTitle;
  final DateTime releaseTime;
  String? imageUrl; // Nicht final, damit AniList-Bilder nachgeladen werden können
  String? description; // Plot/Beschreibung des Anime
  final String seriesUrl;
  final String episodeUrl;
  final bool isPremiere;

  AnimeRelease({
    required this.title,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.releaseTime,
    this.imageUrl,
    this.description,
    required this.seriesUrl,
    required this.episodeUrl,
    this.isPremiere = false,
  });

  String get episodeInfo => 'Folge $episodeNumber';
  
  String get timeString {
    final hour = releaseTime.hour.toString().padLeft(2, '0');
    final minute = releaseTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  factory AnimeRelease.fromJson(Map<String, dynamic> json) {
    return AnimeRelease(
      title: json['title'] as String,
      episodeNumber: json['episodeNumber'] as String,
      episodeTitle: json['episodeTitle'] as String,
      releaseTime: DateTime.parse(json['releaseTime'] as String),
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      seriesUrl: json['seriesUrl'] as String,
      episodeUrl: json['episodeUrl'] as String,
      isPremiere: json['isPremiere'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'releaseTime': releaseTime.toIso8601String(),
      'imageUrl': imageUrl,
      'description': description,
      'seriesUrl': seriesUrl,
      'episodeUrl': episodeUrl,
      'isPremiere': isPremiere,
    };
  }
}
