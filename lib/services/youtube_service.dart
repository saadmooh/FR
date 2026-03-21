import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubePlaylist {
  final String playlistId;
  final String title;
  final String description;
  final String? thumbnailUrl;
  final String channelName;
  final String channelUrl;
  final int totalItems;
  final List<YouTubeVideoItem> items;

  YouTubePlaylist({
    required this.playlistId,
    required this.title,
    required this.description,
    this.thumbnailUrl,
    required this.channelName,
    required this.channelUrl,
    required this.totalItems,
    required this.items,
  });

  factory YouTubePlaylist.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] ?? {};
    final contentDetails = json['contentDetails'] ?? {};
    final channelInfo = json['channelInfo'] ?? {};

    return YouTubePlaylist(
      playlistId: json['id'] ?? '',
      title: snippet['title'] ?? '',
      description: snippet['description'] ?? '',
      thumbnailUrl:
          snippet['thumbnails']?['high']?['url'] ??
          snippet['thumbnails']?['medium']?['url'],
      channelName: snippet['channelTitle'] ?? '',
      channelUrl: channelInfo['channelUrl'] ?? '',
      totalItems:
          int.tryParse(contentDetails['itemCount']?.toString() ?? '0') ?? 0,
      items: [],
    );
  }
}

class YouTubeVideoItem {
  final String videoId;
  final String title;
  final String description;
  final String? thumbnailUrl;
  final int position;
  final int? durationSeconds;

  YouTubeVideoItem({
    required this.videoId,
    required this.title,
    required this.description,
    this.thumbnailUrl,
    required this.position,
    this.durationSeconds,
  });

  factory YouTubeVideoItem.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] ?? {};
    final thumbnails = snippet['thumbnails'] ?? {};

    return YouTubeVideoItem(
      videoId: snippet['resourceId']?['videoId'] ?? '',
      title: snippet['title'] ?? '',
      description: snippet['description'] ?? '',
      thumbnailUrl:
          thumbnails['high']?['url'] ??
          thumbnails['medium']?['url'] ??
          thumbnails['default']?['url'],
      position: int.tryParse(snippet['position']?.toString() ?? '0') ?? 0,
    );
  }
}

class YouTubeService {
  static const String _watchLaterId = 'WL';

  String? extractActualUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('google.com') && uri.path.contains('/url')) {
        final qParam = uri.queryParameters['q'];
        if (qParam != null && qParam.isNotEmpty) {
          return qParam;
        }
      }
      return url;
    } catch (e) {
      return url;
    }
  }

  bool isPlaylistUrl(String url) {
    url = extractActualUrl(url) ?? url;
    try {
      final uri = Uri.parse(url);
      final listParam = uri.queryParameters['list'];
      if (listParam == null || listParam.isEmpty) {
        return false;
      }
      if (listParam == _watchLaterId) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  String? extractPlaylistId(String url) {
    url = extractActualUrl(url) ?? url;
    try {
      final uri = Uri.parse(url);
      final listParam = uri.queryParameters['list'];
      if (listParam != null &&
          listParam.isNotEmpty &&
          listParam != _watchLaterId) {
        return listParam;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String? extractVideoId(String url) {
    try {
      final patterns = [
        RegExp(
          r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([a-zA-Z0-9_-]{11})',
        ),
        RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
        RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(url);
        if (match != null && match.group(1) != null) {
          return match.group(1);
        }
      }

      final uri = Uri.tryParse(url);
      if (uri != null) {
        final vParam = uri.queryParameters['v'];
        if (vParam != null && vParam.length == 11) {
          return vParam;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<YouTubePlaylist?> getPlaylistInfo(String playlistUrl) async {
    playlistUrl = extractActualUrl(playlistUrl) ?? playlistUrl;
    final yt = YoutubeExplode();
    try {
      final playlist = await yt.playlists.get(playlistUrl);

      final videos = await yt.playlists.getVideos(playlist.id).toList();

      return YouTubePlaylist(
        playlistId: playlist.id.value,
        title: playlist.title,
        description: playlist.description,
        thumbnailUrl: playlist.thumbnails.highResUrl,
        channelName: playlist.author,
        channelUrl: playlist.url,
        totalItems: videos.length,
        items: videos.asMap().entries.map((entry) {
          final video = entry.value;
          return YouTubeVideoItem(
            videoId: video.id.value,
            title: video.title,
            description: video.description,
            thumbnailUrl: video.thumbnails.highResUrl,
            position: entry.key,
            durationSeconds: video.duration?.inSeconds,
          );
        }).toList(),
      );
    } catch (e) {
      return null;
    } finally {
      yt.close();
    }
  }

  Future<YouTubePlaylist?> getPlaylistDetails(
    String playlistId,
    String apiKey,
  ) async {
    return getPlaylistInfo('https://www.youtube.com/playlist?list=$playlistId');
  }

  String? getFirstVideoUrl(YouTubePlaylist playlist) {
    if (playlist.items.isEmpty) return null;
    return 'https://www.youtube.com/watch?v=${playlist.items.first.videoId}&list=${playlist.playlistId}';
  }

  String? getNextVideoUrl(YouTubePlaylist playlist, int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= playlist.items.length) return null;
    return 'https://www.youtube.com/watch?v=${playlist.items[nextIndex].videoId}&list=${playlist.playlistId}';
  }

  String? getPreviousVideoUrl(YouTubePlaylist playlist, int currentIndex) {
    final prevIndex = currentIndex - 1;
    if (prevIndex < 0) return null;
    return 'https://www.youtube.com/watch?v=${playlist.items[prevIndex].videoId}&list=${playlist.playlistId}';
  }

  Future<List<YouTubeVideoItem>?> getPlaylistItems(
    String playlistId,
    String apiKey, {
    int maxResults = 50,
    String? pageToken,
  }) async {
    final playlist = await getPlaylistInfo(
      'https://www.youtube.com/playlist?list=$playlistId',
    );
    if (playlist == null) return null;
    return playlist.items;
  }

  Future<List<YouTubeVideoItem>?> getAllPlaylistItems(
    String playlistId,
    String apiKey,
  ) async {
    final playlist = await getPlaylistInfo(
      'https://www.youtube.com/playlist?list=$playlistId',
    );
    if (playlist == null) return null;
    return playlist.items;
  }
}
