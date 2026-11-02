# G0.8.5 — Audit koreksi dan pencabutan observasi

Guru penulis observasi dengan penugasan kelas aktif dapat mengoreksi skor serta bukti, atau mencabut observasi. Semua tindakan membutuhkan alasan sedikitnya 8 karakter dan revisi yang cocok (optimistic locking); pembaruan serta pencatatan audit dilakukan dalam satu transaksi. Status `withdrawn` tetap tercatat untuk audit, tetapi tidak dibaca oleh API grafik orang tua yang hanya menampilkan `published`.

Batasan: belum ada kemampuan mengembalikan observasi yang sudah dicabut, review kepala sekolah atau UI pemeriksaan log audit. Tes Playwright memakai mock RPC; belum ada smoke test login nyata Cloudflare. Migrasi hanya pada Supabase development.
