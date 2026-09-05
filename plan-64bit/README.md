# Rencana build LineageOS 23.2 A37 — userspace 64-bit

Ditulis 5 September 2026. Semua angka hasil pemeriksaan langsung, bukan
perkiraan.

---

## 0. Vonis di depan

**Bisa dikerjakan, dan blobnya memang tersedia.** Tetapi dua kendala keras
membuat hasilnya kemungkinan besar **lebih buruk** daripada ROM 32-bit yang
sekarang berjalan, bukan lebih baik:

```
RAM     1.932.196 kB (1,84 GB). Saat bermain game sudah: free 82 MB,
        zram 369 MB terpakai, swap-in 338 halaman/detik.
        Pointer 64-bit menaikkan jejak memori 20-30% pada struktur data.

system  partisi 2.727 MB, terpakai 1.849 MB oleh ROM 32-bit sekarang.
        Sisa 878 MB. Build 64-bit membawa dua set pustaka (arm64 + arm)
        karena blob kamera hanya ada 32-bit.
```

Rencana lengkap tetap ditulis di bawah. Argumen tandingannya ada di §6, dan
gerbang keputusannya di §9 — supaya ini diputuskan sadar, bukan setengah jalan.

---

## 1. Titik berangkat

ROM 23.2 sekarang berjalan sebagai **userspace 32-bit di atas kernel 64-bit**:

```
TARGET_ARCH          := arm          <- userspace 32-bit
TARGET_ARCH_VARIANT  := armv8-a
TARGET_CPU_ABI       := armeabi-v7a
TARGET_CPU_VARIANT   := cortex-a53
TARGET_KERNEL_ARCH   := arm64        <- kernel SUDAH 64-bit
BOARD_KERNEL_IMAGE_NAME := Image
```

**Kernel tidak perlu disentuh sama sekali.** Ia sudah arm64 dan sudah
menjalankan userspace 32-bit lewat compat layer. Yang berubah hanya userspace.

Device tree A37 **berdiri sendiri** — tidak mewarisi `device/qcom/msm8916-common`,
hanya mengambil rujukan darinya di komentar. Jadi perubahan ini sepenuhnya di
tangan kita, tidak bergantung common tree LineageOS yang untuk msm8916_64
terakhir diperbarui 2018 (`LA.BR.1.2.6_rb1.12`, satu-satunya cabang).

---

## 2. Repo vendor 64-bit yang disediakan

`rigaz29/rb-vendor_oppo_A37-64bit`, cabang `main`, 85 MB terkompresi.

```
Asal   lineage-17.1-20220314-UNOFFICIAL-A37.zip (SourceForge, Android 10)
       ro.product.cpu.abi        arm64-v8a
       ro.vendor.product.cpu.abilist64  arm64-v8a
       ro.vendor.product.cpu.abilist32  armeabi-v7a,armeabi

Isi    710 berkas, 183 MB
       vendor/lib64   214 berkas   98 MB
       vendor/lib     305 berkas   72 MB
       vendor/etc     104 berkas
       vendor/bin      50 berkas
       vendor/firmware 15 berkas
```

**Belum ada `Android.bp` maupun `*-vendor.mk`** — keduanya harus dibuat (§7,
Fase 1).

### Peringatan penting: repo ini memuat lebih dari blob proprietary

`vendor/bin/hw` di dalamnya berisi 23 service, tetapi sebagian besar adalah
komponen **AOSP yang dibangun LineageOS 17.1 dari sumber**, bukan blob vendor:

```
android.hardware.audio@2.0-service          android.hardware.keymaster@3.0-service
android.hardware.camera.provider@2.5-service android.hardware.light@2.0-service.oppo_msm8916
android.hardware.graphics.allocator@2.0-service  android.hardware.media.omx@1.0-service
android.hardware.gnss@1.0-service            vendor.lineage.livedisplay@2.0-service-*
...
```

Bandingkan dengan vendor 32-bit yang sekarang dipakai LOS 23.2, yang hanya
mengambil empat service yang benar-benar proprietary:

```
android.hardware.bluetooth@1.0-service-qti
android.hardware.drm@1.0-service.widevine
android.hardware.drm@1.1-service.widevine
vendor.qti.hardware.perf@1.0-service
```

**Menyalin buta seluruh `vendor/bin/hw` dari repo 64-bit akan merusak build 23.2**,
karena HAL versi Android 10 itu sudah usang dan Android 16 membangunnya sendiri
dari sumber dengan versi jauh lebih baru. Yang diambil hanya blob yang memang
tidak bisa dibangun dari sumber.

---

## 3. Analisis kesenjangan blob

Dari 330 entri di `proprietary-files.txt` yang dipakai LOS 23.2, 274 di antaranya
pustaka di `vendor/lib`. Diadu dengan 214 berkas `vendor/lib64` di repo:

```
punya padanan 64-bit : 114 dari 274
tanpa padanan        : 160
```

160 yang tanpa padanan, menurut kategori:

| Jumlah | Kategori |
|---:|---|
| 121 | kamera (`libmmcamera*`, `libchromatix*`, `libactuator*`, `hw/camera.vendor.msm8916.so`) |
| 32 | lain-lain, sebagian besar JPEG/OMX pendukung kamera (`libjpegdhw`, `libqomx_jpeg*`, `libmmjpeg*`) dan perf (`libqti-perfd`, `libqti-iopd`) |
| 4 | codec media (`libOmxAlacDec`, `libOmxApeDec`, `libOmxWmaDec`, `libOmxAmrwbplusDec`) |
| 3 | bluetooth |

### Temuan kunci: kamera tetap 32-bit, dan itu normal

Repo 64-bit menyimpan **117 blob kamera di `vendor/lib`** (32-bit) dan hanya
lima berkas bernuansa kamera di `lib64`, yang semuanya shim atau antarmuka:

```
camera.device@1.0-impl.so  lib-imscamera.so  libcamera_shim.so
libimscamera_jni.so        libshim_camera.so
```

Artinya **ROM LOS 17.1 64-bit pun menjalankan HAL kamera sebagai proses 32-bit.**
Ini praktik standar: Qualcomm tidak pernah merilis HAL kamera 64-bit untuk
msm8916.

Konsekuensinya untuk rencana: build ini wajib **dual-arch** —
`TARGET_ARCH := arm64` dengan `TARGET_2ND_ARCH := arm`, dan blob kamera 32-bit
tetap dipasang berdampingan.

---

## 4. Kendala keras

### 4.1 RAM — kendala paling serius

Diukur di perangkat pada sesi sebelumnya:

```
MemTotal        1.932.196 kB (1,84 GB)
saat idle       PSI memori 0,18%, lmkd 0 pembunuhan, zram 2,75x
saat bermain ML free 82 MB, zram 369 MB terpakai, swap-in 338 halaman/detik,
                allocstall 19 per 10 detik (idle: 16 per 54 MENIT)
```

Perangkat ini **sudah** di batas dengan userspace 32-bit. Beralih ke 64-bit
menaikkan ukuran pointer dari 4 ke 8 byte, yang menaikkan jejak memori proses
secara umum 20-30% — paling terasa pada `system_server`, `zygote`, dan
aplikasi berbasis Java yang penuh referensi objek.

Pada perangkat yang saat bermain game sudah menyisakan 82 MB, itu bukan
optimasi melainkan regresi.

### 4.2 Ukuran partisi system

```
partisi        2.727 MB
terpakai (32-bit) 1.849 MB
sisa              878 MB
```

Build 64-bit membawa **dua set pustaka**: arm64 untuk yang punya padanan, arm
untuk kamera dan 159 blob lain. Ditambah ART boot image yang dibangun untuk dua
arsitektur.

Perkiraan kasar kenaikan 25-40% menempatkan hasilnya di 2.310-2.590 MB. Masih
muat, tetapi marginnya menipis dari 878 MB menjadi mungkin 130-400 MB — dan
kita sudah pernah kehabisan ruang saat pengemasan OTA (`RILIS.md`, jebakan 3).

### 4.3 Umur blob

Blob berasal dari Android 10 dan akan dipakai di Android 16 — enam versi mayor.
Vendor 32-bit yang sekarang berjalan membuktikan lompatan sebesar itu mungkin,
tetapi butuh 60 patch BPF-less dan sejumlah shim (`libshim_camera.so`,
`libcamera_shim.so`, stub di `libshims/`). Set 64-bit kemungkinan menuntut
pekerjaan shim yang setara, dan **shim yang sudah ada dibangun untuk 32-bit**
sehingga harus dibangun ulang untuk arm64.

---

## 5. Yang justru dipermudah

- **Kernel tidak berubah.** Sudah arm64.
- **Device tree berdiri sendiri.** Tidak ada common tree yang menghalangi.
- **Perkakas ekstraksi sudah ada**: `extract-files.sh`, `setup-makefiles.sh`,
  `proprietary-files.txt` di device tree — `setup-makefiles.sh` bisa
  menghasilkan `Android.bp` dan `A37-vendor.mk` otomatis begitu daftar blobnya
  disiapkan.
- **Preseden ada.** ROM LOS 17.1 64-bit A37 benar-benar dibangun dan dirilis,
  jadi kombinasi blob ini terbukti pernah boot di perangkat yang sama.

---

## 6. Untung-rugi, jujur

### Yang dibeli

- Aplikasi 64-bit berjalan lebih efisien per-instruksi (register lebih banyak,
  ISA ARMv8 penuh alih-alih AArch32).
- Ekosistem bergerak ke 64-bit-only. Google Play mewajibkan APK 64-bit sejak
  2019, dan sebagian aplikasi mulai menghapus varian 32-bitnya. Pada suatu
  titik, ROM 32-bit tidak lagi bisa memasang aplikasi tertentu.
- Android 16 sendiri makin mengarah ke 64-bit-only.

### Yang dibayar

- **Memori**, dan ini yang menentukan. Perangkat 2 GB dengan swap aktif
  saat gaming tidak punya ruang untuk overhead 20-30%.
- Ukuran system, dengan margin yang menipis.
- Kompleksitas dual-arch: dua set pustaka, dua set shim, HAL kamera 32-bit di
  userspace 64-bit.

### Penilaian

Untuk A37 dengan RAM 1,84 GB, **32-bit kemungkinan besar tetap pilihan yang
lebih baik untuk penggunaan sehari-hari.** Alasan sah untuk tetap membangun
64-bit ada dua: kompatibilitas aplikasi masa depan, dan nilai belajar.

Kalau tujuannya kelancaran, uang lebih baik dibelanjakan di tempat lain —
pengukuran sesi sebelumnya menunjukkan bottleneck A37 adalah CPU dan RAM, dan
64-bit memperburuk yang kedua.

---

## 7. Rencana kerja

### Fase 0 — Penyaringan blob (4-8 jam)

Jangan menyalin repo vendor apa adanya (§2).

1. Ambil `proprietary-files.txt` LOS 23.2 yang sekarang sebagai basis — daftar
   itu sudah terbukti cukup untuk boot.
2. Untuk tiap entri `vendor/lib/*`, cek apakah repo 64-bit punya
   `vendor/lib64/` dengan nama sama. Ada 114 yang punya.
3. Susun `proprietary-files.txt` baru:
   - 114 pustaka → ambil versi `lib64`
   - 160 sisanya → **tetap 32-bit**, tandai dengan `;`-suffix atau taruh di
     bagian 32-bit
   - blob non-pustaka (firmware, etc, bin) → tidak berubah
4. Jangan ambil `vendor/bin/hw/*` dari repo 64-bit kecuali empat yang memang
   proprietary (§2).

Keluaran: `proprietary-files.txt` dual-arch yang terukur.

### Fase 1 — Vendor tree (4-8 jam)

1. Tambahkan repo vendor 64-bit ke manifest sebagai `vendor/oppo` (atau
   `vendor/oppo-64`, dengan `rb-vendor_oppo_A37` tetap sebagai rujukan).
2. Jalankan `setup-makefiles.sh` untuk menghasilkan `Android.bp` dan
   `A37-vendor.mk`.
3. Periksa `Android.bp` hasilnya: tiap modul pustaka butuh
   `compile_multilib: "both"` atau `"64"`/`"32"` yang benar, dan
   `check_elf_files: false` untuk blob yang dependensinya tidak lengkap.

### Fase 2 — BoardConfig (2-4 jam)

```make
TARGET_ARCH                := arm64
TARGET_ARCH_VARIANT        := armv8-a
TARGET_CPU_ABI             := arm64-v8a
TARGET_CPU_VARIANT         := cortex-a53

TARGET_2ND_ARCH            := arm
TARGET_2ND_ARCH_VARIANT    := armv8-a
TARGET_2ND_CPU_ABI         := armeabi-v7a
TARGET_2ND_CPU_ABI2        := armeabi
TARGET_2ND_CPU_VARIANT     := cortex-a53

TARGET_SUPPORTS_64_BIT_APPS := true
```

`TARGET_KERNEL_ARCH := arm64` sudah benar, tidak berubah.

Periksa juga `ro.zygote` di `device.mk` — harus `zygote64_32`, dan pastikan
`init.rc` yang bersangkutan ikut.

### Fase 3 — Shim (8-20 jam, paling tidak pasti)

Shim yang ada sekarang (`libshim_camera.so`, `libcamera_shim.so`, stub di
`libshims/`) dibangun untuk 32-bit. Untuk blob yang naik ke 64-bit,
shim padanannya harus dibangun untuk arm64.

Kamera tetap 32-bit sehingga shim kameranya tidak berubah — itu meringankan.

### Fase 4 — Build dan boot (4-12 jam)

`build.sh` sudah menangani jebakan yang diketahui (OOM, testkey, disk, fungsi
shell). Yang perlu diperhatikan khusus:

- Build 64-bit lebih besar; **pastikan disk ≥ 25 GB bebas** sebelum mulai.
- Pergantian `TARGET_ARCH` memaksa build penuh, jadi `-j` diturunkan otomatis.
- Kalau `system.img` melebihi 2.727 MB, pangkas dari `PRODUCT_PACKAGES`
  sebelum mengubah ukuran partisi — mengubah tata letak partisi jauh lebih
  berisiko.

### Fase 5 — Verifikasi (4-8 jam)

Ulangi pengukuran yang sudah jadi patokan proyek ini dan bandingkan langsung
dengan angka 32-bit:

```
getprop ro.product.cpu.abi          harus arm64-v8a
getprop ro.product.cpu.abilist      arm64-v8a,armeabi-v7a,armeabi
dumpsys meminfo                     bandingkan Free RAM dengan 966 MB (32-bit)
cat /proc/pressure/memory           bandingkan dengan 0,18% idle
dumpsys SurfaceFlinger --timestats  bandingkan FPS dengan 41,3 fps baseline
```

**Ukuran keberhasilan yang jujur bukan "boot", melainkan "tidak lebih buruk".**
Kalau Free RAM turun signifikan atau lmkd mulai membunuh aplikasi, 64-bit
merugikan dan sebaiknya dibatalkan.

**Total kasar: 26-60 jam.**

---

## 8. Risiko

| Risiko | Peluang | Dampak | Mitigasi |
|---|---|---|---|
| RAM tidak cukup, lmkd mulai membunuh | **tinggi** | ROM lebih buruk dari sekarang | Fase 5 mengukurnya; batalkan bila terbukti |
| `system.img` melebihi partisi | sedang | build gagal di akhir | Pangkas `PRODUCT_PACKAGES`, jangan ubah partisi |
| Shim 64-bit tidak cukup | sedang | HAL crash | Kamera tetap 32-bit sehingga bagian tersulit terhindar |
| Blob Android 10 di Android 16 | sedang | HAL tidak kompatibel | Set 32-bit membuktikan lompatan itu mungkin |
| Menyalin `vendor/bin/hw` buta | tinggi bila lalai | build rusak | §2 — hanya empat yang proprietary |

Mitigasi terpenting: **kerjakan di branch terpisah** (`lineage-23-64bit`) di
ketiga repo. ROM 32-bit yang sekarang berjalan tidak boleh tersentuh.

---

## 9. Gerbang keputusan

1. **Tujuannya kelancaran atau kompatibilitas?** Kalau kelancaran, §6
   mengatakan jangan — 64-bit memperburuk kendala utama A37. Kalau
   kompatibilitas aplikasi masa depan atau nilai belajar, lanjut.
2. **Bersedia ROM lebih lambat?** Overhead memori 20-30% pada perangkat yang
   sudah swap-in 338 halaman/detik saat gaming punya konsekuensi nyata.
3. **Bersedia membatalkan bila pengukuran Fase 5 buruk?** Kalau tidak, jangan
   mulai — hasil terpenting dari rencana ini adalah datanya, bukan ROM-nya.

Kalau ketiganya lolos, mulai dari **Fase 0**. Penyaringan blobnya murah dan
hasilnya menentukan apakah sisanya realistis.

---

## 10. Rujukan

- Vendor 64-bit — https://github.com/rigaz29/rb-vendor_oppo_A37-64bit
- Vendor 32-bit yang berjalan — https://github.com/rigaz29/rb-vendor_oppo_A37
- Device tree — https://github.com/rigaz29/rb_device_oppo_A37
- ROM asal blob — lineage-17.1-20220314-UNOFFICIAL-A37 (SourceForge)
- Common tree msm8916_64 LineageOS (usang, 2018) —
  https://github.com/LineageOS/android_device_qcom_msm8916_64

Dokumen terkait di repo ini: `PLAN-LOS23.md`, `RILIS.md`, `tools/build.sh`.
