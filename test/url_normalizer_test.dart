import 'package:flutter_test/flutter_test.dart';
import 'package:smart_pocket/core/url_normalizer.dart';

void main() {
  group('normalizeUrl', () {
    test('strips tracking params but keeps real ones', () {
      expect(
        normalizeUrl('https://Example.com/Post?utm_source=x&utm_medium=y&id=5'),
        'https://example.com/Post?id=5',
      );
      expect(
        normalizeUrl('https://a.com/p?fbclid=abc&gclid=def&v=1'),
        'https://a.com/p?v=1',
      );
      expect(
        normalizeUrl('https://youtu.be/abc?si=SHARE_TOKEN'),
        'https://youtu.be/abc',
      );
    });

    test('lowercases scheme and host', () {
      expect(
        normalizeUrl('HTTPS://YouTube.COM/watch?v=abc'),
        'https://youtube.com/watch?v=abc',
      );
    });

    test('drops trailing slash and fragment', () {
      expect(normalizeUrl('https://a.com/path/'), 'https://a.com/path');
      expect(normalizeUrl('https://a.com/'), 'https://a.com');
      expect(normalizeUrl('https://a.com/p#t=30'), 'https://a.com/p');
    });

    test('order of query params does not matter', () {
      expect(
        sameUrl('https://a.com/p?b=2&a=1', 'https://a.com/p?a=1&b=2'),
        isTrue,
      );
    });

    test('falls back to the trimmed original when unparseable', () {
      expect(normalizeUrl('  not a url  '), 'not a url');
      expect(normalizeUrl(''), '');
    });

    test('same link with different tracking params is the same post', () {
      expect(
        sameUrl(
          'https://www.instagram.com/p/XYZ/?igshid=token#reel',
          'https://www.instagram.com/p/XYZ/',
        ),
        isTrue,
      );
      expect(sameUrl('https://a.com/one', 'https://a.com/two'), isFalse);
    });
  });
}
