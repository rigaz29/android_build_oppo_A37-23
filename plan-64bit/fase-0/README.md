# Fase 0 — penyaringan blob 64-bit

Dikerjakan 5 September 2026. **Selesai.**

Tujuan: mengubah "710 berkas di repo vendor" menjadi daftar pekerjaan yang
terukur, dan menentukan apakah sisa rencana realistis.

---

## 1. Hasil utama

Dari 330 entri `proprietary-files.txt` yang dipakai LOS 23.2 sekarang:

```
naik ke vendor/lib64  : 114
tetap 32-bit          : 161
bukan pustaka         :  55   (firmware, etc, bin, framework, app)
                        ---
total                 : 330   (tidak berubah)
```

Berkas hasil: `proprietary-files-64bit.txt`, 433 baris, dengan **seluruh 92
baris komentar dipertahankan** — komentar itu memuat pengetahuan mahal dari
sesi-sesi sebelumnya (kenapa `ims.apk` dibuang, kenapa daemon IMS gagal, dan
seterusnya). Enam entri berprefiks `-` dan tiga entri berformat `src:dest`
juga terjaga apa adanya.

---

## 2. Temuan yang mengubah rencana: butuh DUA vendor tree

**43 blob yang dipakai LOS 23.2 tidak ada sama sekali di repo 64-bit.**
Seluruhnya tersedia di vendor 32-bit yang sekarang berjalan.

Yang absen bukan hal sepele:

| Kelompok | Contoh |
|---|---|
| Bluetooth | `android.hardware.bluetooth@1.0-service-qti`, `-impl-qti.so`, `com.qualcomm.qti.bluetooth_audio@1.0.so` |
| Codec BT | `libaptX_encoder.so`, `libaptXHD_encoder.so`, `libldacBT_enc.so` |
| DRM | `android.hardware.drm@1.1-service.widevine`, `libwvhidl.so` |
| Perf | `libqti-perfd.so`, `libqti-iopd.so`, `libperfgluelayer.so`, `vendor.qti.hardware.perf@1.0-service` |
| Codec audio | `libOmxAlacDec`, `libOmxApeDec`, `libOmxWmaDec`, `libOmxAmrwbplusDec`, `libmm-omxcore.so` |
| Firmware GPU | `a225_pfp.fw`, `a330_pfp.fw`, `a330_pm4.fw` |
| Lain | `time_daemon`, `vm_bms`, `libmmcamera_tuning.so`, `libstlport.so` |

Sebabnya: repo 64-bit berasal dari **LOS 17.1 (Android 10)**, sedangkan vendor
32-bit yang berjalan sekarang dikumpulkan untuk LOS 23.2 dari sumber yang lebih
lengkap. Repo 64-bit memang lebih besar secara total (885 berkas vs 338), tetapi
cakupannya berbeda, bukan superset.

**Konsekuensi untuk Fase 1:** vendor tree 64-bit harus dibentuk dari **gabungan
dua sumber**, bukan satu:

```
rb-vendor_oppo_A37-64bit  ->  114 pustaka vendor/lib64
rb-vendor_oppo_A37        ->  161 pustaka 32-bit + 43 blob lain
```

Daftar lengkapnya di `hanya-di-vendor-32bit.txt`.

---

## 3. Temuan sampingan: 64-bit menghidupkan kembali IMS

`proprietary-files.txt` yang sekarang memuat catatan ini:

```
# Ketiga daemon IMS DIBUANG: ber-ELF 64-bit dengan interpreter
# /system/bin/linker64, sedangkan ROM ini TARGET_ARCH := arm / armeabi-v7a dan
# hanya punya /system/bin/linker 32-bit. Jadi tidak akan pernah bisa dieksekusi
#   E init: cannot execv('/system/vendor/bin/imsqmidaemon')
# (ENOENT-nya menunjuk interpreternya, bukan binernya; binernya ada 120.464 B.)
# Audit seluruh ROM: hanya ketiga file inilah biner 64-bit yang terpasang.
```

Dua dari ketiganya ada di repo 64-bit, dan ukurannya cocok persis dengan
catatan itu:

```
vendor/bin/imsqmidaemon    120.464 byte   <- cocok dengan "binernya ada 120.464 B"
vendor/bin/imsdatadaemon   169.704 byte
```

Dengan userspace 64-bit, `/system/bin/linker64` tersedia dan kedua daemon ini
bisa dieksekusi. **Ini keuntungan konkret 64-bit yang belum tercatat di rencana
induk** — tumpukan IMS (VoLTE) yang selama ini mati karena alasan arsitektur
murni menjadi mungkin dihidupkan.

Catatan kejujuran: ini belum berarti VoLTE akan berfungsi. `ims.apk` sendiri
dibuang karena alasan berbeda (memakai `System.arraycopy` yang jadi private
sejak Android 11), dan itu tidak berubah oleh 64-bit. Yang berubah hanya
penghalang arsitekturnya.

---

## 4. Konfirmasi: kamera tetap 32-bit

161 pustaka yang tetap 32-bit, dan 121 di antaranya kamera. Repo 64-bit sendiri
menyimpan 117 blob kamera di `vendor/lib` dan hanya lima berkas di `lib64`,
semuanya shim atau antarmuka:

```
camera.device@1.0-impl.so  lib-imscamera.so  libcamera_shim.so
libimscamera_jni.so        libshim_camera.so
```

Ini memperkuat kesimpulan riset: ROM LOS 17.1 64-bit pun menjalankan HAL kamera
sebagai proses 32-bit. Build ini wajib dual-arch, dan itu memang bagaimana
seharusnya.

---

## 5. Yang TIDAK diambil dari repo 64-bit

Repo memuat 23 service di `vendor/bin/hw`, tetapi sebagian besar adalah
komponen AOSP yang dibangun LineageOS 17.1 dari sumber. Daftar hasil Fase 0
**tidak mengambil satupun dari yang bukan proprietary**, dan mempertahankan
hanya empat yang memang blob:

```
android.hardware.bluetooth@1.0-service-qti
android.hardware.drm@1.0-service.widevine
android.hardware.drm@1.1-service.widevine
vendor.qti.hardware.perf@1.0-service
```

Ketiga dari empat itu justru harus diambil dari vendor 32-bit (§2).

---

## 6. Berkas

```
proprietary-files-64bit.txt   433 baris, daftar dual-arch siap pakai
naik-ke-lib64.txt             114 pustaka yang naik ke 64-bit
tetap-32bit.txt               160 pustaka yang tetap 32-bit
hanya-di-vendor-32bit.txt      44 blob yang absen dari repo 64-bit
```

---

## 7. Penilaian: apakah sisa rencana realistis?

**Ya, dengan satu perubahan.** Fase 1 di rencana induk mengasumsikan satu
vendor tree; kenyataannya butuh gabungan dua. Itu menambah pekerjaan tetapi
tidak mengubah kelayakan — `setup-makefiles.sh` bisa memproses daftar gabungan
selama kedua sumber tersedia di pohon saat ekstraksi.

Yang **tidak** berubah dari penilaian rencana induk: kendala RAM 1,84 GB dan
margin partisi system tetap menjadi alasan utama untuk meragukan apakah ROM
64-bit akan lebih baik daripada yang 32-bit sekarang. Fase 0 tidak menyentuh
kedua hal itu, dan gerbang keputusan di rencana induk §9 tetap berlaku penuh.
