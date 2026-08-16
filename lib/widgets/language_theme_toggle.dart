import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../providers/app_prefs_provider.dart';
import '../theme.dart';

/// Pemilih bahasa berbendera, dipakai di halaman awal dan di Pengaturan.
///
/// Benderanya emoji, bukan berkas gambar: ikut mengikuti bentuk yang
/// dikenali sistem operasinya, tidak menambah aset yang harus dirawat,
/// dan tidak pernah menjadi kotak kosong saat gagal dimuat.
///
/// Indonesia lebih dulu karena itu bahasa mayoritas pemakainya —
/// urutan pilihan adalah pernyataan tentang siapa yang diutamakan.
class LanguageToggle extends StatelessWidget {
  /// Ringkas untuk halaman awal, melebar untuk layar Pengaturan.
  final bool compact;

  const LanguageToggle({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<AppPrefsProvider>();

    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 'id',
          label: Text(compact ? '🇮🇩 ID' : '🇮🇩  Indonesia'),
        ),
        ButtonSegment(
          value: 'en',
          label: Text(compact ? '🇬🇧 EN' : '🇬🇧  English'),
        ),
      ],
      selected: {prefs.locale.languageCode},
      onSelectionChanged: (v) => prefs.setLocale(Locale(v.first)),
      style: compact
          ? ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 10),
              ),
            )
          : null,
    );
  }
}

/// Pemilih tema: Terang, Gelap, atau ikut setelan HP.
///
/// "Ikuti HP" ada dan menjadi bawaannya karena sebagian besar orang
/// sudah menentukan pilihannya sekali di tingkat sistem — termasuk yang
/// menjadwalkannya berganti sendiri saat malam. Memaksa mereka memilih
/// lagi di sini berarti aplikasi ini yang menyendiri saat semua
/// aplikasi lain di HP-nya berubah.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<AppPrefsProvider>();

    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: ThemeMode.light,
          icon: const Icon(Icons.light_mode_outlined, size: 17),
          label: Text(context.tr('Terang')),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: const Icon(Icons.dark_mode_outlined, size: 17),
          label: Text(context.tr('Gelap')),
        ),
        ButtonSegment(
          value: ThemeMode.system,
          icon: const Icon(Icons.brightness_auto_outlined, size: 17),
          label: Text(context.tr('Ikuti HP')),
        ),
      ],
      selected: {prefs.themeMode},
      onSelectionChanged: (v) => prefs.setThemeMode(v.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// Blok Bahasa + Tampilan untuk layar Pengaturan.
class LanguageThemeSection extends StatelessWidget {
  const LanguageThemeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Bahasa'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        const LanguageToggle(),
        const SizedBox(height: 18),
        Text(context.tr('Tampilan'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        const ThemeToggle(),
        const SizedBox(height: 6),
        Text(
          'Berlaku di perangkat ini saja.',
          style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
        ),
      ],
    );
  }
}

/// Tombol bilah atas yang membuka pilihan bahasa dan tema.
///
/// Untuk hub yang tidak punya menu Pengaturan sendiri — kasir, dapur,
/// super admin, dan halaman pelanggan. Tanpa ini, satu-satunya cara
/// mereka mengganti bahasa setelah masuk adalah keluar akun dulu, dan
/// itu bukan harga yang pantas untuk mengubah tampilan.
class AppearanceIconButton extends StatelessWidget {
  const AppearanceIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.translate),
      tooltip: '${context.tr('Bahasa')} & ${context.tr('Tampilan')}',
      onPressed: () => showAppearanceDialog(context),
    );
  }
}

Future<void> showAppearanceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        '${dialogContext.tr('Bahasa')} & ${dialogContext.tr('Tampilan')}',
        style: const TextStyle(fontSize: 17),
      ),
      content: const SingleChildScrollView(child: LanguageThemeSection()),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(dialogContext.tr('Tutup')),
        ),
      ],
    ),
  );
}
