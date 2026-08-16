import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test(
    'Presenter render payload preserves allow-listed structured details',
    () {
      final failure =
          ReportFlowFailure.presenterRenderPayload(<String, dynamic>{
            'category': 'document',
            'code': 'invalidElement',
            'path': r'elements[2].content',
            'message': 'Text content is invalid.',
            'source': 'runtimeFile',
            'sessionId': 'session-1',
            'ignoredSecret': 'must-not-be-preserved',
          });

      expect(failure.code, ReportFlowFailureCode.renderFailed);
      expect(failure.diagnostic, 'Text content is invalid.');
      expect(failure.technicalCategory, 'document');
      expect(failure.technicalCode, 'invalidElement');
      expect(failure.technicalPath, r'elements[2].content');
      expect(failure.details, <String, Object?>{
        'source': 'runtimeFile',
        'sessionId': 'session-1',
      });
      expect(failure.details.containsKey('ignoredSecret'), isFalse);
      expect(failure.hasTechnicalDetails, isTrue);
    },
  );
}
