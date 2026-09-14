import 'package:flutter/widgets.dart';

import '../contracts/report_contract_values.dart';
import '../flow/report_flow_failure.dart';
import '../flow/report_flow_state.dart';
import '../flow/urb_identifiers.dart';

class ReportFlowStrings {
  const ReportFlowStrings(this.locale);

  final Locale locale;
  bool get arabic => locale.languageCode == 'ar';

  static ReportFlowStrings of(BuildContext context, {String? override}) {
    final locale = override == null
        ? Localizations.localeOf(context)
        : Locale(override == 'ar' ? 'ar' : 'en');
    return ReportFlowStrings(locale);
  }

  String get title => arabic ? 'إعداد التقارير' : 'Report setup';
  String get preparation => arabic ? 'تحديث التقارير' : 'Preparation';
  String get preparationDescription => arabic
      ? 'تحقق من القوالب ونسخة المستعرض قبل اختيار القالب.'
      : 'Check templates and Presenter resources before selecting a template.';
  String get stepOneOfTwo => arabic ? 'الخطوة ١ من ٢' : 'Step 1 of 2';
  String get stepTwoOfTwo => arabic ? 'الخطوة ٢ من ٢' : 'Step 2 of 2';
  String get selectTemplate => arabic ? 'اختر القالب' : 'Select template';
  String get currentTemplate => arabic ? 'القالب الحالي' : 'Current template';
  String get templatesResource => arabic ? 'القوالب' : 'templates';
  String get presenterResource => arabic ? 'مستعرض التقارير' : 'Presenter';
  String get updateTemplates => arabic ? 'تحديث' : 'Update';
  String get updatePresenter => arabic ? 'تحديث' : 'Update';
  String get refreshPresenter => updatePresenter;
  String get ready => arabic ? 'محمل' : 'Ready';
  String get notReady => arabic ? 'غير محمل' : 'Not ready';
  String get optional => arabic ? 'اختياري' : 'Optional';
  String get downloadRequired => arabic ? 'التحديث مطلوب' : 'Update required';
  String get back => arabic ? 'رجوع' : 'Back';
  String get searchTemplates => arabic ? 'ابحث عن قالب' : 'Search templates';
  String get templateSelectionPrompt => arabic
      ? 'اختر قالبًا مناسبًا حسب نوع الصفحة والحجم.'
      : 'Choose a template that fits the type, layout, and size.';
  String get clearTemplateFilters => arabic ? 'مسح الفلتر' : 'Clear filters';
  String get adjustTemplateSearchOrFilters => arabic
      ? 'جرّب تغيير البحث أو الفلتر.'
      : 'Try changing the search or filters.';
  String get templateFilterPages => arabic ? 'متعدد الصفحات' : 'Pages';
  String get templateFilterThermal => arabic ? 'حراري' : 'Thermal';
  String get templateFilterA4 => 'A4';
  String get templateFilter80mm => arabic ? '٨٠ مم' : '80 mm';
  String get online => arabic ? 'متصل' : 'Online';
  String get offline => arabic ? 'دون اتصال' : 'Offline';
  String get presenterMode => arabic ? 'العمل بدون اتصال' : 'Presenter mode';
  String get usePresenterOffline =>
      arabic ? 'استخدام التقارير دون اتصال' : 'Use Presenter offline';
  String get continueLabel => arabic ? 'متابعة' : 'Continue';
  String get saveSettings => arabic ? 'حفظ الإعدادات' : 'Save settings';
  String get cancel => arabic ? 'إلغاء' : 'Cancel';
  String get retry => arabic ? 'إعادة المحاولة' : 'Retry';
  String get more => arabic ? 'المزيد' : 'More';
  String get less => arabic ? 'أقل' : 'Less';
  String get errorCode => arabic ? 'الرمز' : 'Code';
  String get errorMessage => arabic ? 'الرسالة' : 'Message';
  String get renderFailureTitle =>
      arabic ? 'تعذر عرض التقرير' : 'Unable to display report';
  String get maintenanceAndSupport =>
      arabic ? 'الصيانة والدعم' : 'Maintenance and support';
  String get clearCacheFiles =>
      arabic ? 'حذف ملفات الكاش' : 'Delete cache files';
  String get clearCacheFilesDescription => arabic
      ? 'حذف الملفات المؤقتة المحفوظة'
      : 'Delete locally cached temporary files';
  String get sendReportDataToDevelopment => arabic
      ? 'إرسال بيانات التقرير إلى التطوير'
      : 'Send report data to development';
  String get developmentSupportDescription => arabic
      ? 'مساعدة فريق التطوير على تحسين التقرير'
      : 'Help the development team improve this report';
  String get preparingDevelopmentSupportShare =>
      arabic ? 'جارٍ تجهيز المشاركة…' : 'Preparing share…';
  String get clearCacheWarningTitle =>
      arabic ? 'حذف ملفات الكاش؟' : 'Delete cache files?';
  String get clearCacheWarningBody => arabic
      ? 'سيتم حذف ملفات التقارير المخزنة . لن يتم حذف تفضيلات القالب المحفوظة.'
      : 'Only cached templates and offline Presenter files will be deleted. Saved report settings and template preferences will be kept.';
  String get deleteCache => arabic ? 'حذف الكاش' : 'Delete cache';
  String get cacheCleared => arabic
      ? 'تم حذف ملفات الكاش. حدّث التقارير للمتابعة.'
      : 'Cache files were deleted. Update resources to continue.';
  String get technicalCategory => arabic ? 'نوع الخطأ' : 'Technical category';
  String get technicalPath => arabic ? 'المسار' : 'Path';
  String get close => arabic ? 'إغلاق' : 'Close';
  String get settings => arabic ? 'إعدادات التقرير' : 'Report settings';
  String get resources => arabic ? 'الموارد' : 'Resources';
  String get defaultTemplate =>
      arabic ? 'القالب الافتراضي' : 'Default template';
  String get changeTemplate => arabic ? 'تغيير القالب' : 'Change template';
  String get prepareAndSynchronize =>
      arabic ? 'تحديث التقارير' : 'Prepare and update';
  String get prepareAndSynchronizeDescription => arabic
      ? 'تحديث القوالب والمستعرض'
      : 'Manage available preparation and updates';
  String get saveAndRefresh =>
      arabic ? 'حفظ وتحديث التقرير' : 'Save and refresh report';
  String get useTemplate => arabic ? 'استخدام القالب' : 'Use template';
  String get adoptAndOpenReport =>
      arabic ? 'اعتماد القالب وفتح التقرير' : 'Adopt and open report';
  String get print => arabic ? 'طباعة' : 'Print';
  String get preparingPrint =>
      arabic ? 'جارٍ تجهيز الطباعة' : 'Preparing print';
  String get connectingPrinter =>
      arabic ? 'جارٍ الاتصال بالطابعة' : 'Connecting printer';
  String get sendingToPrinter =>
      arabic ? 'جارٍ إرسال الطباعة' : 'Sending to printer';
  String get thermalPrinterSettings =>
      arabic ? 'إعدادات الطابعة الحرارية' : 'Thermal printer settings';
  String get printingSection => arabic ? 'الطباعة' : 'Printing';
  String get configureThermalPrinter =>
      arabic ? 'إعداد الطابعة الحرارية' : 'Set up thermal printer';
  String get noDefaultPrinterConfigured => arabic
      ? 'لم يتم إعداد طابعة افتراضية.'
      : 'No default printer has been configured.';
  String get thermalPrinterSettingsDescription => arabic
      ? 'تغيير الاتصال، عرض الطباعة، وخيارات الورق.'
      : 'Change the connection, print width, and paper options.';
  String get printerConnectionType =>
      arabic ? 'نوع الاتصال' : 'Connection type';
  String get printerName => arabic ? 'اسم الطابعة' : 'Printer name';
  String get bluetooth => 'Bluetooth';
  String get usb => 'USB';
  String get tcpNetwork => arabic ? 'الشبكة (TCP)' : 'TCP / Network';
  String get suggestedPaperSize =>
      arabic ? 'مقاس الورق المقترح' : 'Suggested paper size';
  String get printableWidth =>
      arabic ? 'العرض القابل للطباعة (بكسل)' : 'Printable width (px)';
  String get copies => arabic ? 'النسخ' : 'Copies';
  String get feedDots => arabic ? 'تغذية الورق (نقطة)' : 'Feed dots';
  String get grayscale => arabic ? 'تدرج رمادي' : 'Grayscale';
  String get grayscaleDescription =>
      arabic ? 'إيقافه يرسل أسود وأبيض' : 'When off, black and white is sent';
  String get sendCutCommand =>
      arabic ? 'إرسال أمر قص الورق' : 'Send paper-cut command';
  String get sendCutCommandDescription => arabic
      ? 'لا يمكن التحقق من وجود قاطع في الطابعة'
      : 'The printer cutter cannot be detected';
  String get testPrint => arabic ? 'طباعة اختبار' : 'Test print';
  String get saveDefaultPrinter =>
      arabic ? 'حفظ الطابعة الافتراضية' : 'Save default printer';
  String get removeDefaultPrinter =>
      arabic ? 'إزالة الطابعة الافتراضية' : 'Remove default printer';
  String get defaultPrinter =>
      arabic ? 'الطابعة الافتراضية' : 'Default printer';
  String get refreshDevices => arabic ? 'تحديث الأجهزة' : 'Refresh devices';
  String get bluetoothPairedDevices => arabic
      ? 'الأجهزة المقترنة عبر Bluetooth'
      : 'Paired Bluetooth devices';
  String get connectedUsbPrinters =>
      arabic ? 'طابعات USB المتصلة' : 'Connected USB printers';
  String get hostOrIpAddress =>
      arabic ? 'عنوان المضيف أو IP' : 'Host / IP address';
  String get port => arabic ? 'المنفذ' : 'Port';
  String get timeoutSeconds =>
      arabic ? 'مهلة الاتصال (ثوانٍ)' : 'Timeout (seconds)';
  String get refreshToShowDevices => arabic
      ? 'اضغط «تحديث الأجهزة» لعرض الأجهزة المتاحة.'
      : 'Refresh devices to show available devices.';
  String get invalidPrintableWidth => arabic
      ? 'أدخل عرض طباعة صالحًا.'
      : 'Enter a valid printable width.';
  String get hostRequired => arabic
      ? 'أدخل عنوان IP أو اسم المضيف.'
      : 'Enter an IP address or hostname.';
  String get invalidPort => arabic
      ? 'أدخل منفذًا بين 1 و65535.'
      : 'Enter a port from 1 to 65535.';
  String get invalidTimeout => arabic
      ? 'أدخل مهلة بين 1 و60 ثانية.'
      : 'Enter a timeout from 1 to 60 seconds.';
  String get savedPrinterUnavailable => arabic
      ? 'الطابعة المحفوظة غير متاحة الآن. اربطها من إعدادات Android ثم حدّث الأجهزة وأعد اختيارها.'
      : 'The saved printer is unavailable. Pair it in Android settings, refresh devices, then select it again.';
  String printerSettingsError(String code) => switch (code) {
    'savedBluetoothPrinterUnavailable' || 'bluetoothPrinterUnavailable' =>
      arabic
          ? 'الطابعة المحفوظة غير متاحة. تأكد من ربطها عبر Bluetooth ثم حدّث الأجهزة.'
          : 'The saved Bluetooth printer is unavailable. Pair it, then refresh devices.',
    'bluetoothPermissionDenied' => arabic
        ? 'يلزم السماح بصلاحية الأجهزة القريبة لاستخدام طابعة Bluetooth.'
        : 'Nearby devices permission is required for Bluetooth printing.',
    'bluetoothUnavailable' || 'bluetoothDisabled' =>
      arabic
          ? 'Bluetooth غير متاح. فعّله ثم أعد المحاولة.'
          : 'Bluetooth is unavailable. Enable it and try again.',
    'bluetoothConnectionFailed' => arabic
        ? 'تعذر الاتصال بطابعة Bluetooth. تأكد أنها قيد التشغيل وقريبة.'
        : 'The Bluetooth printer could not be connected. Check that it is powered on and nearby.',
    'tcpConnectionTimeout' => arabic
        ? 'انتهت مهلة الاتصال بالشبكة. تحقق من عنوان IP والمنفذ والشبكة.'
        : 'The network connection timed out. Check the IP address, port, and network.',
    'tcpHostNotFound' => arabic
        ? 'تعذر العثور على عنوان الطابعة في الشبكة.'
        : 'The network printer address could not be found.',
    'tcpConnectionRefused' => arabic
        ? 'رفضت الطابعة الاتصال. تأكد من المنفذ وأن الطابعة متصلة بالشبكة.'
        : 'The printer refused the connection. Check the port and network connection.',
    'tcpSendFailed' || 'tcpConnectionFailed' => arabic
        ? 'تعذر الإرسال إلى طابعة الشبكة. تحقق من IP والمنفذ وأن الجهازين على الشبكة نفسها.'
        : 'Data could not be sent to the network printer. Check the IP address, port, and network.',
    'printerConnectionFailed' => arabic
        ? 'تعذر الاتصال بالطابعة. تأكد أنها قيد التشغيل.'
        : 'The printer could not be connected. Check that it is powered on.',
    _ => arabic
        ? 'تعذر تنفيذ الطباعة. راجع إعدادات الطابعة ثم أعد المحاولة.'
        : 'Printing could not be completed. Review the printer settings and try again.',
  };
  String get savePdf => arabic ? 'حفظ PDF' : 'Save PDF';
  String get share => arabic ? 'مشاركة' : 'Share';
  String get language => arabic ? 'اللغة' : 'Language';
  String get layout => arabic ? 'نوع الصفحة' : 'Layout';
  String get pageSize => arabic ? 'الحجم' : 'Size';
  String get reportType => arabic ? 'نوع التقرير' : 'Report Type';
  String get customType => arabic ? 'النوع المخصص' : 'Custom type';
  String get documentSettings =>
      arabic ? 'إعدادات المستند' : 'Document settings';
  String get apply => arabic ? 'تطبيق' : 'Apply';
  String get all => arabic ? 'الكل' : 'All';

  String reportTypeLabel(UrbReportTypeCode type) => switch (type.value) {
    'sales_invoice' => arabic ? 'فاتورة مبيعات' : 'Sales Invoice',
    'sales_return' => arabic ? 'مردود مبيعات' : 'Sales Return',
    'customer_order' => arabic ? 'طلب عميل' : 'Customer Order',
    'receipt_voucher' => arabic ? 'سند قبض' : 'Receipt Voucher',
    'payment_voucher' => arabic ? 'سند صرف' : 'Payment Voucher',
    'quotation' => arabic ? 'عرض سعر' : 'Quotation',
    'account_statement' => arabic ? 'كشف حساب' : 'Account Statement',
    'report' => arabic ? 'تقرير' : 'Report',
    _ => type.value,
  };

  String languageValueLabel(ReportLanguage language) => switch (language) {
    ReportLanguage.ar => arabic ? 'العربية' : 'Arabic',
    ReportLanguage.en => arabic ? 'الإنجليزية' : 'English',
  };

  String layoutValueLabel(ReportLayout layout) => switch (layout) {
    ReportLayout.pages => arabic ? 'صفحات' : 'Pages',
    ReportLayout.thermal => arabic ? 'حراري' : 'Thermal',
  };

  String sizeValueLabel(ReportPageSize size) => switch (size) {
    ReportPageSize.a4 => 'A4',
    ReportPageSize.a5 => 'A5',
    ReportPageSize.letter => arabic ? 'Letter' : 'Letter',
    ReportPageSize.thermal80 => arabic ? '٨٠ مم' : '80 mm',
    ReportPageSize.thermal58 => arabic ? '٥٨ مم' : '58 mm',
    ReportPageSize.custom => arabic ? 'مخصص' : 'Custom',
  };
  String customSizeValueLabel({
    required double width,
    required double height,
    required ReportMeasurementUnit unit,
  }) {
    String number(double value) => value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '${number(width)} × ${number(height)} ${unit.value}';
  }

  String thumbnailSizeValueLabel(ReportPageSize size) => switch (size) {
    ReportPageSize.a4 => 'A4',
    ReportPageSize.a5 => 'A5',
    ReportPageSize.letter => 'Letter',
    ReportPageSize.thermal80 => arabic ? '٨٠مم' : '80mm',
    ReportPageSize.thermal58 => arabic ? '٥٨مم' : '58mm',
    ReportPageSize.custom => arabic ? 'مخصص' : 'Custom',
  };

  String customThumbnailSizeValueLabel({
    required double width,
    required double height,
    required ReportMeasurementUnit unit,
  }) {
    String number(double value) => value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '${number(width)}×${number(height)}${unit.value}';
  }

  String orientationValueLabel(ReportOrientation orientation) =>
      switch (orientation) {
        ReportOrientation.portrait => arabic ? 'عمودي' : 'Portrait',
        ReportOrientation.landscape => arabic ? 'أفقي' : 'Landscape',
      };
  String get loading => arabic ? 'جارٍ التحميل…' : 'Loading…';
  String get syncingTemplates =>
      arabic ? 'جارٍ تحديث القوالب…' : 'Updating templates…';
  String get syncingPresenter =>
      arabic ? 'جارٍ تحديث مستعرض التقارير…' : 'Updating Presenter…';
  String get preparingPreview =>
      arabic ? 'تجهيز التقرير…' : 'Preparing preview…';
  String get noSearchResults =>
      arabic ? 'لا توجد قوالب مطابقة.' : 'No matching templates.';
  String matchingTemplates(int count) => arabic
      ? 'القوالب المطابقة: $count'
      : '$count matching template${count == 1 ? '' : 's'}';
  String templateCount(int count) => arabic
      ? 'عدد القوالب المتوافقة: $count'
      : '$count compatible template${count == 1 ? '' : 's'}';
  String templateCatalogDetail({
    required int cachedCount,
    required int compatibleCount,
    required bool queryScopeLimited,
  }) {
    final cachedLabel = queryScopeLimited
        ? (arabic ? 'المخزنة لهذا التطبيق' : 'Cached for this app')
        : (arabic ? 'القوالب المخزنة ' : 'Cached for system');
    final compatibleLabel = arabic
        ? 'المتوافقة مع نوع التقرير الحالي'
        : 'Compatible with current report';
    return '$cachedLabel: $cachedCount · $compatibleLabel: $compatibleCount';
  }

  String lastSynchronized(String date) =>
      arabic ? 'آخر تحديث: $date' : 'Last updated: $date';
  String presenterBundleDetails({
    required String presenterVersion,
    required String bundleVersion,
    String? updatedDate,
  }) {
    final details = arabic
        ? <String>['رقم النسخة: $presenterVersion', 'الحزمة: $bundleVersion']
        : <String>[
            'version Number: $presenterVersion',
            'Bundle: $bundleVersion',
          ];
    if (updatedDate != null) {
      details.add(
        arabic ? 'تاريخ التحديث: $updatedDate' : 'Updated: $updatedDate',
      );
    }
    return details.join(' · ');
  }

  String templateSelectionHelp(int count) => arabic
      ? '${templateCount(count)}. سيصبح القالب المختار هو الافتراضي  لنوع التقرير.'
      : '${templateCount(count)}. The selected template becomes the default for this system and report type.';
  String entryFallback(ReportEntryFallbackReason reason) => switch (reason) {
    ReportEntryFallbackReason.noSavedDefault =>
      arabic
          ? 'اختر قالبًا افتراضيًا لإعداد هذا التقرير.'
          : 'Choose a default template to set up this report.',
    ReportEntryFallbackReason.invalidSavedTemplate =>
      arabic
          ? 'لم يعد القالب الافتراضي متاحًا. تمت إزالة هذا الاختيار فقط.'
          : 'The saved default is no longer available. Only this scoped choice was removed.',
    ReportEntryFallbackReason.offlinePresenterUnavailable =>
      arabic
          ? 'نسخة مستعرض التقاير غير مكتملة. حدّث المستعرض للمتابعة دون اتصال.'
          : 'The local Presenter copy is incomplete. Update Presenter to continue offline.',
    ReportEntryFallbackReason.noCompatibleTemplates =>
      arabic
          ? 'لا توجد قوالب متوافقة حاليًا. حدّث القوالب للمتابعة.'
          : 'No compatible templates are currently available. Update templates to continue.',
    ReportEntryFallbackReason.entryPolicy =>
      arabic
          ? 'تتطلب سياسة فتح التقرير مراجعة ملفات التقارير أولًا.'
          : 'The report entry policy requires reviewing resources first.',
  };
  String templatesHelp({required bool queryScopeLimited}) => queryScopeLimited
      ? (arabic ? 'يتم تحديث القوالب.' : 'Updates templates.')
      : (arabic
            ? 'يتم تحديث  قوالب التقارير وتخزينها .'
            : 'Updates all report templates and stores them locally.');
  String get presenterOnlineHelp => arabic
      ? 'الوضع المتصل يستخدم مستعرض التقارير من السرفر.'
      : 'Online mode uses Presenter from the server.';
  String get presenterOfflineHelp => arabic
      ? 'الوضع دون اتصال يحتاج تحميل مستعرض التقارير.'
      : 'Offline mode requires a complete local Presenter copy.';
  String get presenterOfflineUnavailableHelp => arabic
      ? 'حدّث مستعرض التقارير للعمل بدون اتصال.'
      : 'Update Presenter before enabling offline mode.';
  String get previewFailed =>
      arabic ? 'تعذر عرض التقرير.' : 'The report could not be displayed.';
  String get presenterIncompatible => arabic
      ? 'نسخة مستعرض التقارير قديمة أو غير متوافقة. حدّث مستعرض التقارير ثم أعد المحاولة.'
      : 'The Presenter is outdated or incompatible. Update it and try again.';
  String get renderTimedOut => arabic
      ? 'استغرق عرض التقرير وقتًا أطول من المتوقع. أعد المحاولة أو حدّث العارض.'
      : 'Report rendering took longer than expected. Retry or update Presenter.';
  String get printSubmitted =>
      arabic ? 'تم إرسال التقرير للطباعة.' : 'Report submitted for printing.';
  String get printCancelled =>
      arabic ? 'تم إلغاء الطباعة.' : 'Printing was cancelled.';
  String get pdfSaved => arabic ? 'تم حفظ ملف PDF.' : 'PDF saved.';
  String get pdfShared =>
      arabic ? 'تم فتح مشاركة ملف PDF.' : 'PDF share opened.';
  String get cleanupWarning => arabic
      ? 'أُغلق التقرير مع تعذر إكمال التنظيف.'
      : 'The report closed with an incomplete cleanup warning.';

  String failure(ReportFlowFailure? failure) {
    if (failure == null) return previewFailed;
    return switch (failure.code) {
      ReportFlowFailureCode.flowAlreadyActive =>
        arabic
            ? 'هناك تقرير مفتوح بالفعل.'
            : 'Another report flow is already active.',
      ReportFlowFailureCode.noCompatibleTemplates =>
        arabic
            ? 'لا توجد قوالب متوافقة لهذا التقرير.'
            : 'No compatible templates are available for this report.',
      ReportFlowFailureCode.templateSyncFailed =>
        arabic ? 'تعذر تحديث القوالب.' : 'Template update failed.',
      ReportFlowFailureCode.presenterSyncFailed =>
        arabic ? 'تعذر تحديث مستعرض التقارير.' : 'Presenter update failed.',
      ReportFlowFailureCode.previewPreparationFailed =>
        arabic ? 'تعذر تجهيز التقرير.' : 'Report preparation failed.',
      ReportFlowFailureCode.previewLoadFailed => previewFailed,
      ReportFlowFailureCode.presenterIncompatible => presenterIncompatible,
      ReportFlowFailureCode.renderTimedOut => renderTimedOut,
      ReportFlowFailureCode.renderFailed => previewFailed,
      ReportFlowFailureCode.persistenceFailed =>
        arabic
            ? 'تعذر حفظ إعدادات التقرير.'
            : 'The report settings could not be saved.',
      ReportFlowFailureCode.actionDenied =>
        arabic
            ? 'هذه العملية غير مسموح بها وفق سياسة التقرير.'
            : 'This action is denied by the report policy.',
      ReportFlowFailureCode.exportUnavailable =>
        arabic
            ? 'التصدير غير متاح حتى يكتمل عرض التقرير.'
            : 'Export is unavailable until report rendering completes.',
      ReportFlowFailureCode.exportInProgress =>
        arabic
            ? 'انتظر حتى تكتمل عملية الإخراج الحالية.'
            : 'Wait for the current output action to finish.',
      ReportFlowFailureCode.operationInProgress =>
        arabic
            ? 'انتظر حتى تكتمل العملية الحالية.'
            : 'Wait for the current operation to finish.',
      ReportFlowFailureCode.exportFailed =>
        arabic ? 'تعذر تصدير ملف PDF.' : 'PDF export failed.',
      ReportFlowFailureCode.developmentSupportFailed =>
        arabic
            ? 'تعذر إنشاء أو مشاركة بيانات التقرير.'
            : 'Report support data could not be created or shared.',
      ReportFlowFailureCode.cacheClearFailed =>
        arabic
            ? 'تعذر حذف ملفات الكاش بالكامل.'
            : 'Cache files could not be fully deleted.',
      ReportFlowFailureCode.printUnavailable =>
        arabic
            ? 'الطباعة غير متاحة حتى يكتمل عرض التقرير.'
            : 'Printing is unavailable until report rendering completes.',
      ReportFlowFailureCode.printSetupRequired =>
        arabic
            ? 'يجب إكمال إعداد الطباعة أولًا.'
            : 'Printer setup must be completed first.',
      ReportFlowFailureCode.printAppNotInstalled =>
        arabic
            ? 'تطبيق الطباعة المطلوب غير مثبت.'
            : 'The required printing application is not installed.',
      ReportFlowFailureCode.printUnsupportedContract =>
        arabic
            ? 'إصدار تكامل الطباعة غير مدعوم.'
            : 'The printing integration contract is unsupported.',
      ReportFlowFailureCode.printUnsupportedPaperConversion =>
        arabic
            ? 'لا يمكن تحويل حجم الورق المحدد للطباعة.'
            : 'The selected paper size cannot be converted for printing.',
      ReportFlowFailureCode.savedBluetoothPrinterUnavailable =>
        arabic
            ? 'الطابعة المحفوظة غير متاحة. تأكد من ربطها عبر Bluetooth ثم حدّث إعداداتها.'
            : 'The saved Bluetooth printer is unavailable. Pair it, then refresh its settings.',
      ReportFlowFailureCode.bluetoothPermissionDenied =>
        arabic
            ? 'يلزم السماح بصلاحية الأجهزة القريبة لاستخدام طابعة Bluetooth.'
            : 'Nearby devices permission is required for Bluetooth printing.',
      ReportFlowFailureCode.bluetoothPrinterConnectionFailed =>
        arabic
            ? 'تعذر الاتصال بطابعة Bluetooth. تأكد أنها قيد التشغيل وقريبة.'
            : 'The Bluetooth printer could not be connected. Check that it is powered on and nearby.',
      ReportFlowFailureCode.tcpPrinterConnectionTimeout =>
        arabic
            ? 'انتهت مهلة الاتصال بالشبكة. تحقق من عنوان IP والمنفذ وأن الجهازين على الشبكة نفسها.'
            : 'The network printer connection timed out. Check its IP address, port, and network.',
      ReportFlowFailureCode.tcpPrinterHostNotFound =>
        arabic
            ? 'تعذر العثور على عنوان طابعة الشبكة. تحقق من IP أو اسم المضيف.'
            : 'The network printer host could not be found. Check its IP address or hostname.',
      ReportFlowFailureCode.tcpPrinterConnectionRefused =>
        arabic
            ? 'رفضت طابعة الشبكة الاتصال. تحقق من المنفذ وأنها متصلة بالشبكة.'
            : 'The network printer refused the connection. Check its port and network connection.',
      ReportFlowFailureCode.tcpPrinterSendFailed =>
        arabic
            ? 'انقطع الإرسال إلى طابعة الشبكة قبل اكتماله. أعد المحاولة.'
            : 'Sending data to the network printer did not complete. Please try again.',
      ReportFlowFailureCode.tcpPrinterConnectionFailed =>
        arabic
            ? 'تعذر الاتصال بطابعة الشبكة. تحقق من IP والمنفذ والشبكة نفسها.'
            : 'The network printer could not be connected. Check its IP address, port, and network.',
      ReportFlowFailureCode.thermalPrinterConnectionFailed =>
        arabic
            ? 'تعذر الاتصال بالطابعة. تأكد أنها قيد التشغيل وقريبة.'
            : 'The printer could not be connected. Check that it is powered on and nearby.',
      ReportFlowFailureCode.printFailed =>
        arabic ? 'تعذرت طباعة التقرير.' : 'Report printing failed.',
      ReportFlowFailureCode.cleanupFailed => cleanupWarning,
      ReportFlowFailureCode.disposed =>
        arabic ? 'تم إغلاق  التقرير.' : 'The report flow has been disposed.',
      ReportFlowFailureCode.unknown =>
        arabic ? 'حدث خطأ غير متوقع.' : 'An unexpected error occurred.',
    };
  }
}
