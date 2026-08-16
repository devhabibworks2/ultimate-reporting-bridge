final class UrbSystemCode {
  const UrbSystemCode(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UrbSystemCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

abstract final class UrbSystem {
  static const motakamelTransactions = UrbSystemCode('motakamel_transactions');
}

final class UrbReportTypeCode {
  const UrbReportTypeCode(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrbReportTypeCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

abstract final class UrbReportType {
  static const salesInvoice = UrbReportTypeCode('sales_invoice');
  static const salesReturn = UrbReportTypeCode('sales_return');
  static const customerOrder = UrbReportTypeCode('customer_order');
  static const receiptVoucher = UrbReportTypeCode('receipt_voucher');
  static const paymentVoucher = UrbReportTypeCode('payment_voucher');
  static const quotation = UrbReportTypeCode('quotation');
  static const accountStatement = UrbReportTypeCode('account_statement');
  static const report = UrbReportTypeCode('report');

  static const values = <UrbReportTypeCode>[
    salesInvoice,
    salesReturn,
    customerOrder,
    receiptVoucher,
    paymentVoucher,
    quotation,
    accountStatement,
    report,
  ];

  static UrbReportTypeCode parseCanonical(String raw) => switch (raw.trim()) {
    'sales_invoice' => salesInvoice,
    'sales_return' => salesReturn,
    'customer_order' => customerOrder,
    'receipt_voucher' => receiptVoucher,
    'payment_voucher' => paymentVoucher,
    'quotation' => quotation,
    'account_statement' => accountStatement,
    'report' => report,
    _ => throw ArgumentError.value(
      raw,
      'reportType',
      'Unsupported report type.',
    ),
  };
}
