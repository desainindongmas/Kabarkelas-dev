# Seed data pilot

File: `pilot_seed.sql`

## Cara menjalankan
1. Pastikan migration `20261119000000_g10_pilot_features.sql` dan `20261119000001_g10_pilot_rpcs.sql` sudah diterapkan.
2. Supabase Dashboard → SQL Editor → New query → paste `pilot_seed.sql` → Run.
3. Cek output: `Seed pilot selesai: 35 siswa sintetis, 3 kelas`.
4. Jalankan `verify_seed.sql` untuk konfirmasi.

## Yang dibuat
- 3 kelas: Kelas 5A Uji, Kelas 5B Uji, Kelas 6A Uji
- 35 siswa sintetis (`SIM-001`–`SIM-035`)
- 3 mata pelajaran: Matematika, IPA, Bahasa Indonesia
- Jadwal mingguan contoh, 1 pengumuman pilot

## Yang TIDAK dibuat
- Akun Auth baru (gunakan akun pilot yang sudah ada)
- Data nilai, kehadiran, EWS, rapor (isi manual via UI)

## Keamanan
- Semua nama siswa fiktif.
- Idempotent via `ON CONFLICT DO NOTHING`.
