import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const List<int> _magic = <int>[85, 82, 66, 84, 1]; // URBT + format version.

final class NativeThumbnailCrypto {
  NativeThumbnailCrypto({AesGcm? algorithm})
    : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;

  Future<Uint8List> encrypt({
    required Uint8List keyBytes,
    required List<int> clearBytes,
    required String associatedIdentity,
  }) async {
    _validateKey(keyBytes);
    final nonceBytes = List<int>.generate(
      12,
      (_) => Random.secure().nextInt(256),
    );
    final box = await _algorithm.encrypt(
      clearBytes,
      secretKey: SecretKey(keyBytes),
      nonce: nonceBytes,
      aad: utf8.encode(associatedIdentity),
    );
    return Uint8List.fromList(<int>[
      ..._magic,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  Future<Uint8List> decrypt({
    required Uint8List keyBytes,
    required Uint8List encryptedBytes,
    required String associatedIdentity,
  }) async {
    _validateKey(keyBytes);
    if (encryptedBytes.length < _magic.length + 12 + 16 ||
        !_hasMagic(encryptedBytes)) {
      throw const FormatException('Invalid encrypted thumbnail envelope.');
    }
    final nonceStart = _magic.length;
    final macStart = nonceStart + 12;
    final ciphertextStart = macStart + 16;
    final box = SecretBox(
      encryptedBytes.sublist(ciphertextStart),
      nonce: encryptedBytes.sublist(nonceStart, macStart),
      mac: Mac(encryptedBytes.sublist(macStart, ciphertextStart)),
    );
    return Uint8List.fromList(
      await _algorithm.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode(associatedIdentity),
      ),
    );
  }

  static bool _hasMagic(List<int> bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static void _validateKey(List<int> bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'keyBytes',
        'AES-256 requires 32 bytes.',
      );
    }
  }
}
