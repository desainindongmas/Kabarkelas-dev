# KabarKelas untuk Kepala Sekolah — Panduan Pilot Detail

Untuk kepala sekolah & admin sekolah yang menjadi pilot KabarKelas.

## 1. Peran Anda di sistem

Sebagai `principal` atau `school_admin` Anda mendapat semua kemampuan guru,
plus:

| Kemampuan | Modul | Keterangan |
|---|---|---|
| Terbitkan pengumuman | Pengumuman | Judul + isi → langsung tampil untuk semua peran |
| Setujui/tolak izin guru | Izin guru | Lihat alasan & tanggal, klik Setujui/Tolak |
| Buat tugas & kuis | Tugas, Kuis | Untuk kelas/mapel mana pun di sekolah |
| Input nilai tugas/kuis | Tugas, Kuis | Pilih tugas → siswa → nilai → simpan |
| Catat P5/Tahfizh | P5 & Tahfizh | Per siswa, skor 0–100 |
| Atur & jalankan EWS | Pratinjau pendampingan siswa | Aktifkan aturan, scan harian, tindak lanjut peringatan |
| Kelola rapor & remedial | AKADEMIK menu | Buat paket rapor, atur kebijakan nilai |

Akun pilot demo: `pilot.kepala@kabarkelas.dev` (principal),
`pilot.admin@kabarkelas.dev` (school_admin) — password
`PilotKabarKelas2026!`.

## 2. Alur kerja yang disarankan untuk pilot

**Minggu 1 — eksplorasi (±30 menit)**
1. Masuk → dashboard menampilkan ringkasan + modul pilot.
2. Buka tiap modul: Jadwal, Pengumuman, Izin guru, Tugas, Kuis, P5.
3. Terbitkan 1 pengumuman percobaan → minta guru/orang tua pilot cek.

**Minggu 2 — pakai nyata pada data sintetis**
1. Minta guru pilot input nilai tugas & observasi karakter.
2. Setujui 1 izin guru percobaan (atau minta guru mengajukan dulu).
3. Jalankan EWS scan → baca sinyal → catat tindak lanjut.
4. Bila rapor sudah diisi guru, terbitkan paket rapor kelas percobaan.

**Sepanjang pilot**
- Rutin cek modul Izin guru & Pengumuman.
- Kumpulkan masukan guru/orang tua → catat di form feedback.

## 3. EWS (Early Warning System) — cara pakai

1. Buka **Pratinjau pendampingan siswa (EWS)** → tombol muat.
2. Sistem menampilkan sinyal akademik (rata-rata < 70%, min. 2 nilai) dan
   sinyal kehadiran (≥3 tidak hadir/30 hari).
3. Sebagai kepala sekolah Anda bisa:
   - **Aktifkan aturan** akademik & absensi (sekali saja).
   - **Jalankan deteksi hari ini** — mencatat peringatan baru.
   - **Tindak lanjut** tiap peringatan: mulai tinjauan → selesai/tutup,
     dengan catatan wajib.

Peringatan adalah awal percakapan pendampingan — bukan label untuk siswa.

## 4. Batasan yang perlu diketahui

- **Jadwal pelajaran belum bisa diinput dari UI** — data jadwal saat ini
  contoh. Akan ditambah di rilis berikutnya.
- **Input kehadiran harian belum ada** — sinyal absensi EWS baru bekerja
  bila data kehadiran diisi (saat ini manual via database oleh admin).
- **Tidak ada notifikasi realtime** — refresh halaman untuk data terbaru.
- **Satu akun = satu peran** — guru dan kepala sekolah perlu akun masing-masing.
- Semua data pilot **sintetis** — jangan input data siswa asli.

## 5. Akun & keamanan

- Password pilot bersifat bersama untuk demo — **wajib diganti** sebelum
  pilot sekolah nyata (admin akan reset per orang).
- Jangan bagikan password di grup umum; satu akun per perangkat idealnya.
- Lupa password → hubungi admin pilot untuk reset via dashboard Supabase.

## 6. Feedback yang paling berguna

Saat menemui masalah atau punya ide, catat:
1. Peran akun yang dipakai
2. Halaman/modul yang dibuka
3. Langkah yang dilakukan (klik apa)
4. Yang terjadi vs yang diharapkan
5. Tangkapan layar (data sintetis, aman)

Kirim ke kontak admin pilot.
