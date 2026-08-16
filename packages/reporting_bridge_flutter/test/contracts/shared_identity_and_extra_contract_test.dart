import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  group('shared ReportIdentity', () {
    test('same identity is accepted', () {
      const identity = ReportIdentity(
        userId: '42',
        branchId: '01',
        systemUnit: 'MAIN',
      );
      final request = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
          identity: identity,
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          identity: identity,
        ),
      );

      expect(
        request.selectedTemplateCriteria.identity,
        request.templateSyncRequest.identity,
      );
    });

    test('empty identity is accepted', () {
      final request = ReportOpenRequest(
        seedData: const <String, dynamic>{'id': 1},
        selectedTemplateCriteria: SelectedTemplateCriteria(
          reportType: UrbReportType.salesInvoice,
        ),
        templateSyncRequest: TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
        ),
      );
      expect(request.selectedTemplateCriteria.identity.isEmpty, isTrue);
      expect(request.templateSyncRequest.identity.isEmpty, isTrue);
    });

    test('conflicting userId is rejected', () {
      expect(
        () => ReportOpenRequest(
          seedData: const <String, dynamic>{'id': 1},
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
            identity: const ReportIdentity(userId: 'A'),
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
            identity: const ReportIdentity(userId: 'B'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('conflicting branchId is rejected', () {
      expect(
        () => ReportOpenRequest(
          seedData: const <String, dynamic>{'id': 1},
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
            identity: const ReportIdentity(branchId: '01'),
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
            identity: const ReportIdentity(branchId: '02'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('conflicting systemUnit is rejected', () {
      expect(
        () => ReportOpenRequest(
          seedData: const <String, dynamic>{'id': 1},
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
            identity: const ReportIdentity(systemUnit: 'MAIN'),
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
            identity: const ReportIdentity(systemUnit: 'ALT'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TemplateSyncRequest.extra snapshot', () {
    test('caller mutation does not change request.extra', () {
      final nested = <String, Object?>{'b': 1};
      final sourceMap = <String, Object?>{'a': nested};
      final request = TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        extra: sourceMap,
      );

      sourceMap['a'] = <String, Object?>{'b': 99};
      nested['b'] = 99;
      sourceMap['c'] = 'added';

      expect(request.extra, <String, Object?>{
        'a': <String, Object?>{'b': 1},
      });
      expect(() => request.extra['x'] = 1, throwsUnsupportedError);
    });

    test('nested maps and lists are deeply immutable', () {
      final request = TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        extra: <String, Object?>{
          'nested': <String, Object?>{
            'b': 1,
            'deep': <String, Object?>{'c': 2},
          },
          'list': <Object?>[
            1,
            <String, Object?>{'d': 3},
          ],
        },
      );

      final fingerprintBefore = canonicalJsonFingerprint(request.extra);

      final nested = request.extra['nested']! as Map<String, Object?>;
      expect(() => nested['b'] = 999, throwsUnsupportedError);

      final deep = nested['deep']! as Map<String, Object?>;
      expect(() => deep['c'] = 999, throwsUnsupportedError);

      final list = request.extra['list']! as List<Object?>;
      expect(() => list.add(4), throwsUnsupportedError);
      expect(() => list.removeAt(0), throwsUnsupportedError);

      final listMap = list[1]! as Map<String, Object?>;
      expect(() => listMap['d'] = 999, throwsUnsupportedError);

      expect(canonicalJsonFingerprint(request.extra), fingerprintBefore);
      expect(request.extra['nested'], <String, Object?>{
        'b': 1,
        'deep': <String, Object?>{'c': 2},
      });
    });

    test('rejects non-JSON values', () {
      expect(
        () => TemplateSyncRequest(
          systemCode: UrbSystem.motakamelTransactions,
          extra: <String, Object?>{'bad': Object()},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Host external print reserved extra', () {
    for (final key in reservedHostExternalPrintExtraKeys) {
      test('rejects reserved key $key', () {
        expect(
          () => HostExternalPrintRequest(
            extra: <String, Object?>{key: 'override'},
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('allows non-reserved Host extra', () {
      final request = HostExternalPrintRequest(
        extra: <String, Object?>{'copyCount': 2, 'channel': 'shop'},
      );
      expect(request.extra, <String, Object?>{
        'copyCount': 2,
        'channel': 'shop',
      });
    });
  });
}
