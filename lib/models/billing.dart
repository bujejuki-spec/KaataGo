/// Keadaan tagihan sebuah tagihan langganan.
enum InvoiceStatus {
  /// Belum dibayar.
  unpaid,

  /// Bukti bayar sudah diunggah, menunggu diperiksa KaataGo.
  review,

  /// Diterima.
  paid,

  /// Dibebaskan — masa percobaan, atau kompensasi gangguan.
  waived,
}

const _statusDb = {
  InvoiceStatus.unpaid: 'unpaid',
  InvoiceStatus.review: 'review',
  InvoiceStatus.paid: 'paid',
  InvoiceStatus.waived: 'waived',
};

const kInvoiceStatusLabels = {
  InvoiceStatus.unpaid: 'Belum Dibayar',
  InvoiceStatus.review: 'Menunggu Verifikasi',
  InvoiceStatus.paid: 'Lunas',
  InvoiceStatus.waived: 'Dibebaskan',
};

InvoiceStatus _statusOf(Object? v) => _statusDb.entries
    .firstWhere((e) => e.value == v, orElse: () => _statusDb.entries.first)
    .key;

/// Setelan langganan sebuah resto — harga dan tanggal tagihnya.
class RestoBilling {
  final String restoId;

  /// Rupiah per bulan. Nol berarti gratis, dan resto bernilai nol tidak
  /// pernah terkunci.
  final int monthlyPrice;

  /// Tanggal jatuh tempo tiap bulan, 1–28.
  ///
  /// Dibatasi 28 supaya artinya sama di bulan mana pun. "Tanggal 31"
  /// tidak ada di Februari, dan menggesernya diam-diam ke 28 membuat
  /// tagihan datang di hari yang tidak dijanjikan.
  final int billingDay;

  /// Tenggang sesudah jatuh tempo sebelum restonya terkunci.
  final int graceDays;

  final bool active;
  final String? note;

  const RestoBilling({
    required this.restoId,
    this.monthlyPrice = 0,
    this.billingDay = 1,
    this.graceDays = 1,
    this.active = true,
    this.note,
  });

  bool get gratis => monthlyPrice <= 0;

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'monthly_price': monthlyPrice,
        'billing_day': billingDay,
        'grace_days': graceDays,
        'active': active,
        'note': note,
      };

  factory RestoBilling.fromMap(Map<String, dynamic> map) => RestoBilling(
        restoId: map['resto_id'] as String,
        monthlyPrice: (map['monthly_price'] as num?)?.toInt() ?? 0,
        billingDay: (map['billing_day'] as num?)?.toInt() ?? 1,
        graceDays: (map['grace_days'] as num?)?.toInt() ?? 1,
        active: map['active'] != false,
        note: map['note'] as String?,
      );

  RestoBilling copyWith({
    int? monthlyPrice,
    int? billingDay,
    int? graceDays,
    bool? active,
    String? note,
  }) =>
      RestoBilling(
        restoId: restoId,
        monthlyPrice: monthlyPrice ?? this.monthlyPrice,
        billingDay: billingDay ?? this.billingDay,
        graceDays: graceDays ?? this.graceDays,
        active: active ?? this.active,
        note: note ?? this.note,
      );
}

/// Satu tagihan bulanan.
class BillingInvoice {
  final String id;
  final String restoId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime dueDate;
  final int amount;
  final InvoiceStatus status;

  final String? proofBase64;
  final String? paidNote;
  final DateTime? submittedAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? rejectReason;

  /// Nama resto — hanya terisi di layar Super Admin, yang membaca
  /// tagihan lintas resto.
  final String? restoName;

  const BillingInvoice({
    required this.id,
    required this.restoId,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.amount,
    this.status = InvoiceStatus.unpaid,
    this.proofBase64,
    this.paidNote,
    this.submittedAt,
    this.confirmedBy,
    this.confirmedAt,
    this.rejectReason,
    this.restoName,
  });

  bool get open =>
      status == InvoiceStatus.unpaid || status == InvoiceStatus.review;

  bool get hasProof => proofBase64 != null && proofBase64!.isNotEmpty;

  factory BillingInvoice.fromMap(Map<String, dynamic> map) => BillingInvoice(
        id: map['id'] as String,
        restoId: map['resto_id'] as String,
        periodStart: DateTime.parse(map['period_start'].toString()),
        periodEnd: DateTime.parse(map['period_end'].toString()),
        dueDate: DateTime.parse(map['due_date'].toString()),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        status: _statusOf(map['status']),
        proofBase64: map['proof_base64'] as String?,
        paidNote: map['paid_note'] as String?,
        submittedAt: _waktu(map['submitted_at']),
        confirmedBy: map['confirmed_by'] as String?,
        confirmedAt: _waktu(map['confirmed_at']),
        rejectReason: map['reject_reason'] as String?,
        restoName: map['restaurants'] is Map
            ? (map['restaurants'] as Map)['name'] as String?
            : map['resto_name'] as String?,
      );

  static DateTime? _waktu(Object? v) =>
      v == null ? null : DateTime.parse(v.toString()).toLocal();
}

/// Ringkasan keadaan langganan sebuah resto, dihitung di server.
///
/// Dihitung di satu tempat dan dibaca dari sana, bukan disusun ulang di
/// aplikasi: perhitungan yang sama di dua tempat akan berpisah, dan
/// yang terlihat adalah layar yang mengaku aman sementara database
/// menolak menyimpan apa pun.
class BillingState {
  final bool locked;
  final DateTime? dueDate;

  /// Sisa hari menuju jatuh tempo. Negatif berarti sudah lewat.
  final int? daysLeft;

  final int? amount;
  final String? invoiceId;
  final InvoiceStatus? invoiceStatus;
  final int monthlyPrice;
  final int billingDay;
  final bool active;

  const BillingState({
    this.locked = false,
    this.dueDate,
    this.daysLeft,
    this.amount,
    this.invoiceId,
    this.invoiceStatus,
    this.monthlyPrice = 0,
    this.billingDay = 1,
    this.active = false,
  });

  /// Tidak ada yang perlu dikabarkan: gratis, dimatikan, atau tidak ada
  /// tagihan terbuka.
  static const tenang = BillingState();

  /// Pengingat mulai muncul H-3, dan tetap muncul sesudah lewat jatuh
  /// tempo selama belum lunas.
  ///
  /// Tiga hari dipilih bukan karena angka bulat: itu jarak terpendek
  /// yang masih memuat satu akhir pekan, dan transfer antarbank yang
  /// dikirim Jumat sore baru terlihat Senin.
  bool get perluDiingatkan =>
      active &&
      monthlyPrice > 0 &&
      invoiceId != null &&
      invoiceStatus != InvoiceStatus.paid &&
      invoiceStatus != InvoiceStatus.waived &&
      (daysLeft ?? 99) <= 3;

  bool get lewatTempo => (daysLeft ?? 99) < 0;

  bool get menungguVerifikasi => invoiceStatus == InvoiceStatus.review;

  factory BillingState.fromMap(Map<String, dynamic> map) => BillingState(
        locked: map['locked'] == true,
        dueDate: map['due_date'] == null
            ? null
            : DateTime.parse(map['due_date'].toString()),
        daysLeft: (map['days_left'] as num?)?.toInt(),
        amount: (map['amount'] as num?)?.toInt(),
        invoiceId: map['invoice_id'] as String?,
        invoiceStatus:
            map['invoice_status'] == null ? null : _statusOf(map['invoice_status']),
        monthlyPrice: (map['monthly_price'] as num?)?.toInt() ?? 0,
        billingDay: (map['billing_day'] as num?)?.toInt() ?? 1,
        active: map['active'] == true,
      );
}
