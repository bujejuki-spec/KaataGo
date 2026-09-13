-- KaataGo - pemeriksa konsistensi pembukuan.
--
-- Jalankan SETELAH saldo_perusahaan.sql. Aman diulang.
--
-- Dalam beberapa hari terakhir ditemukan lima kekeliruan yang bentuknya
-- sama persis: satu uang terhitung di dua tempat, atau satu angka
-- berbeda tergantung siapa yang melihatnya. Semuanya ketemu karena ada
-- orang yang kebetulan memperhatikan sebuah angka yang ganjil.
--
-- Itu cara menemukan yang tidak bisa diandalkan. Angka yang salah
-- sebesar seratus ribu memang terlihat; yang salah sebesar dua ribu
-- tidak, dan yang salah pada merchant yang jarang dibuka tidak akan
-- pernah dilihat siapa pun.
--
-- Fungsi ini memeriksa aturan-aturan yang TIDAK BOLEH dilanggar, dan
-- mengembalikan yang dilanggar saja. Tiap barisnya menyebut apa yang
-- salah, seberapa besar, dan ke mana harus melihat.
--
-- Sengaja tidak memperbaiki apa pun. Pemeriksa yang sekaligus
-- membetulkan akan menyembunyikan sebab kesalahannya — dan yang perlu
-- diperbaiki hampir selalu kodenya, bukan barisnya.

begin;

create or replace function periksa_pembukuan(p_resto_id text)
returns table (
  aturan text,
  keterangan text,
  selisih bigint,
  petunjuk text
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_nilai bigint;
begin
  if not (is_super_admin()
          or is_resto_employee(p_resto_id, array['owner', 'finance'])) then
    raise exception 'Hanya Owner dan Finance yang bisa memeriksa pembukuan.';
  end if;

  -- ── 1. Titipan setoran harus habis ────────────────────────────────
  --
  -- Tiap setoran masuk GL Suspense saat diajukan dan keluar saat
  -- diputuskan. Yang tersisa berarti ada setoran yang tidak pernah
  -- diputuskan — atau, lebih buruk, sepasang jurnal yang tidak
  -- berpasangan.
  select coalesce(sum(case when j.entry_type = 'credit'
                           then j.amount else -j.amount end), 0)
    into v_nilai
  from gl_journal_entries j
  join gl_accounts a
    on a.resto_id = j.resto_id
   and a.gl_code = j.gl_code
   and a.payment_method = 'suspense'
  where j.resto_id = p_resto_id
    and coalesce(j.is_reversal, false) = false;

  if v_nilai <> 0 then
    -- Sisa positif wajar kalau memang ada setoran yang menunggu
    -- diperiksa; yang tidak wajar adalah sisa NEGATIF, yang berarti
    -- titipan dilepas tanpa pernah dititipkan.
    aturan := 'GL Suspense Setoran tidak nol';
    keterangan := case when v_nilai > 0
      then 'Ada setoran yang belum diputuskan Finance'
      else 'Titipan dilepas tanpa pernah dicatat masuk' end;
    selisih := v_nilai;
    petunjuk := 'Setor Saldo Cash — periksa yang statusnya Pending';
    return next;
  end if;

  -- ── 2. Titipan cash pickup harus habis ────────────────────────────
  select coalesce(sum(case when j.entry_type = 'credit'
                           then j.amount else -j.amount end), 0)
    into v_nilai
  from gl_journal_entries j
  join gl_accounts a
    on a.resto_id = j.resto_id
   and a.gl_code = j.gl_code
   and a.payment_method = 'cash_pickup'
  where j.resto_id = p_resto_id
    and coalesce(j.is_reversal, false) = false;

  if v_nilai <> 0 then
    aturan := 'GL Cash Pickup tidak nol';
    keterangan := case when v_nilai > 0
      then 'Ada uang yang dijemput dan belum diserahterimakan'
      else 'Serah terima tercatat tanpa pickup yang mendahuluinya' end;
    selisih := v_nilai;
    petunjuk := 'Terima Cash Pickup — periksa yang statusnya Pending';
    return next;
  end if;

  -- ── 3. Saldo perusahaan tidak boleh minus ─────────────────────────
  --
  -- Uang yang dipegang tidak bisa kurang dari nol. Kalau minus, ada
  -- pengeluaran yang dicatat dari kantong yang tidak pernah diisi.
  for aturan, keterangan, selisih, petunjuk in
    select
      'Saldo ' || case a.payment_method when 'company_cash'
        then 'Cash' else 'Bank' end || ' Perusahaan minus',
      'Uang yang dipegang tidak bisa kurang dari nol',
      sum(case when j.entry_type = 'credit' then j.amount else -j.amount end),
      'Saldo Perusahaan — periksa pengeluaran dan setorannya'
    from gl_journal_entries j
    join gl_accounts a
      on a.resto_id = j.resto_id
     and a.gl_code = j.gl_code
     and a.payment_method in ('company_cash', 'company_bank')
    where j.resto_id = p_resto_id
      and coalesce(j.is_reversal, false) = false
    group by a.payment_method
    having sum(case when j.entry_type = 'credit'
                    then j.amount else -j.amount end) < 0
  loop
    return next;
  end loop;

  -- ── 4. Isi laci tidak boleh minus ─────────────────────────────────
  --
  -- Laci yang berbunyi minus berarti ada uang keluar yang tidak pernah
  -- masuk — setoran melebihi penjualan tunai, atau pickup dicatat dua
  -- kali.
  v_nilai := saldo_cash_laci(p_resto_id);
  if v_nilai < 0 then
    aturan := 'Saldo Cash laci minus';
    keterangan := 'Uang keluar laci melebihi yang pernah masuk';
    selisih := v_nilai;
    petunjuk := 'Setor Saldo Cash — periksa setoran dan pickup ganda';
    return next;
  end if;

  -- ── 5. Pesanan lunas non-tunai harus punya barisnya di Saldo Bank ──
  --
  -- Kecuali yang hari ini: tugas jam 5 pagi belum menjalaninya.
  select coalesce(sum(o.total), 0) into v_nilai
  from orders o
  join gl_accounts a
    on a.resto_id = o.resto_id
   and a.payment_method = 'company_bank'
   and coalesce(a.gl_code, '') <> ''
  where o.resto_id = p_resto_id
    and o.payment_status = 'paid'
    and _normalize_payment_method(o.source, o.payment_method)
          in ('qris', 'qris_static', 'transfer')
    and o.created_at < date_trunc('day', now() at time zone 'Asia/Jakarta')
                         at time zone 'Asia/Jakarta'
    and not exists (
      select 1 from gl_journal_entries j
      where j.resto_id = o.resto_id
        and j.reference_type = 'order'
        and j.reference_id = o.id::text
        and j.gl_code = a.gl_code
    );

  if v_nilai > 0 then
    aturan := 'Penjualan non-tunai belum masuk Saldo Bank';
    keterangan := 'Tugas jam 5 pagi belum menjalaninya, atau pernah gagal';
    selisih := v_nilai;
    petunjuk := 'Periksa cron.job jurnal-pendapatan-bank';
    return next;
  end if;

  -- ── 6. Pengeluaran harus punya lawan akunnya ──────────────────────
  --
  -- Tiap pengeluaran menulis dua baris: akun biayanya dan kantong
  -- sumbernya. Yang cuma punya satu berarti pemetaan GL-nya kosong, dan
  -- saldo kantongnya berhenti berkurang tanpa ada yang menyadari.
  select coalesce(sum(e.amount), 0) into v_nilai
  from expenses e
  where e.resto_id = p_resto_id
    and (select count(*) from gl_journal_entries j
         where j.resto_id = e.resto_id
           and j.reference_type = 'expense'
           and j.reference_id = e.id::text
           and coalesce(j.is_reversal, false) = false) < 2;

  if v_nilai > 0 then
    aturan := 'Pengeluaran tanpa lawan akun';
    keterangan := 'Kantong sumbernya tidak ikut berkurang di jurnal';
    selisih := v_nilai;
    petunjuk := 'Mapping GL Account — pastikan akun sumbernya terisi';
    return next;
  end if;

  return;
end;
$fn$;

revoke all on function periksa_pembukuan(text) from public, anon;
grant execute on function periksa_pembukuan(text) to authenticated;

commit;
