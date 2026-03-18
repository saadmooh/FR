import 'package:metadata_fetch/metadata_fetch.dart';
import '../services/ai_service.dart';

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
  AIService? _aiService;

  void setAIService(AIService aiService) {
    _aiService = aiService;
  }

  Future<MetadataResult> fetchMetadata(String url) async {
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
}
