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

  test('invalid HTTPS image certificate acceptance defaults to true', () {
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://app.skeyerp.com/img.png'),
      ),
      isTrue,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://another-public-host.org/image.jpg'),
      ),
      isTrue,
    );
  });

  test('false flag restores HTTPS certificate verification', () {
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://app.skeyerp.com/img.png'),
        allowInvalidHttpsCertificates: false,
      ),
      isFalse,
    );
    expect(
      allowUntrustedImageCertificate(
        Uri.parse('https://another-public-host.org/image.jpg'),
        allowInvalidHttpsCertificates: false,
      ),
      isFalse,
    );
  });

  test(
    'invalid certificate flag is never applicable to HTTP or private URLs',
    () {
      expect(
        allowUntrustedImageCertificate(
          Uri.parse('http://images.example.org/a.png'),
        ),
        isFalse,
      );
      expect(
        allowUntrustedImageCertificate(Uri.parse('https://127.0.0.1/a.png')),
        isFalse,
      );
    },
  );
}
