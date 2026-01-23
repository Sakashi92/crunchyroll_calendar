class AnimeMetadata {
  final int? id;
  final String? imageUrl;
  final String? description;
  final int? totalEpisodes;
  final String? siteUrl;
  final String? bannerImage;
  final DateTime? startDate;
  final String? nextEpisodeNumber;
  final DateTime? nextEpisodeDate;

  AnimeMetadata({
    this.id,
    this.imageUrl,
    this.description,
    this.totalEpisodes,
    this.siteUrl,
    this.bannerImage,
    this.startDate,
    this.nextEpisodeNumber,
    this.nextEpisodeDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'description': description,
      'totalEpisodes': totalEpisodes,
      'siteUrl': siteUrl,
      'bannerImage': bannerImage,
      'startDate': startDate?.toIso8601String(),
      'nextEpisodeNumber': nextEpisodeNumber,
      'nextEpisodeDate': nextEpisodeDate?.toIso8601String(),
    };
  }

  factory AnimeMetadata.fromJson(Map<String, dynamic> json) {
    DateTime? start;
    try {
      if (json['startDate'] != null) start = DateTime.parse(json['startDate']);
    } catch (_) {
      start = null;
    }
    DateTime? nextDate;
    try {
      if (json['nextEpisodeDate'] != null) nextDate = DateTime.parse(json['nextEpisodeDate']);
    } catch (_) {
      nextDate = null;
    }
    return AnimeMetadata(
      id: json['id'] is int ? json['id'] as int : (json['id'] == null ? null : int.tryParse(json['id'].toString())),
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      totalEpisodes: json['totalEpisodes'] is int ? json['totalEpisodes'] as int : (json['totalEpisodes'] == null ? null : int.tryParse(json['totalEpisodes'].toString())),
      siteUrl: json['siteUrl'] as String?,
      bannerImage: json['bannerImage'] as String?,
      startDate: start,
      nextEpisodeNumber: json['nextEpisodeNumber'] as String?,
      nextEpisodeDate: nextDate,
    );
  }
}
