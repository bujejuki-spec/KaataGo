import 'package:flutter/material.dart';

import '../theme.dart';

/// Judul bagian yang bisa dilipat, berikut satu tombol tindakan di
/// ujung kanannya.
///
/// Dipakai Saldo & Pengeluaran dan Saldo Perusahaan. Dua layar yang
/// menyusun daftar dengan cara yang sama tapi memakai widget berbeda
/// akan berpisah bentuknya pada perubahan berikutnya — dan yang
/// terlihat orang adalah dua layar yang tampak dibuat di aplikasi yang
/// berbeda.
class JudulBagian extends StatelessWidget {
  final String title;
  final bool open;
  final int count;
  final VoidCallback onToggle;
  final Widget action;

  const JudulBagian({
    super.key,
    required this.title,
    required this.open,
    required this.count,
    required this.onToggle,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                  const SizedBox(width: 4),
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  // Jumlahnya disebut justru saat tertutup: bagian yang
                  // dilipat tidak boleh terlihat sama dengan bagian yang
                  // memang kosong.
                  if (!open && count > 0) ...[
                    const SizedBox(width: 6),
                    Text('($count)',
                        style: TextStyle(
                            fontSize: 12, color: KaataTheme.mutedOf(context))),
                  ],
                ],
              ),
            ),
          ),
        ),
        action,
      ],
    );
  }
}

class TombolPil extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const TombolPil({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
