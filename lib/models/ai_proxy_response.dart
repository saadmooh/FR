class AiProxyResponse {
  final String text;
  final String? model;

  const AiProxyResponse({required this.text, this.model});

  factory AiProxyResponse.fromJson(Map<String, dynamic> json) {
    return AiProxyResponse(
      text: json['text'] as String? ?? '',
      model: json['model'] as String?,
    );
  }
}

class AiProxyException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final bool isRetryable;

  const AiProxyException(
    this.statusCode,
    this.code,
    this.message, {
    this.isRetryable = false,
  });

  @override
  String toString() => message;
}
