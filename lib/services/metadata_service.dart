import 'package:metadata_fetch/metadata_fetch.dart';
import '../services/ai_service.dart';
import '../services/youtube_service.dart';

class MetadataResult {
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? ogTitle;
  final String? ogDescription;
  final String? ogImage;
  final String? siteName;
  final String? language;
  final String? canonicalUrl;

  final bool isPlaylist;
  final String? playlistId;
  final int? totalVideos;
  final int? totalDurationSeconds;

  MetadataResult({
    this.title,
    this.description,
    this.imageUrl,
    this.ogTitle,
    this.ogDescription,
    this.ogImage,
    this.siteName,
    this.language,
    this.canonicalUrl,
    this.isPlaylist = false,
    this.playlistId,
    this.totalVideos,
    this.totalDurationSeconds,
  });
}

class MetadataService {
  AIService? _aiService;
  YouTubeService? _youtubeService;

  void setAIService(AIService aiService) {
    _aiService = aiService;
  }

  void setYouTubeService(YouTubeService youtubeService) {
    _youtubeService = youtubeService;
  }

  Future<MetadataResult> fetchMetadata(String url) async {
    if (_youtubeService != null && _youtubeService!.isPlaylistUrl(url)) {
      try {
        final playlist = await _youtubeService!.getPlaylistInfo(url);
        if (playlist != null) {
          int? totalDuration;
          if (playlist.items.isNotEmpty) {
            totalDuration = playlist.items
                .where((v) => v.durationSeconds != null)
                .fold<int>(0, (sum, v) => sum + v.durationSeconds!);
          }

          final description = playlist.description.isNotEmpty
              ? '${playlist.description}\n\nChannel: ${playlist.channelName} | ${playlist.totalItems} videos${totalDuration != null ? ' | Total: ${_formatDuration(totalDuration)}' : ''}'
              : 'Channel: ${playlist.channelName} | ${playlist.totalItems} videos${totalDuration != null ? ' | Total: ${_formatDuration(totalDuration)}' : ''}';

          return MetadataResult(
            title: playlist.title,
            description: description,
            imageUrl: playlist.thumbnailUrl,
            ogTitle: playlist.title,
            ogDescription: description,
            ogImage: playlist.thumbnailUrl,
            siteName: 'YouTube',
            language: 'en',
            canonicalUrl: url,
            isPlaylist: true,
            playlistId: playlist.playlistId,
            totalVideos: playlist.totalItems,
            totalDurationSeconds: totalDuration,
          );
        }
      } catch (e) {
        // Fall through to regular metadata fetch
      }
    }
    try {
      final data = await MetadataFetch.extract(url);

      if (data != null && data.title != null && data.title!.isNotEmpty) {
        return MetadataResult(
          title: data.title,
          description: data.description,
          imageUrl: data.image,
          ogTitle: data.title,
          ogDescription: data.description,
          ogImage: data.image,
          siteName: data.url != null ? Uri.parse(data.url!).host : '',
          language: 'en',
          canonicalUrl: url,
        );
      }
    } catch (e) {
      // Fall through to AI fallback
    }

    if (_aiService == null) {
      throw Exception('AI Service not initialized and metadata_fetch failed');
    }

    final result = await _aiService!.fetchMetadata(url);

    return MetadataResult(
      title: result['title'],
      description: result['description'],
      imageUrl: result['og_image'],
      ogTitle: result['og_title'],
      ogDescription: result['og_description'],
      ogImage: result['og_image'],
      siteName: result['site_name'],
      language: result['language'],
      canonicalUrl: result['canonical_url'],
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
