import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('filename is unique, filesystem-safe, and keeps the template name', () {
    final first = buildPresenterPdfFilename(
      templateName: 'Invoice: Retail / A',
      timestamp: DateTime(2026, 7, 26, 12, 3, 4, 5),
    );
    final second = buildPresenterPdfFilename(
      templateName: 'Invoice: Retail / A',
      timestamp: DateTime(2026, 7, 26, 12, 3, 4, 6),
    );

    expect(first, 'Invoice_Retail_A_20260726_120304005.pdf');
    expect(second, isNot(first));
    expect(first, isNot(contains(':')));
    expect(first, isNot(contains('/')));
  });

  test('cache reuses one export within a session', () async {
    final cache = PresenterPdfExportCache()..bindSession('session-a');
    var loads = 0;

    Future<PresenterCachedPdf> load() async {
      loads += 1;
      return PresenterCachedPdf(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        filename: 'report.pdf',
      );
    }

    final first = await cache.resolve(load);
    final second = await cache.resolve(load);

    expect(identical(first, second), isTrue);
    expect(loads, 1);
  });

  test(
    'session replacement cannot repopulate cache from an old export',
    () async {
      final cache = PresenterPdfExportCache()..bindSession('session-a');
      final oldCompletion = Completer<PresenterCachedPdf>();
      final oldFuture = cache.resolve(() => oldCompletion.future);

      cache.bindSession('session-b');
      oldCompletion.complete(
        PresenterCachedPdf(
          bytes: Uint8List.fromList(<int>[1]),
          filename: 'old.pdf',
        ),
      );
      await oldFuture;

      var newLoads = 0;
      final current = await cache.resolve(() async {
        newLoads += 1;
        return PresenterCachedPdf(
          bytes: Uint8List.fromList(<int>[2]),
          filename: 'new.pdf',
        );
      });

      expect(current.filename, 'new.pdf');
      expect(newLoads, 1);
    },
  );
}
