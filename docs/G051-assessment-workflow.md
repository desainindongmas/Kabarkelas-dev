# G0.5.1 — Alur penilaian dan rapor (implementasi development)

## Pembagian kewenangan
- **Nilai pembelajaran**: guru yang ditugaskan ke kelas mencatat nilai awal dan remedial, memperbaiki kesalahan input disertai alasan, dan memfinalisasi sendiri. Tidak ada kewajiban kepala sekolah menyetujui setiap nilai.
- **Kebijakan sekolah**: kepala sekolah memilih best_score (default), latest_score, atau best_capped, dan after_release atau report_only. Perubahan menyimpan versi baru; snapshot lama tidak dihitung ulang.
- **Rapor kelas/semester**: kepala sekolah membuat paket rapor dan menunjuk wali kelas dari guru yang ditugaskan. Guru kelas finalisasi data → wali kelas review → kepala sekolah mengesahkan → kepala sekolah/wali kelas merilis. Status disimpan bersama jejak audit. Snapshot rapor dibuat per siswa agar wali hanya mendapat rapor anak terverifikasi.

## Koreksi dan remedial
- Nilai awal dan tiap percobaan remedial disimpan terpisah di assessment_attempts.
- Koreksi tidak dianggap remedial: dicatat sebagai assessment_corrections berisi nilai sebelum, sesudah, alasan, waktu dan identitas guru.
- Nilai olahan dihitung di server menurut kebijakan sekolah; remedial lebih rendah tidak mengurangi skor jika best_score; latest_score dapat mengurangi skor.
- Finalisasi guru menciptakan assessment_releases baru yang tidak dapat di-update atau dihapus. Revisi setelah rilis membuat versi baru; versi lama tetap ada dan tidak mengubah rapor yang sudah disahkan.
- Jika visibility report_only, penilaian masuk rapor tetapi tidak ditampilkan sebagai nilai harian kepada orang tua.
- G0.5 legacy grade Nadia Simulasi bernilai 82 yang sudah Published tetap tidak dimodifikasi. Grade historis tanpa attempts dapat tetap memakai workflow lama; grade dengan attempts menolak transisi lama dan menyembunyikan tombolnya.

## Pengamanan
- Identitas dari auth.uid(), bukan parameter aktor atau metadata pengguna.
- Akses guru membutuhkan membership aktif, class assignment, enrollment dan sekolah/tenant aktif.
- Rapor resmi disahkan oleh principal pada tingkat kelas/periode, bukan nilai individu.
- Parent read hanya jika hubungan wali-siswa verified dan report/release sudah dipublikasikan.
- Foundation role tidak mendapat akses individual melalui RPC baru.
- Tabel assessment/release/rapor baru menggunakan FORCE RLS, tanpa grant langsung kepada anon/authenticated.
- Snapshot rilis dan rapor tidak bisa UPDATE/DELETE/TRUNCATE; administrator database dengan izin DDL tetap dapat mengubah struktur, sehingga ini bukan WORM di luar kontrol database.

## Migrasi dan verifikasi
- Migration SQL dalam supabase/migrations diselaraskan dengan versi pada Supabase development qajgoqtipvsstqlcyfro.
- Tidak ada migrasi yang menimpa nilai G0.5 lama.
- Pengujian otomatis: npm run check; npm test; npm run build; npm run test:db; npm run test:ui. CI wajib hijau sebelum merge.
- Tes SQL mencakup penugasan guru, pemisahan nilai awal/remedial, koreksi beralasan, kebijakan latest_score, rapor ditinjau/ditandatangani/dirilis, audit, pembacaan guardian terverifikasi dan penolakan guardian pending, kompatibilitas workflow lama, revisi nilai yang telah dirilis.
- Pengujian browser menggunakan HTTP/Auth stub. Login browser terhadap Supabase nyata dan Cloudflare harus diuji setelah deployment dengan data fiktif.

## Batas rilis
Sebelum go-live data siswa nyata, lakukan security review, tes end-to-end dengan pengguna autentikasi nyata, monitoring dan backup/restore. Jalur koreksi versi rapor baru tersedia setelah paket sebelumnya released; tidak mengubah snapshot yang telah disahkan. UI pembuatan master assessment belum termasuk G0.5.1; gunakan data fiktif pengujian yang disiapkan admin.
