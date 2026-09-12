/// Rekening perusahaan merchant.
///
/// Berdiri sendiri, tidak menempel di satu resto. Satu perusahaan yang
/// punya beberapa cabang menyetor ke rekening yang sama, dan yang paling
/// menentukan: sebuah mutasi bank masuk ke REKENING, bukan ke resto —
/// jadi rekeningnya harus punya keberadaan sendiri sebelum mutasi bisa
/// ditautkan ke mana pun.
class BankAccount {
  final String id;
  final String bankName;
  final String accountNumber;
  final String accountHolder;

  /// Sebutan pendek untuk dibaca orang: "BCA Operasional", "Mandiri
  /// Cabang Dua". Nomor rekening tidak pernah dihafal siapa pun, dan
  /// daftar berisi empat nomor tanpa nama menuntut yang memilihnya
  /// membaca digit satu per satu.
  final String? label;

  final bool active;

  /// Rekening yang dipakai kalau tidak disebut yang mana: tujuan setoran
  /// tunai, dan yang ditampilkan di layar Transfer pelanggan.
  ///
  /// Sifatnya per resto, bukan milik rekeningnya sendiri — rekening yang
  /// utama di cabang satu bisa jadi cadangan di cabang lain.
  final bool isPrimary;

  const BankAccount({
    required this.id,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    this.label,
    this.active = true,
    this.isPrimary = false,
  });

  /// Yang dibaca orang saat memilih dari daftar.
  String get tampilan =>
      label == null || label!.trim().isEmpty ? bankName : label!.trim();

  /// Satu baris lengkap untuk struk dan layar Transfer.
  String get ringkas => '$bankName · $accountNumber · a.n. $accountHolder';

  factory BankAccount.fromMap(Map<String, dynamic> map) => BankAccount(
        id: map['id'].toString(),
        bankName: map['bank_name']?.toString() ?? '',
        accountNumber: map['account_number']?.toString() ?? '',
        accountHolder: map['account_holder']?.toString() ?? '',
        label: map['label'] as String?,
        active: map['active'] as bool? ?? true,
        // Datang dari tabel penautnya saat dibaca lewat join; baris
        // rekeningnya sendiri tidak punya kolom ini.
        isPrimary: map['is_primary'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'bank_name': bankName.trim(),
        'account_number': accountNumber.trim(),
        'account_holder': accountHolder.trim(),
        'label': label?.trim().isEmpty ?? true ? null : label!.trim(),
        'active': active,
      };

  BankAccount copyWith({
    String? bankName,
    String? accountNumber,
    String? accountHolder,
    String? label,
    bool? active,
    bool? isPrimary,
  }) =>
      BankAccount(
        id: id,
        bankName: bankName ?? this.bankName,
        accountNumber: accountNumber ?? this.accountNumber,
        accountHolder: accountHolder ?? this.accountHolder,
        label: label ?? this.label,
        active: active ?? this.active,
        isPrimary: isPrimary ?? this.isPrimary,
      );
}
