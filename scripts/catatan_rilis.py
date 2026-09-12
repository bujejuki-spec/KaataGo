#!/usr/bin/env python3
"""Menyusun badan pengumuman rilis dari CATATAN-RILIS.md.

Mencetak JSON siap kirim ke fungsi publish-release. Versi yang belum
punya bagiannya tetap menghasilkan JSON yang sah — hanya tanpa `body`,
sehingga fungsinya memakai kalimat umumnya sendiri. Menahan rilis karena
catatannya belum ditulis akan menukar satu ketidaknyamanan kecil dengan
satu rilis yang gagal terbit.
"""

import json
import sys


def poin_untuk(isi: str, versi: str) -> list[str]:
    """Butir-butir di bawah judul `## <versi>`, satu butir satu baris.

    Catatannya ditulis terbungkus pada lebar berkas supaya enak dibaca di
    editor. Pembungkusan itu tidak boleh ikut terkirim: di layar ponsel
    teksnya dibungkus ulang oleh lebar layar, sementara patahan baris
    dari berkasnya tetap tinggal di tengah kalimat — dan yang terbaca
    adalah paragraf yang patah di tempat acak.

    Jadi sambungan barisnya disatukan kembali di sini, dan tiap butir
    keluar sebagai satu baris utuh.
    """
    poin: list[str] = []
    kutip = False
    for baris in isi.splitlines():
        if baris.startswith("## "):
            # Judul berikutnya menutup bagian ini. Tanpa ini, catatan
            # versi lama ikut terbawa ke pengumuman versi baru.
            if kutip:
                break
            kutip = baris[3:].strip() == versi
            continue
        if not kutip or not baris.strip():
            continue

        bersih = baris.strip()
        if bersih.startswith(("- ", "* ")):
            poin.append(bersih)
        elif poin:
            # Sambungan butir sebelumnya, bukan butir baru.
            poin[-1] = f"{poin[-1]} {bersih}"
        else:
            poin.append(bersih)
    return poin


def main() -> None:
    path, versi = sys.argv[1], sys.argv[2]
    try:
        isi = open(path).read()
    except OSError:
        print(json.dumps({"version": versi}))
        return

    poin = poin_untuk(isi, versi)
    if not poin:
        print(json.dumps({"version": versi}))
        return

    pesan = "Versi baru KaataGo sudah bisa diunduh. Yang berubah:\n\n" + "\n".join(poin)
    print(json.dumps({"version": versi, "body": pesan}))


if __name__ == "__main__":
    main()
