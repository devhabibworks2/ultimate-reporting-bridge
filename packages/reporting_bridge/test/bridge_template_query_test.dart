import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateQueryRequest', () {
    test('serializes complete request and normalized identity', () {
      final request = TemplateQueryRequest(
        systemCode: ' MOTAKAMEL_TRANSACTIONS ',
        identity: BridgeIdentityContext(
          branchId: ' branch_01 ',
          userId: ' user_123 ',
          systemUnit: ' sales ',
        ),
        filter: TemplateSyncFilter(
          reportTypes: const <String>['SALES_INVOICE', 'payment_voucher'],
          layouts: const <String>['Pages', 'Thermal'],
          sizes: const <String>['A4', '80mm'],
          languages: const <String>['ar', 'en'],
          units: const <String>['mm'],
          orientations: const <String>['portrait'],
        ),
        extra: const <String, Object?>{
          'transactionType': 'sales',
          'flags': <Object?>[true, 3],
        },
      );

      expect(request.systemCode, 'motakamel_transactions');
      expect(request.identity.branchId, 'branch_01');
      expect(request.identity.userId, 'user_123');
      expect(request.identity.systemUnit, 'sales');
      expect(request.toJson(), <String, dynamic>{
        'systemCode': 'motakamel_transactions',
        'userId': 'user_123',
        'systemUnit': 'sales',
        'branchId': 'branch_01',
        'filter': <String, dynamic>{
          'reportTypes': <String>['sales_invoice', 'payment_voucher'],
          'layouts': <String>['Pages', 'Thermal'],
          'sizes': <String>['A4', '80mm'],
          'languages': <String>['ar', 'en'],
          'units': <String>['mm'],
          'orientations': <String>['portrait'],
        },
        'extra': <String, Object?>{
          'transactionType': 'sales',
          'flags': <Object?>[true, 3],
        },
      });
    });

    test('defaults every missing filter to all', () {
      final request = TemplateQueryRequest(systemCode: 'erp');

      expect(request.filter.toJson(), <String, dynamic>{
        'reportTypes': <String>['all'],
        'layouts': <String>['all'],
        'sizes': <String>['all'],
        'languages': <String>['all'],
        'units': <String>['all'],
        'orientations': <String>['all'],
      });
      expect(request.toJson().containsKey('userId'), isFalse);
      expect(request.toJson().containsKey('branchId'), isFalse);
      expect(request.toJson().containsKey('systemUnit'), isFalse);
    });

    test('rejects all combined with another filter value', () {
      expect(
        () => TemplateSyncFilter(layouts: const <String>['all', 'Pages']),
        throwsArgumentError,
      );
    });

    test('keeps unknown filter values open', () {
      final filter = TemplateSyncFilter(
        reportTypes: const <String>['future_report_type'],
      );

      expect(filter.reportTypes, const <String>['future_report_type']);
    });

    test('filter fingerprint is stable across OR-value order', () {
      final first = TemplateSyncFilter(
        reportTypes: const <String>['sales_invoice', 'payment_voucher'],
        languages: const <String>['ar', 'en'],
      );
      final second = TemplateSyncFilter(
        reportTypes: const <String>['payment_voucher', 'sales_invoice'],
        languages: const <String>['en', 'ar'],
      );

      expect(first.fingerprint, second.fingerprint);
      expect(first, second);
    });

    test('extra fingerprint canonicalizes maps but preserves list order', () {
      final first = TemplateQueryRequest(
        systemCode: 'erp',
        extra: const <String, Object?>{
          'outer': <String, Object?>{'b': 2, 'a': 1},
          'list': <Object?>['a', 'b'],
        },
      );
      final reorderedMap = TemplateQueryRequest(
        systemCode: 'erp',
        extra: const <String, Object?>{
          'list': <Object?>['a', 'b'],
          'outer': <String, Object?>{'a': 1, 'b': 2},
        },
      );
      final reorderedList = TemplateQueryRequest(
        systemCode: 'erp',
        extra: const <String, Object?>{
          'outer': <String, Object?>{'a': 1, 'b': 2},
          'list': <Object?>['b', 'a'],
        },
      );

      expect(first.extraFingerprint, reorderedMap.extraFingerprint);
      expect(first.extraFingerprint, isNot(reorderedList.extraFingerprint));
    });

    test('rejects extra maps larger than the contract limit', () {
      final largeValue = List<String>.filled(
        kTemplateQueryExtraMaximumBytes,
        'x',
      ).join();

      expect(
        () => TemplateQueryRequest(
          systemCode: 'motakamel_transactions',
          extra: <String, Object?>{'value': largeValue},
        ),
        throwsArgumentError,
      );
    });
  });
}
