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

## Implemented G0.6 MVP (development)
- Read-only academic and published attendance previews for teacher/principal, no guardian/foundation visibility.
- Principal-only activation of versioned academic and attendance rules. On-demand scan uses unique alert keys per student, rule version, date to avoid duplicates.
- Teacher/principal-scoped alert inbox and notes-based follow-up workflow: open → under_review → resolved/dismissed, reopening with reason. Every transition creates an ews_followups audit entry.
- No automatic dispatch to parents; threshold presets 70%, 2 assessments, or 3 absences in 30 days are **demo values**, not official education standards.
- Current scan requires principal clicking Run; scheduled unattended scanning is outside this MVP and must not be implied.
- Automated tests cover missing data, permissions, low-score creation, duplicate scan, notes, and status replay; Playwright uses mocked Auth; real browser with school accounts remains an after-deploy smoke test.
- Existing G0.5.1 data/snapshots are not mutated by detection. No real-student data intended in this environment.
