# G0.8.2 — Grafik Akademik Orang Tua

Grafik perkembangan adalah hasil API `kabarkelas_guardian_academic_trends`, yang melakukan otorisasi berdasarkan `auth.uid()`, membership guardian aktif dan tautan wali-anak `verified` dalam sekolah terkait. Hanya rilis G0.5.1 dengan status `released` dan nilai historis G0.5 `published` yang ditampilkan, dengan masing-masing nilai dinormalisasi terhadap `max_score` penilaian. Jika versi rilis terbaru belum published, rilis lama tidak dipakai sehingga fail-closed. Grafik memisahkan anak dan mata pelajaran serta menggunakan urutan waktu rilis, bukan urutan capaian kurikulum.

Tampilan G0.8.2 adalah grafik nilai berdasarkan penilaian, bukan grafik jaring karakter/kompetensi dari mockup. Tidak ada data karakter yang layak digunakan sebagai angka, sehingga grafik karakter belum ditampilkan. Frontend memuat grafik setelah orang tua memilih tombol Muat grafik; kegagalan API tidak digantikan dengan data contoh.

Pengujian: PostgreSQL auth boundary, Playwright dengan mock RPC yang diizinkan, CI repo. Belum ada verifikasi browser login nyata pada Cloudflare setelah merge; jangan gunakan data siswa nyata sebelum keamanan produksi siap.
