import '../widgets/app_toast.dart';
import 'merchant_info_screen.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/table_session_provider.dart';
import '../theme.dart';
import '../utils/resto_location.dart';
import '../widgets/resto_logo_avatar.dart';

/// Batas sebuah resto masih disebut "terdekat".
///
/// Lima kilometer. Sepuluh terlalu jauh untuk kata "terdekat": di jam
/// sibuk itu setengah jam perjalanan, dan daftar yang menjanjikan
/// kedekatan lalu menawarkan tempat sejauh itu lebih buruk daripada
/// tidak menjanjikan apa pun.
///
/// Yang di luar radius tidak hilang — mereka tetap ada di tab Semua.
/// Yang dipersempit hanya janjinya, bukan pilihannya.
const _nearbyRadiusKm = 5.0;

/// Resto yang bisa dibuka pelanggan tanpa memindai QR meja.
///
/// Terbagi dua: yang dekat dari tempatnya berdiri, dan seluruhnya. Yang
/// dicari orang lapar hampir selalu yang pertama — tapi yang kedua tetap
/// harus ada, karena dia mungkin sedang memesan untuk nanti, untuk orang
/// lain, atau dari tempat yang lokasinya tidak diizinkan dibaca.
class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  final _repo = RestaurantRepository();
  final _searchCtrl = TextEditingController();

  List<Restaurant> _restaurants = [];
  Position? _me;
  bool _loading = true;

  /// Kenapa jaraknya tidak bisa dihitung, atau null kalau bisa.
  ///
  /// Ditampilkan apa adanya, bukan disembunyikan: daftar "terdekat" yang
  /// diam-diam kosong terlihat seperti tidak ada resto di dekat sini,
  /// padahal yang terjadi cuma izin lokasi belum diberikan.
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _repo.getAllActive();
    if (!mounted) return;
    setState(() {
      _restaurants = all;
      _loading = false;
    });
    _locate();
  }

  /// Lokasinya diminta setelah daftarnya tampil, bukan sebelum.
  ///
  /// Meminta izin lebih dulu berarti layar kosong yang menahan orang di
  /// depan dialog izin sebelum dia sempat melihat ada apa di sini. Dan
  /// kalau izinnya ditolak, daftarnya toh tetap berguna.
  Future<void> _locate() async {
    try {
      final me = await currentPosition();
      if (!mounted) return;
      setState(() {
        _me = me;
        _locationNote = null;
      });
    } on LocationFailure catch (e) {
      if (!mounted) return;
      setState(() => _locationNote = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationNote = 'Lokasi tidak bisa dibaca.');
    }
  }

  /// Jarak garis lurus dalam kilometer, atau null kalau salah satunya
  /// tidak diketahui.
  ///
  /// Garis lurus, bukan jarak tempuh — yang dijawab angka ini adalah
  /// "kira-kira sejauh apa", bukan "berapa lama sampai". Untuk memilih
  /// di antara beberapa resto itu sudah cukup, dan menghitung rute
  /// sungguhan berarti memanggil layanan berbayar untuk tiap baris di
  /// daftar ini.
  double? _distanceKm(Restaurant resto) {
    final me = _me;
    if (me == null || !resto.hasLocation) return null;
    return Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          resto.latitude!,
          resto.longitude!,
        ) /
        1000;
  }

  String _distanceText(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

  /// Yang cocok dengan pencarian, terurut dari yang paling dekat.
  ///
  /// Yang tidak diketahui lokasinya ditaruh paling belakang, bukan
  /// dianggap berjarak nol. Resto yang belum mengisi titik lokasinya
  /// bukan resto yang ada di sebelah kita — dan menaruhnya di puncak
  /// daftar "terdekat" persis membalik arti daftar itu.
  List<Restaurant> get _matching {
    final q = _searchCtrl.text.trim().toLowerCase();
    final matched = q.isEmpty
        ? [..._restaurants]
        : _restaurants
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                r.address.toLowerCase().contains(q))
            .toList();

    if (_me == null) return matched;

    matched.sort((a, b) {
      // Yang tutup selalu di bawah, sedekat apa pun. Tempat terdekat
      // yang sedang tutup bukan tempat yang bisa dipilih — menaruhnya
      // di puncak daftar berarti baris teratas justru satu-satunya yang
      // tidak berguna sekarang.
      final ta = _tutup(a);
      final tb = _tutup(b);
      if (ta != tb) return ta ? 1 : -1;

      final da = _distanceKm(a);
      final db = _distanceKm(b);
      if (da == null && db == null) return a.name.compareTo(b.name);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return matched;
  }

  /// Yang dekat, terurut dari yang paling dekat.
  List<Restaurant> get _nearby {
    if (_me == null) return const [];
    final withDistance = <(Restaurant, double)>[];
    for (final r in _matching) {
      final km = _distanceKm(r);
      if (km != null && km <= _nearbyRadiusKm) withDistance.add((r, km));
    }
    withDistance.sort((a, b) {
      final ta = _tutup(a.$1);
      final tb = _tutup(b.$1);
      if (ta != tb) return ta ? 1 : -1;
      return a.$2.compareTo(b.$2);
    });
    return withDistance.map((e) => e.$1).toList();
  }

  /// Sedang tutup menurut jam bukanya sendiri.
  ///
  /// Merchant yang belum mengisi jam bukanya tidak dianggap tutup —
  /// daftar kosong berarti belum diisi, bukan berarti tutup selamanya,
  /// dan menutup pintunya karena setelan yang belum disentuh adalah
  /// kehilangan pesanan yang tidak pernah dia sadari.
  bool _tutup(Restaurant resto) =>
      resto.openingHours.adaIsinya &&
      !resto.openingHours.bukaPada(DateTime.now());

  Future<void> _select(Restaurant resto) async {
    if (_tutup(resto)) {
      // Dihentikan di sini, bukan dibiarkan masuk lalu gagal saat
      // checkout. Yang sudah memilih menu dan menyusun keranjang lalu
      // ditolak di ujung akan mengira aplikasinya yang rusak.
      AppToast.show(
        context,
        'Merchant lagi tutup nih, silakan pilih merchant lainnya dulu ya.',
        isError: true,
      );
      return;
    }
    await context.read<TableSessionProvider>().setResto(resto.id);
    if (!mounted) return;
    // Pola yang sama dengan ScanTableScreen: kembali ke layar customer,
    // yang sekarang menampilkan menu resto pilihannya.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final matching = _matching;
    final nearby = _nearby;
    final searching = _searchCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Pilih Merchant'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama merchant atau alamat',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_searchCtrl.clear),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('Belum ada merchant terdaftar.'))
              : matching.isEmpty
                  ? _EmptySearch(query: _searchCtrl.text.trim())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        children: [
                          if (nearby.isNotEmpty) ...[
                            _SectionHeader(
                              icon: Icons.near_me_outlined,
                              title: 'Terdekat',
                              subtitle: 'Dalam ${_nearbyRadiusKm.round()} km dari kamu',
                            ),
                            for (final r in nearby) _card(r),
                            const SizedBox(height: 18),
                          ] else if (_locationNote != null) ...[
                            _LocationNote(
                              message: _locationNote!,
                              onRetry: _locate,
                            ),
                            const SizedBox(height: 14),
                          ],
                          _SectionHeader(
                            icon: Icons.storefront_outlined,
                            title: 'Semua Merchant',
                            subtitle: _me == null
                                ? '${matching.length} merchant'
                                : '${matching.length} merchant · terdekat dulu',
                          ),
                          // Yang dekat tetap ikut muncul di sini. Daftar
                          // "semua" yang diam-diam menyembunyikan
                          // sebagian isinya akan membuat orang mengira
                          // restonya hilang saat dia menggulir mencari
                          // yang tadi dia lihat di atas.
                          for (final r in matching) _card(r),
                        ],
                      ),
                    ),
    );
  }

  Widget _card(Restaurant resto) {
    final km = _distanceKm(resto);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: RestoLogoAvatar(logoBase64: resto.logoBase64),
        title: Row(
          children: [
            Flexible(
              child: Text(resto.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (_tutup(resto)) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Tutup',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.red),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resto.address.isEmpty ? 'Alamat belum diisi' : resto.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (km != null) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.near_me, size: 12, color: KaataTheme.brand),
                  const SizedBox(width: 4),
                  Text(
                    _distanceText(km),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: KaataTheme.brand,
                    ),
                  ),
                ],
              ),
            ],
            // Fasilitasnya berwarna dan berbentuk kartu kecil, bukan
            // teks abu-abu sebaris.
            //
            // Ini yang paling sering menentukan pilihan — ada AC atau
            // tidak, boleh merokok atau tidak, aman untuk anak atau
            // tidak — dan keterangan yang sepucat alamat akan terlewat
            // oleh mata yang sedang menyapu daftar.
            if (resto.facilities.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in resto.facilities.take(4))
                    _FasilitasChip(nama: f),
                  // "+6" yang tidak bisa dibuka cuma memberi tahu ada
                  // yang disembunyikan tanpa cara melihatnya — dan yang
                  // disembunyikan itu bisa jadi justru yang dicari.
                  if (resto.facilities.length > 4)
                    InkWell(
                      onTap: () => _bukaInfo(context, resto),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: KaataTheme.brandOf(context)
                                  .withOpacity(0.5)),
                        ),
                        child: Text(
                          '+${resto.facilities.length - 4} lainnya',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: KaataTheme.brandOf(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        isThreeLine: km != null || resto.facilities.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ikut ditawarkan di sini, bukan hanya setelah masuk:
            // memilih resto sering justru soal "yang mana yang paling
            // dekat".
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Info merchant',
              onPressed: () => _bukaInfo(context, resto),
            ),
            if (resto.hasLocation)
              IconButton(
                icon: const Icon(Icons.directions_outlined),
                tooltip: 'Buka di Google Maps',
                onPressed: () => openInMaps(
                  resto.latitude!,
                  resto.longitude!,
                  label: resto.name,
                ),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _select(resto),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: KaataTheme.brand),
          const SizedBox(width: 7),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationNote extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LocationNote({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me_disabled_outlined, size: 18, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Merchant terdekat belum bisa ditampilkan. $message',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba Lagi')),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final String query;

  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 52, color: KaataTheme.borderOf(context)),
            const SizedBox(height: 12),
            Text(
              'Tidak ada merchant bernama "$query".',
              textAlign: TextAlign.center,
              style: TextStyle(color: KaataTheme.mutedOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu fasilitas, sebagai kartu kecil berwarna.
///
/// Warnanya diambil dari namanya sendiri, bukan diacak tiap kali
/// digambar: fasilitas yang sama harus berwarna sama di seluruh daftar,
/// supaya mata bisa mengenalinya tanpa membaca ulang tiap barisnya.
class _FasilitasChip extends StatelessWidget {
  final String nama;

  const _FasilitasChip({required this.nama});

  static const _palet = [
    Color(0xFF10B981),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF8B5CF6),
  ];

  static const _ikon = {
    'ac': Icons.ac_unit,
    'smoking area': Icons.smoking_rooms_outlined,
    'kids friendly': Icons.child_friendly_outlined,
    'live music': Icons.music_note_outlined,
    'wifi gratis': Icons.wifi,
    'parkir luas': Icons.local_parking_outlined,
    'mushola': Icons.mosque_outlined,
    'toilet': Icons.wc_outlined,
    'colokan listrik': Icons.power_outlined,
    'ramah difabel': Icons.accessible_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final warna = _palet[nama.toLowerCase().hashCode.abs() % _palet.length];
    final ikon = _ikon[nama.toLowerCase()];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.13),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: warna.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 12, color: warna),
            const SizedBox(width: 4),
          ],
          Text(
            nama,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}


/// Membuka Info Merchant — alamat, fasilitas lengkap, jam buka, dan
/// penilaian orang yang sudah ke sana.
void _bukaInfo(BuildContext context, Restaurant merchant) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MerchantInfoScreen(merchant: merchant)),
  );
}
