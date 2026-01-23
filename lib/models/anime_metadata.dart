class AnimeMetadata {
  final String? imageUrl;
  final String? description;
  final int? totalEpisodes;
  final String? siteUrl;
  final String? bannerImage;
  final DateTime? startDate;

  AnimeMetadata({
    this.imageUrl,
    this.description,
    this.totalEpisodes,
    this.siteUrl,
    this.bannerImage,
    this.startDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'imageUrl': imageUrl,
      'description': description,
      'totalEpisodes': totalEpisodes,
      'siteUrl': siteUrl,
      'bannerImage': bannerImage,
      'startDate': startDate?.toIso8601String(),
    };
  }

  factory AnimeMetadata.fromJson(Map<String, dynamic> json) {
    DateTime? start;
    try {
      if (json['startDate'] != null) start = DateTime.parse(json['startDate']);
    } catch (_) {
      start = null;
    }
    return AnimeMetadata(
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      totalEpisodes: json['totalEpisodes'] is int ? json['totalEpisodes'] as int : (json['totalEpisodes'] == null ? null : int.tryParse(json['totalEpisodes'].toString())),
      siteUrl: json['siteUrl'] as String?,
      bannerImage: json['bannerImage'] as String?,
      startDate: start,
    );
  }
}
