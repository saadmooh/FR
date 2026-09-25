/// Normalizes a URL so the "same" link shared with tracking parameters or
/// minor formatting differences can be recognized as the same post.
///
/// Used for comparison only — the original URL is what gets stored and opened.
String normalizeUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    // Can't parse reliably: fall back to the trimmed original.
    return trimmed;
  }

  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();

  final queryParams = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    if (_trackingParams.contains(key.toLowerCase()) ||
        key.toLowerCase().startsWith('utm_')) {
      return;
    }
    queryParams[key] = value;
  });

  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  } else if (path == '/') {
    path = '';
  }

  // Sort params so the same query set in a different order compares equal.
  final sortedParams = queryParams.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  return Uri(
    scheme: scheme,
    userInfo: uri.userInfo,
    host: host,
    port: uri.hasPort ? uri.port : null,
    path: path.isEmpty ? null : path,
    query: sortedParams.isEmpty
        ? null
        : sortedParams
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
  ).toString();
}

/// True when both URLs point at the same resource after normalization.
bool sameUrl(String a, String b) => normalizeUrl(a) == normalizeUrl(b);

const Set<String> _trackingParams = {
  'fbclid',
  'gclid',
  'gclsrc',
  'dclid',
  'igshid',
  'igsh',
  'si',
  'si_id',
  'ref',
  'ref_src',
  'ref_url',
  'mc_cid',
  'mc_eid',
  'mbid',
  'cmpid',
  'ncid',
  'oc',
  'feature',
  'app',
  'app_id',
  'mibextid',
};
