import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_failure.dart';
import 'package:reporting_bridge_flutter/src/localization/report_flow_strings.dart';
import 'package:reporting_bridge_flutter/src/ui/report_failure_recovery.dart';

void main() {
  test(
    'style recovery shows approved Arabic details label and honest host guidance',
    () {
      const ar = ReportFlowStrings(Locale('ar'));
      const en = ReportFlowStrings(Locale('en'));
      expect(ar.technicalDetails, 'تفاصيل تقنية');
      expect(en.technicalDetails, 'Technical details');
      expect(
        ar.recoveryNextStep(ReportRecoveryKind.invalidStyle),
        contains('مصدر التقرير'),
      );
      expect(
        en.recoveryNextStep(ReportRecoveryKind.invalidStyle),
        contains('report source'),
      );
      expect(ar.settings, 'إعدادات التقرير');
    },
  );

  group('classifyReportRecovery', () {
    test('classifies trusted color and font token paths as invalid style', () {
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            technicalPath: 'styleTokens.color.primary',
          ),
        ),
        ReportRecoveryKind.invalidStyle,
      );
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.renderFailed,
            technicalPath: 'styleTokens.font.heading',
          ),
        ),
        ReportRecoveryKind.invalidStyle,
      );
    });

    test(
      'does not infer invalid style from a diagnostic or unrelated path',
      () {
        expect(
          classifyReportRecovery(
            const ReportFlowFailure(
              code: ReportFlowFailureCode.renderFailed,
              diagnostic: 'Invalid styleTokens.color.primary value',
            ),
          ),
          ReportRecoveryKind.generic,
        );
        expect(
          classifyReportRecovery(
            const ReportFlowFailure(
              code: ReportFlowFailureCode.renderFailed,
              technicalPath: 'elements[1].style.color',
            ),
          ),
          ReportRecoveryKind.generic,
        );
      },
    );

    test('routes template and Presenter resource failures separately', () {
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.templateSyncFailed,
          ),
        ),
        ReportRecoveryKind.templates,
      );
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.noCompatibleTemplates,
          ),
        ),
        ReportRecoveryKind.templates,
      );
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.presenterIncompatible,
          ),
        ),
        ReportRecoveryKind.presenterResources,
      );
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(
            code: ReportFlowFailureCode.presenterSyncFailed,
          ),
        ),
        ReportRecoveryKind.presenterResources,
      );
    });

    test('keeps non-style rendering failures generic', () {
      expect(
        classifyReportRecovery(
          const ReportFlowFailure(code: ReportFlowFailureCode.renderFailed),
        ),
        ReportRecoveryKind.generic,
      );
    });
  });
}
