# G0.8 — Dashboard shell KabarKelas

## Yang dibuat
- Layout dashboard berbasis peran: guru, kepala sekolah, orang tua, yayasan.
- Sidebar modul yang bisa menavigasi blok fungsi yang sudah tersedia.
- Responsif desktop/tablet/mobile, warna teal KabarKelas, kartu, header, dan fokus keyboard.
- Modul penilaian, remedial, rapor, EWS, siswa, kebijakan, serta perpindahan unit tetap menggunakan RPC dan pembatasan akses sebelumnya.

## Keamanan dan kompatibilitas
- Navigasi **bukan** otorisasi: semua operasi tetap divalidasi Supabase pada server.
- Tidak ada penambahan akses siswa untuk yayasan atau orang tua.
- Belum menambah master data dan tidak memodifikasi isi database.
- Tombol aksi tetap terlihat pada modul terkait agar alur tes G0.5.1/G0.6 tidak berubah.

## Batas capaian
Ini fondasi antarmuka, **belum** padanan visual final dari mockup demo. Komponen grafik akademik/karakter, KPI dari API khusus, ilustrasi dan brand assets terkurasi, dashboard yayasan agregat serta sistem desain lanjutan membutuhkan tahap tersendiri. Data tidak dibuat-buat untuk mengisi grafik.

## Uji rilis
- CI: npm run check, npm test, npm run build, npm run test:db, npm run test:ui.
- Playwright menguji shell guru dan layout mobile dengan HTTP/Auth stub, bukan login produksi.
- Live Cloudflare pasca-merge harus diverifikasi secara terpisah.
