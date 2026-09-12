/// Seberapa jauh sebuah peran boleh masuk ke sebuah menu.
///
/// Urutannya menaik, dan itu dipakai: [AksesMenu] menjawab pertanyaan
/// "boleh lihat?" dengan membandingkan tingkatnya, bukan dengan daftar
/// pengecualian yang harus diingat di setiap tempat.
enum TingkatAkses {
  tidakAda('none', 'Tidak Ada'),
  lihat('view', 'Lihat'),
  ubah('edit', 'Lihat & Ubah');

  final String db;
  final String label;

  const TingkatAkses(this.db, this.label);

  static TingkatAkses dari(String? nilai) {
    for (final t in TingkatAkses.values) {
      if (t.db == nilai) return t;
    }
    // Yang tidak dikenali dianggap penuh, bukan tertutup.
    //
    // Baris yang tidak ada juga berarti penuh, jadi nilai asing yang
    // ditafsirkan sebagai "tidak ada" akan mengunci orang dari menunya
    // karena sebuah salah ketik — dan yang terkunci tidak punya cara
    // menebak apa yang terjadi.
    return TingkatAkses.ubah;
  }

  bool get bolehLihat => this != TingkatAkses.tidakAda;
  bool get bolehUbah => this == TingkatAkses.ubah;
}

/// Parameter akses satu menu untuk satu peran di satu resto.
class MenuAccess {
  final String restoId;
  final String role;
  final String menuKey;
  final TingkatAkses tingkat;

  const MenuAccess({
    required this.restoId,
    required this.role,
    required this.menuKey,
    required this.tingkat,
  });

  factory MenuAccess.fromMap(Map<String, dynamic> map) => MenuAccess(
        restoId: map['resto_id'].toString(),
        role: map['role'].toString(),
        menuKey: map['menu_key'].toString(),
        tingkat: TingkatAkses.dari(map['level'] as String?),
      );

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'role': role,
        'menu_key': menuKey,
        'level': tingkat.db,
      };
}
