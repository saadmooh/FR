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
  });
}

class MetadataService {
  Future<MetadataResult> fetchMetadata(String url) async {
    try {
      final uri = Uri.parse(url);
      return _fallbackMetadata(url, uri);
    } catch (e) {
      return _fallbackMetadata(url, null);
    }
  }

  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        return pathSegments.last
            .replaceAll(RegExp(r'[_-]'), ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
      }
      return uri.host;
    } catch (e) {
      return 'Unknown Post';
    }
  }

  MetadataResult _fallbackMetadata(String url, Uri? uri) {
    final title = uri != null ? _extractTitleFromUrl(url) : 'Unknown Post';
    return MetadataResult(
      title: title,
      description: '',
      imageUrl: null,
      ogTitle: title,
      ogDescription: '',
      ogImage: '',
      siteName: uri?.host ?? '',
      language: 'en',
      canonicalUrl: url,
    );
  }
}
