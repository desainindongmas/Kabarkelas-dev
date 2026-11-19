# KabarKelas — Panduan Pilot (1 halaman)


Versi per peran: [Orang tua](PILOT-onboarding-ortu.md) · [Kepala sekolah](PILOT-onboarding-kepala.md)
Terima kasih sudah mau mencoba KabarKelas. Panduan ini untuk guru, kepala
sekolah, dan orang tua yang ikut pilot.

## Apa itu KabarKelas?

Satu ruang digital untuk pantau perkembangan siswa: nilai & tugas, rapor,
Early Warning System (peringatan siswa yang perlu perhatian), jadwal,
pengumuman, dan penilaian P5/Tahfizh.

**Penting:** semua data di pilot ini adalah **data sintetis** (siswa, nilai,
dan nama hanyalah contoh). Jangan masukkan data siswa asli.

## Cara masuk

1. Buka https://kabarkelas-dev.pages.dev di browser (Chrome/Edge/Safari).
2. Masuk dengan email & password yang diberikan admin pilot.
3. Jika punya lebih dari satu penugasan, pilih unit sekolah yang dimaksud.

## Akun pilot demo (untuk uji coba internal)

| Peran | Email | Password |
|---|---|---|
| Guru | pilot.guru@kabarkelas.dev | PilotKabarKelas2026! |
| Kepala sekolah | pilot.kepala@kabarkelas.dev | PilotKabarKelas2026! |
| Admin sekolah | pilot.admin@kabarkelas.dev | PilotKabarKelas2026! |
| Orang tua | pilot.ortu@kabarkelas.dev | PilotKabarKelas2026! |

## Apa yang bisa dilakukan tiap peran

**Guru**
- Lihat penilaian akademik, kelola nilai awal & remedial, finalisasi penilaian
- Observasi kompetensi & karakter siswa (skala 1–4)
- Beri tugas & jadwalkan kuis, input nilainya
- Catat penilaian P5/Tahfizh
- Ajukan izin (sakit/pribadi/resmi)
- Lihat jadwal pelajaran, pengumuman, EWS siswa binaannya

**Kepala sekolah / Admin sekolah**
- Semua modul guru, plus:
- Setujui/tolak izin guru
- Terbitkan pengumuman sekolah
- Atur aturan EWS & jalankan deteksi, kelola rapor & kebijakan remedial

**Orang tua**
- Lihat nilai, rapor, dan nilai harian yang **sudah diterbitkan** guru
- Lihat perkembangan akademik & jaring kompetensi anak yang terverifikasi
- Lihat tugas, kuis, jadwal, pengumuman, dan P5 anak

## Alur kerja contoh

1. Guru input nilai tugas/kuis → tercatat langsung.
2. Kepala sekolah terbitkan pengumuman → semua peran melihatnya.
3. Guru ajukan izin → kepala sekolah setujui → status berubah.
4. Orang tua hanya melihat data yang sudah dirilis — tidak bisa mengubah.

## Yang belum tersedia di pilot ini (jujur)

- Input kehadiran/absensi harian (EWS membaca data absensi bila ada)
- Pembuatan jadwal pelajaran dari UI (jadwal saat ini data contoh)
- Gerbang sekolah & pengajuan izin untuk orang tua
- Notifikasi realtime (refresh halaman untuk data terbaru)
- Multi-guru dalam satu akun (satu akun = satu peran per sekolah)

## Kalau menemukan masalah

Catat: halaman yang dibuka, peran akun, apa yang diklik, dan apa yang
seharusnya terjadi. Kirim ke kontak admin pilot. Sertakan tangkapan layar
bila bisa — semua data sintetis jadi aman dibagikan.

## Tips

- Tekan tombol modul (mis. "Tugas") untuk memuat datanya — data tidak
  dimuat otomatis.
- Setelah mengubah data, modul dimuat ulang sendiri.
- Akun pilot boleh dipakai bersama untuk demo; untuk pilot sekolah nyata
  akan dibuatkan akun per orang.
