# Roadmap Pengembangan Fitur Superkickoff

Dokumen ini merangkum rencana implementasi fitur-fitur pilihan untuk game **Superkickoff — Football Career Manager**.

---

## 🏆 Fitur 3: Trofi & Gala Penghargaan Akhir Musim (*Annual Awards Gala*)
> **Status:** ✅ *Completed (Selesai)*

Menghadirkan sistem penghargaan bergengsi akhir musim dan seremoni visual untuk mengapresiasi pencapaian pemain, pelatih, dan klub. Sudah terintegrasi penuh ke alur pergantian musim, Home banner, Club Hub Honours, dan Season History.

### Rincian Fitur:
1. **Penghargaan Individu (*Individual Awards*):**
   - **Ballon d'Or / World Player of the Year:** Diberikan kepada pemain dengan performa keseluruhan terbaik lintas kompetisi (kombinasi rating, gol, assist, dan gelar juara).
   - **Golden Boot (*Sepatu Emas*):** Top skorer dengan torehan gol terbanyak dalam satu musim.
   - **Golden Glove (*Sarung Tangan Emas*):** Kiper terbaik berdasarkan rasio kebobolan terendah, clean sheet terbanyak, dan rating penyelamatan.
   - **Best Young Player (*Pemain Muda Terbaik*):** Pemain berusia $\le$ 21 tahun dengan menit bermain cukup dan rating performa tertinggi.
   - **Manager of the Year (*Pelatih Terbaik*):** Pelatih dengan rasio kemenangan tertinggi dan perolehan trofi terbanyak.
2. **Team of the Year (*Once Ideal / XI Terbaik*):**
   - Penentuan 11 pemain terbaik (1 GK, 4 DEF, 4 MID / 3 MID, 2-3 ATT) dari liga berdasarkan rating match sepanjang musim.
   - Ditampilkan dengan formasi visual di atas lapangan hijau.
3. **Layar Gala Penghargaan (*Annual Awards Ceremony Screen*):**
   - Transisi interaktif di akhir musim sebelum musim baru dimulai.
   - Kartu penghargaan mewah beranimasi, efek emas/glamour, panggung pemenang, dan dialog ringkasan musim (*Season Recap*).
4. **Kabinet Penghargaan & Riwayat (*Awards Showcase & History*):**
   - Tersimpan di database dan dapat dilihat kembali kapan saja di Club Hub (Honours & Awards) untuk melihat peraih trofi dari musim ke musim.

---

## 🏢 Fitur 4: Fasilitas Klub & Staf Kepelatihan (*Club Facilities & Staff*)
> **Status:** ✅ *Completed (Selesai)*

Memperluas manajemen klub di luar stadion dan akademi muda dengan menghadirkan staf profesional (Head Physio, Tactical Analyst, Head Scout) dan infrastruktur fasilitas klub (Training Ground & Medical Centre).

### Rincian Fitur:
1. **Medical Centre & Fisioterapis (*Physio Staff*):**
   - Rekrut fisioterapis profesional dengan rating 1–5 bintang di bursa staf kepelatihan.
   - Mengurangi risiko cedera pertandingan hingga 45% dan memangkas drop stamina pasca-laga (dari 8 ke 5-6).
   - Mempercepat pemulihan kebugaran (*fitness recovery*) dan penyembuhan pemain cedera secara signifikan di alur *weekly housekeeping*.
2. **Training Ground Facility Upgrade:**
   - Level fasilitas latihan klub (Level 1–5) dengan visualisasi upgrade dan biaya dinamis.
   - Meningkatkan kapasitas latihan mingguan (3 hingga 7 pemain per sesi) serta poin kebugaran (4 hingga 8).
   - Mempercepat lonjakan atribut dan perkembangan potensi pemain muda (*wonderkids*) menuju rating maksimal (`jug_potencial`).
3. **Head Scout & Tactical Analyst:**
   - **Head Scout (1–5 Bintang):** Meningkatkan efektivitas scouting dunia, membuka potensi bonus wonderkid, serta memperbesar peluang menemukan talenta muda elit.
   - **Tactical Analyst (1–5 Bintang):** Menghasilkan dossier analisis taktis pra-pertandingan (*Tactical Dossier*) di Home Next Match card yang mencakup formasi lawan, gaya main, bahaya utama (*key danger men*), titik lemah pertahanan, dan rekomendasi kontra-taktik dengan akurasi prediksi berbobot bintang.
4. **UI & Integrasi Manajemen:**
   - Tab "Fasilitas & Staf" di Club Hub untuk upgrade infrastruktur dan rekrut/ganti staf.
   - Lembar Analisis Taktis lawan interaktif sebelum bertanding.
   - Tab Latihan terhubung langsung dengan level fasilitas latihan aktif.

---

## 🎨 Fitur 5: Kustomisasi Klub (*Create-Your-Own-Club Mode*)
> **Status:** 📅 *Future Backlog (Mendatang)*

Memberikan kebebasan pemain untuk membangun klub impian dari nol di awal karier.

### Rincian Fitur:
1. **Club Identity Creator:**
   - Kustomisasi nama klub, singkatan (3 huruf), julukan (*nickname*), dan tahun berdiri.
   - Pilih kota dan negara basis klub.
2. **Kustomisasi Stadion:**
   - Beri nama stadion sendiri, pilih tipe arsitektur dan kapasitas awal.
3. **Jersey Kit & Logo/Crest Editor:**
   - Pilih warna utama dan warna sekunder (Home & Away kits).
   - Pola jersey (polos, garis vertikal, garis horizontal, diagonal).
   - Desain badge/crest klub (pilihan perisai, lingkaran, ikon, pita).
4. **Sistem Skuad Awal:**
   - Pilihan: Memulai dengan pemain lokal muda, anggaran transfer ekstra, atau skuad acak seimbang di divisi terbawah piramida liga.
