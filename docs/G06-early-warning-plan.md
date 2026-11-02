# G0.6 — Early Warning System (EWS)

## Sasaran produk
Membantu guru mengenali siswa yang perlu ditinjau lebih awal melalui sinyal nilai dan kehadiran, bukan penilaian otomatis tentang kemampuan/karakter siswa. Sinyal wajib dapat dijelaskan serta ditinjau manusia.

## Data dan aturan
- Gunakan hanya nilai penilaian yang telah difinalisasi; ambil skor olahan terakhir dari assessment_releases, atau snapshot published G0.5 sebagai kompatibilitas. Jangan menghitung nilai awal + remedial sebagai dua penilaian berbeda.
- Uji nilai terhadap max_score per assessment. Dua penilaian final minimum, ambang contoh 70%, belum merupakan standar resmi sekolah.
- Kehadiran hanya dari sesi valid yang sudah diselesaikan; izin dan sakit tidak otomatis dianggap absen tanpa keterangan. Data absensi yang belum tersedia **bukan** indikator risiko.
- Perubahan koreksi/remedial menghitung ulang sinyal dari nilai versi terbaru; riwayat tindakan tinjauan tetap dapat diaudit.
- Sinyal tidak boleh dibuat otomatis menjadi catatan negatif atau ditampilkan ke wali/orang tua.

## Akses dan privasi
- Guru melihat hanya siswa kelas yang aktif ditugaskan kepadanya.
- Kepala sekolah melihat hanya siswa dalam sekolahnya untuk tindak lanjut.
- Wali/orang tua tidak melihat raw alert, aturan, alasan internal, atau catatan bimbingan.
- Yayasan hanya statistik agregat dengan ambang kelompok minimum 10 dan supresi kelompok kecil, bukan rekam siswa.
- Validasi identitas melalui auth.uid() dan membership aktif dari server, RLS fail-closed; jangan percaya role atau school_id dari browser.

## Workflow sasaran
Deteksi (tanpa aksi otomatis ke siswa) → guru meninjau → catat langkah pendampingan → buka ulang/tutup dengan alasan → kepala sekolah memonitor tindak lanjut. Tidak ada pengesahan kepala sekolah untuk setiap sinyal, kecuali kebijakan sekolah mengatur intervensi tertentu.

## Tahapan dan gerbang rilis
1. Evaluator pure dan tes edge case di branch (selesai).
2. Migration sumber data dan RPC yang scoped; audit, deduplikasi, dan concurrency.
3. Dashboard guru dan kepala sekolah sesuai design system KabarKelas.
4. Uji lintas tenant, role negative, data hilang, nilai direvisi, absensi dan risiko false positives.
5. Pengujian browser autentikasi asli dengan data fiktif, baru kemudian merge.

Saat ini belum ada EWS production rule yang diaktifkan. Rule `grade_below_threshold_demo` di Supabase development tetap berstatus draft.
