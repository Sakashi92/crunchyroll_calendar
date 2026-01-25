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
  final bool? hasCrunchyroll;
  final String? status;

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
    this.hasCrunchyroll,
    this.status,
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
      'hasCrunchyroll': hasCrunchyroll,
      'status': status,
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
      if (json['nextEpisodeDate'] != null) {
        nextDate = DateTime.parse(json['nextEpisodeDate']);
      }
    } catch (_) {
      nextDate = null;
    }
    return AnimeMetadata(
      id: json['id'] is int
          ? json['id'] as int
          : (json['id'] == null ? null : int.tryParse(json['id'].toString())),
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      totalEpisodes: json['totalEpisodes'] is int
          ? json['totalEpisodes'] as int
          : (json['totalEpisodes'] == null
                ? null
                : int.tryParse(json['totalEpisodes'].toString())),
      siteUrl: json['siteUrl'] as String?,
      bannerImage: json['bannerImage'] as String?,
      startDate: start,
      nextEpisodeNumber: json['nextEpisodeNumber'] as String?,
      nextEpisodeDate: nextDate,
      hasCrunchyroll: json['hasCrunchyroll'] as bool?,
      status: json['status'] as String?,
    );
  }

  AnimeMetadata copyWith({
    int? id,
    String? imageUrl,
    String? description,
    int? totalEpisodes,
    String? siteUrl,
    String? bannerImage,
    DateTime? startDate,
    String? nextEpisodeNumber,
    DateTime? nextEpisodeDate,
    bool? hasCrunchyroll,
    String? status,
  }) {
    return AnimeMetadata(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      siteUrl: siteUrl ?? this.siteUrl,
      bannerImage: bannerImage ?? this.bannerImage,
      startDate: startDate ?? this.startDate,
      nextEpisodeNumber: nextEpisodeNumber ?? this.nextEpisodeNumber,
      nextEpisodeDate: nextEpisodeDate ?? this.nextEpisodeDate,
      hasCrunchyroll: hasCrunchyroll ?? this.hasCrunchyroll,
      status: status ?? this.status,
    );
  }
}
