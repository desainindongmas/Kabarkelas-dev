# G0.8.1 — Dashboard KPI berbasis data

Tahap pertama dashboard berbasis data nyata. Kartu jumlah siswa/anak menggunakan `kabarkelas_my_students` (guru) dan `kabarkelas_my_role_students` (orang tua/kepala sekolah), sesuai kontrol akses server yang sudah diuji. Kartu EWS guru/kepala sekolah menggunakan `kabarkelas_ews_my_alerts`, menghitung hanya status `open` dan `under_review`. Tidak ada angka dummy atau query tabel publik langsung.

Untuk yayasan belum tersedia endpoint agregat yang aman sehingga aplikasi menyatakan data belum tersedia. Error API menghapus kartu dan menunjukkan status yang jelas, bukan angka nol atau contoh palsu. Data akademik grafik jaring dan karakter belum dibuat karena tidak ada kontrak RPC terverifikasi untuk metrik tersebut.

Pengujian Playwright pada tahap ini menggunakan Supabase RPC/Auth stub, bukan deployment Cloudflare asli. Perlu memeriksa CI dan smoke test login nyata terpisah sebelum siap produksi.
