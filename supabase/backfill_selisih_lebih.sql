-- KaataGo — melahirkan baris kerja untuk selisih lebih yang terlanjur
-- ditutup sebelum cash_variance_lebih.sql dipasang.
--
-- Jalankan SETELAH cash_variance_lebih.sql. Aman diulang.
--
-- Sampai commit itu, trigger penutup shift hanya membuat baris
-- `cash_variances` untuk selisih KURANG. Shift yang lacinya lebih tetap
-- dijurnal — kreditnya ada di 2100003 — tapi tidak punya baris yang
-- bisa ditelusuri, jadi layar Shift Kasir tidak menampilkannya dan
-- Finance tidak punya tombol untuk menutupnya.
--
-- Yang diperbaiki di sini HANYA baris kerjanya. Jurnalnya sengaja tidak
-- disentuh: ia sudah benar dan sudah ada. Menulis ulang jurnal yang
-- sudah tercatat berarti menghitung uang yang sama dua kali.

begin;

insert into cash_variances (
  resto_id, shift_id, employee_email, employee_name,
  amount, note, kind, created_at)
select
  s.resto_id,
  s.id,
  s.employee_email,
  s.employee_name,
  s.difference,
  s.note,
  'lebih',
  coalesce(s.closed_at, now())
from cashier_shifts s
where s.closed_at is not null
  and coalesce(s.difference, 0) > 0
on conflict (shift_id) do nothing;

commit;

-- Sesudahnya, untuk melihat apa saja yang baru lahir:
--
--   select v.created_at, v.employee_name, v.amount, v.status
--   from cash_variances v
--   where v.kind = 'lebih' and v.status = 'open'
--   order by v.created_at desc;
