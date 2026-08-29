/// Selisih kurang sebuah shift yang masih ditagihkan kepada kasirnya.
///
/// Hanya yang **kurang** yang jadi tagihan. Tidak ada yang bisa ditagih
/// dari uang yang justru berlebih — yang perlu dilakukan menelusuri
/// penjualan yang belum diinput, dan itu pekerjaan Finance, bukan utang
/// kasir.
class CashVariance {
  final String id;
  final String restoId;
  final String shiftId;
  final String employeeEmail;
  final String? employeeName;

  /// Selalu positif — jenisnya yang menentukan artinya.
  final int amount;

  /// Kurang berarti uang lacinya kurang dari yang seharusnya; lebih
  /// berarti justru berlebih.
  ///
  /// Keduanya disimpan di tabel yang sama karena keduanya lahir dari
  /// kejadian yang sama — satu shift ditutup dan angkanya tidak cocok.
  /// Yang berbeda hanya siapa yang menutupnya dan bagaimana.
  final bool lebih;

  /// Bagaimana barisnya ditutup: `dibayar`, `input_penjualan`, atau
  /// `pendapatan`. Null selama masih terbuka.
  final String? resolution;

  final bool lunas;
  final String? note;
  final DateTime createdAt;
  final DateTime? settledAt;
  final String? settledBy;
  final String? settleNote;

  CashVariance({
    required this.id,
    required this.restoId,
    required this.shiftId,
    required this.employeeEmail,
    this.employeeName,
    required this.amount,
    this.lebih = false,
    this.resolution,
    this.lunas = false,
    this.note,
    required this.createdAt,
    this.settledAt,
    this.settledBy,
    this.settleNote,
  });

  /// Kalimat pendek yang menyebut apa yang sebenarnya terjadi pada
  /// barisnya. Dipakai di daftar dan di rinciannya.
  String get caraSelesai => switch (resolution) {
        'dibayar' => 'Dibayar kasir',
        'input_penjualan' => 'Penjualannya sudah diinput',
        'pendapatan' => 'Diakui pendapatan lain-lain',
        _ => 'Belum diselesaikan',
      };

  String get namaTampil {
    final n = employeeName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return employeeEmail.split('@').first;
  }

  factory CashVariance.fromMap(Map<String, dynamic> map) => CashVariance(
        id: map['id'].toString(),
        restoId: map['resto_id'].toString(),
        shiftId: map['shift_id'].toString(),
        employeeEmail: map['employee_email']?.toString() ?? '',
        employeeName: map['employee_name']?.toString(),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        lebih: map['kind'] == 'lebih',
        resolution: map['resolution']?.toString(),
        lunas: map['status'] == 'settled',
        note: map['note']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        settledAt: DateTime.tryParse(map['settled_at']?.toString() ?? ''),
        settledBy: map['settled_by']?.toString(),
        settleNote: map['settle_note']?.toString(),
      );
}
