import 'package:reporting_bridge/src/bridge_image_proxy_fetch.dart';
import 'package:test/test.dart';

void main() {
  test('HTTP public image URLs are allowed without a TLS certificate', () {
    expect(
      isAllowedBridgeImageUrl(Uri.parse('http://images.example.org/logo.png')),
      isTrue,
    );
    expect(
      isAllowedBridgeImageUrl(Uri.parse('http://127.0.0.1/admin.png')),
      isFalse,
    );
  });

  test('untrusted HTTPS image certificates require exact host opt-in', () {
    const hosts = <String>{'app.skeyerp.com'};
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://app.skeyerp.com/img.png'),
        hosts,
      ),
      isTrue,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://other.skeyerp.com/img.png'),
        hosts,
      ),
      isFalse,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('http://app.skeyerp.com/img.png'),
        hosts,
      ),
      isFalse,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://app.skeyerp.com/img.png'),
        const <String>{},
      ),
      isFalse,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://127.0.0.1/img.png'),
        hosts,
      ),
      isFalse,
    );
  });
}
