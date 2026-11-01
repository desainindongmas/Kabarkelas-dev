# G0.5.1 — Assessment dan Rapor

Status: rancangan perubahan di branch, belum diterapkan ke aplikasi.

- Nilai harian: guru input, koreksi, finalisasi, dan rilis menurut kebijakan sekolah. Kepala sekolah tidak perlu menyetujui tiap nilai.
- Koreksi salah input: simpan alasan serta riwayat sebelum/sesudah; bukan remedial.
- Remedial: simpan percobaan terpisah dari nilai awal, jangan overwrite. Kebijakan nilai terbaik / percobaan terbaru / nilai terbaik dengan batas harus dikonfigurasi dan diberi versi oleh sekolah. Nilai remedial lebih rendah tidak menurunkan hasil jika kebijakan nilai terbaik dipilih.
- Orang tua hanya melihat nilai yang telah dirilis; EWS internal tidak otomatis dibagikan.
- Rapor semester: guru finalisasi nilai, wali kelas memeriksa, pejabat berwenang mengesahkan, lalu rilis rapor bersnapshot.
- Perubahan setelah pengesahan harus menghasilkan versi rapor baru serta audit; versi lama tetap dapat ditelusuri.
- Kontrol akses lintas tenant, sekolah, kelas; simpan audit, revisi optimistis dan tes konkurensi.
- Nilai Nadia Simulasi 82 berstatus published dari G0.5 tidak boleh diubah oleh migrasi baru.

Rencana: (1) model attempt dan kebijakan, (2) API koreksi/remedial dengan otorisasi, (3) kebijakan rilis, (4) workflow rapor, (5) integrasi UI dan tes peran.
