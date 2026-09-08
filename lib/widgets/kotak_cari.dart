import 'package:flutter/material.dart';

/// Kotak pencarian yang bentuknya sama di seluruh daftar panjang.
///
/// Ditulis sekali karena sudah dipakai lima layar, dan kotak cari yang
/// disalin akan berbeda tinggi, berbeda ikonnya, dan berbeda pula
/// perilakunya saat dikosongkan — perbedaan yang tidak pernah disengaja
/// tapi selalu terlihat.
class KotakCari extends StatelessWidget {
  final TextEditingController controller;
  final String petunjuk;
  final ValueChanged<String> onUbah;

  /// Jarak di sekelilingnya. Beberapa layar sudah punya jarak sendiri
  /// dari daftarnya, jadi tidak semuanya butuh yang sama.
  final EdgeInsets padding;

  const KotakCari({
    super.key,
    required this.controller,
    required this.petunjuk,
    required this.onUbah,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        onChanged: onUbah,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: petunjuk,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          // Tombol bersihnya hanya muncul saat ada yang bisa dibersihkan.
          // Tombol yang selalu ada tapi kadang tidak melakukan apa-apa
          // mengajari orang untuk berhenti mempercayainya.
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Bersihkan',
                  onPressed: () {
                    controller.clear();
                    onUbah('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Apakah sebuah baris cocok dengan kata yang dicari.
///
/// Cocok kalau salah satu kolomnya mengandung katanya — bukan harus
/// diawali. Yang mencari "geprek" biasanya tidak ingat bahwa namanya
/// dimulai dengan "Ayam".
bool cocokCari(String kata, List<String?> kolom) {
  final cari = kata.trim().toLowerCase();
  if (cari.isEmpty) return true;
  for (final k in kolom) {
    if (k != null && k.toLowerCase().contains(cari)) return true;
  }
  return false;
}
