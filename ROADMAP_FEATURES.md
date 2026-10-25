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
> **Status:** ⏳ *Planned (Tahap Berikutnya)*

Memperluas manajemen klub di luar stadion dan akademi muda dengan menghadirkan staf profesional dan infrastruktur latihan.

### Rincian Fitur:
1. **Medical Centre & Fisioterapis (*Physio Staff*):**
   - Rekrut fisioterapis dengan rating bintang (1–5 bintang).
   - Mempercepat pemulihan pemain cedera (*injury recovery speed*).
   - Mengurangi risiko cedera parah saat pertandingan dan mempercepat pemulihan kebugaran (*fitness recovery*) pasca-laga.
2. **Training Ground Facility Upgrade:**
   - Level fasilitas latihan (Level 1–5).
   - Meningkatkan efektivitas latihan mingguan dan mempercepat lonjakan atribut pemain muda (*wonderkids*) menuju potensi maksimalnya (`jug_potencial`).
3. **Head Scout & Tactical Analyst:**
   - Meningkatkan akurasi laporan *scouting* dan analisis kekuatan lawan sebelum matchday.

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
