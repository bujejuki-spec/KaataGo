import 'package:flutter/foundation.dart';

import '../db/cashier_shift_repository.dart';

/// Shift yang sedang dipegang orang yang memakai aplikasi ini.
///
/// Disimpan di satu tempat dan dibaca penanda mengambang di atas rute
/// mana pun. Shift yang dibuka pagi lalu terlupakan sampai malam bukan
/// kelalaian yang aneh: begitu kasir mulai melayani, layar Shift Kasir
/// adalah layar yang paling jarang dibuka lagi sampai tutup toko.
///
/// Yang ditanggung kalau lupa bukan cuma kerapian. Shift yang tidak
/// ditutup membuat laci tidak pernah dihitung, selisih harinya tidak
/// pernah ketahuan, dan — sejak shift hanya bisa ditutup oleh yang
/// membukanya — kasir berikutnya tidak bisa membuka shiftnya sendiri.
class ShiftBerjalan extends ChangeNotifier {
  ShiftBerjalan._();

  static final ShiftBerjalan instance = ShiftBerjalan._();

  final _repo = CashierShiftRepository();

  /// Kapan shift itu dibuka. Null berarti tidak ada yang sedang
  /// dipegang orang ini.
  DateTime? _dibuka;

  /// Sudah pernah berhasil bertanya ke server atau belum.
  ///
  /// Dibedakan dari [aktif] karena keduanya berbeda arti: "tidak ada
  /// shift" adalah jawaban, "belum sempat bertanya" bukan. Penanda
  /// "buka shift dulu" hanya boleh muncul kalau jawabannya memang sudah
  /// datang — kalau tidak, kasir yang jaringannya lambat disuruh membuka
  /// shift yang sebetulnya sudah dibukanya.
  bool _diketahui = false;

  DateTime? get dibuka => _dibuka;
  bool get aktif => _dibuka != null;
  bool get diketahui => _diketahui;

  /// Menanyakan ulang ke server.
  ///
  /// [emailSaya] dipakai memastikan shiftnya memang milik orang ini:
  /// Owner dan Admin bisa MEMBACA shift siapa pun, dan penanda "shiftmu
  /// masih berjalan" yang muncul untuk shift orang lain adalah ajakan
  /// menutup sesuatu yang bukan haknya.
  Future<void> segarkan(String? restoId, String? emailSaya) async {
    if (restoId == null || emailSaya == null) {
      _set(null);
      return;
    }
    try {
      final shift = await _repo.terbuka(restoId);
      final milikSaya = shift != null &&
          shift.employeeEmail.toLowerCase() == emailSaya.toLowerCase();
      _set(milikSaya ? shift.openedAt : null);
    } catch (_) {
      // Gagal bertanya tidak berarti shiftnya berakhir. Penanda yang
      // hilang karena jaringan buruk mengajari orang mengabaikannya.
    }
  }

  /// Dipanggil layar Shift Kasir sesudah membuka atau menutup, supaya
  /// penandanya tidak menunggu pemuatan berikutnya.
  void tandaiTutup() => _set(null);

  void _set(DateTime? nilai) {
    final berubah = _dibuka != nilai || !_diketahui;
    _dibuka = nilai;
    _diketahui = true;
    if (berubah) notifyListeners();
  }
}
