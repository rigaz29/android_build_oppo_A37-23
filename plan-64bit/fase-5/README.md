# Fase 5 — Verifikasi di perangkat dan penutupan celah dual-arch

Tanggal pengukuran: 6–7 September 2026
ROM: `23.2-20260906_134257-UNOFFICIAL-A37`, `ro.product.cpu.abi = arm64-v8a`,
`ro.zygote = zygote64`

## 1. Hasil

ROM 64-bit **boot sampai homescreen**. Setelah perbaikan di fase ini, seluruh
layanan inti berjalan:

| Layanan | Sebelum | Sesudah |
|---|---|---|
| `qmuxd` | restarting | **running** |
| `netmgrd` | restarting | **running** |
| `vendor.ril-daemon` | restarting | **running** |
| `ril-daemon2` | restarting | **running** |
| `qseecomd` | restarting | **running** |

Radio hidup penuh dan terbukti dari properti perangkat, bukan dari asumsi:

```
gsm.sim.state          LOADED,ABSENT
gsm.operator.alpha     by.U
gsm.sim.operator.alpha Telkomsel
gsm.network.type       LTE,Unknown
lshal                  android.hardware.radio@1.0/1.1::IRadio slot1 + slot2 terdaftar
```

Memori — prediksi rencana (overhead 20–30 %) **tidak terbukti**:

| | 32-bit (dasar) | 64-bit |
|---|---|---|
| Free RAM (`dumpsys meminfo`) | 989.525 K | 973.759 K |

Selisihnya 15 MB, sekitar **1,5 %**, bukan 20–30 %. Angka rencana itu salah dan
sudah dikoreksi di sini.

## 2. Metode: dua jenis audit, bukan satu

Kegagalan berulang di Fase 4 (EGL, lalu RIL, lalu audio, lalu RIL lagi) punya
satu akar yang sama: **saya menambal satu kegagalan per satu build**, padahal
seluruh kelasnya bisa ditemukan sekaligus sebelum build pertama.

Fase ini menjalankan audit menyeluruh lebih dulu. Ternyata dibutuhkan **dua**
jenis, dan yang kedua sempat terlewat:

### 2.a Audit `DT_NEEDED` — tautan saat link

`alat/audit-dt-needed.sh`. Untuk setiap ELF di pohon ROM terbangun: baca
`DT_NEEDED`, lalu cari penyedianya di direktori pustaka **arch yang sama**,
pisahkan namespace vendor dan system.

Catatan penting saat membacanya: APEX di `out/` masih berbentuk `.apex` yang
belum diekstrak, sehingga `libnativehelper`, `libstats*`, `libicu`,
`libandroidicu`, `libnativeloader`, `libsigchain`, `libnetd_*`, dan
`libadb_pairing_*` muncul sebagai "hilang" padahal penghuni APEX. Itu positif
palsu — jangan dikejar.

### 2.b Audit `dlopen` berdasar nama — tautan saat runtime

Audit 2.a **tidak** menemukan `librpmb.so`, karena `qseecomd` memuatnya lewat
`dlopen("librpmb.so")`, bukan lewat `DT_NEEDED`. Nama seperti itu hanya ada
sebagai string literal di dalam biner.

Pemindaian kedua: ambil semua string berbentuk `lib*.so` dari setiap komponen
32-bit, buang yang sudah ada di `DT_NEEDED`, lalu tandai yang **ada versi
64-bitnya tapi tidak ada versi 32-bitnya** — pola khas blob yang lupa dibawa
saat peralihan dual-arch.

Hasilnya 22 pustaka, menyentuh GPS, Bluetooth, DRM/qseecom, codec audio, dan
color management. Tidak satu pun terlihat oleh audit 2.a.

## 3. Temuan dan perbaikan

### 3.a `libxml.so` 32-bit — penyebab pasti `qmuxd`/`netmgrd` restart

```
CANNOT LINK EXECUTABLE "/system/vendor/bin/qmuxd": library "libxml.so" not found
   needed by /system/vendor/lib/libconfigdb.so
```

Tercatat **1170 kali** di logcat. `qmuxd` dan `netmgrd` adalah ELF32, sedangkan
`libxml.so` hanya dibawa ke `vendor/lib64`.

### 3.b `com.quicinc.cne.api@1.0.so` + `com.quicinc.cne.constants@1.0.so` 32-bit

Penghalang **kedua** untuk `netmgrd`, yang baru terlihat setelah 3.a dibereskan:
`netmgrd` → `libcneapiclient.so` → `cne.api` → `cne.constants`. Ketiganya
32-bit; dua yang terakhir hanya ada 64-bit.

### 3.c `libmedia.so` 32-bit — kesalahan saya sendiri

```
E RILD: dlopen failed: library "libmedia.so" not found:
        needed by /system/vendor/lib/libril-qc-qmi-1.so
```

Stub `libmedia_a37_vendor` dipindahkan ke lib64-**saja** pada commit yang
membuat shim multiarch, dengan alasan tertulis: *"Keempat konsumennya kini di
vendor/lib64 … Tidak ada satupun blob 32-bit yang merujuk libmedia.so."*

Alasan itu benar saat ditulis, dan menjadi **salah** pada commit berikutnya yang
memaksa `rild` dan radio HAL kembali 32-bit — karena itu memindahkan
`libril-qc-qmi-1.so` ke `vendor/lib`. Saya tidak mengaudit ulang closure-nya
sesudah mengubah arch komponen.

Perbaikan: stub dibangun untuk **kedua** arch (`libmedia_a37_vendor` 32-bit di
`vendor/lib`, `libmedia_a37_vendor64` di `vendor/lib64`), masing-masing dengan
`install_symlink` sendiri — pola yang sama dengan `libandroid` yang sudah
terbukti.

> **Aturan yang seharusnya saya pegang:** mengubah arch sebuah komponen mengubah
> arch seluruh closure dependensinya. Jalankan ulang audit, jangan percaya
> catatan lama — termasuk catatan yang saya tulis sendiri.

### 3.d Stack GPU 32-bit — 13 driver EGL tanpa pustaka pendukungnya

Fase 4 membuat 13 driver di `vendor/lib/egl` jadi dual-arch, tetapi tidak
membawa pustaka yang mereka tautkan: `libgsl.so` (12 konsumen) dan
`libadreno_utils.so` (6 konsumen). Jadi lapisan EGL 32-bit lengkap, isinya tidak.

Konsumen 32-bit-nya nyata dan sedang berjalan: `camera.vendor.msm8916.so`
(dimuat `android.hardware.camera.provider-service_32.lineage`),
`gralloc.msm8916.so`, `copybit.msm8916.so`, `hwcomposer.msm8916.so`.

Keduanya ditambahkan.

Varian `libESX*GLES*_adreno.so` dan `libRB*GLES*_adreno.so` **dibuang** dari sisi
32-bit: `ro.hardware.egl = adreno` sehingga hanya jalur `libEGL_adreno` yang
pernah dimuat, dan mempertahankannya menuntut `libllvm-glnext.so` (8,1 MB) +
`libsc-a3xx.so` (4,8 MB) untuk sesuatu yang tidak pernah dipakai.

> **Koreksi.** Percobaan pertama membuang SELURUH `libESX*`/`libRB*`, termasuk
> `libESXEGL_adreno.so` dan `libRBEGL_adreno.so`. Itu keliru: kedua berkas itu
> dituntut lewat `DT_NEEDED` oleh `eglSubDriverAndroid.so` dan `eglsubAndroid.so`
> — dua sub-driver yang justru ada di jalur utama dan tetap dipasang. Keduanya
> dikembalikan (72 KB + 172 KB). Yang dibuang hanya varian GLES-nya.

### 3.e 18 blob `dlopen` 32-bit

Dari audit 2.b, ditambahkan ke `vendor/lib` (daftar lengkap dengan ukuran dan
SHA256 ada di `blob-baru-32bit.txt`):

| Fungsi | Blob |
|---|---|
| qseecom / DRM | `librpmb.so`, `libssd.so`, `libdrmtime.so` |
| GPS | `libgeofence.so`, `liblbs_core.so`, `libloc_api_v02.so`, `libizat_core.so` |
| Grafis 2D | `libC2D2.so`, `libscale.so` |
| Codec audio | `libOmxAacDec.so`, `libOmxEvrcDec.so`, `libOmxQcelp13Dec.so` |
| Display post-processing | `libmm-qdcm.so`, `libmm-als.so` |
| Bluetooth | `libbtnv.so` |

Closure-nya sudah dihitung rekursif sampai bersih (hanya menyisakan bionic).

> `libRSDriver_adreno.so`, `librs_adreno.so`, dan `libCB.so` sempat ikut
> ditambahkan di sini, lalu **dibuang lagi** pada putaran kedua — lihat §8.c.

## 4. Bukti perbaikan, sebelum build

Ke-23 blob dan stub `libmedia` 32-bit didorong langsung ke `/system/vendor/lib`
perangkat yang sedang berjalan, lalu layanan direstart. Ini membuktikan
perbaikan **sebelum** menghabiskan berjam-jam build:

```
sebelum : qmuxd/netmgrd/ril-daemon2/qseecomd  restarting
sesudah : kelimanya running, SIM LOADED, operator by.U, jaringan LTE
logcat  : nol baris "not found: needed" / "CANNOT LINK" / "cannot locate symbol"
```

Stub `libmedia` yang didorong untuk uji ini adalah tiruan kecil yang dibangun
dengan clang pohon; ia hanya mengekspor empat nama ter-mangle yang sama dengan
stub asli. ROM hasil build akan memakai stub asli dari
`libshims/stub/libmedia_stub.cpp`.

## 5. Sisa yang diketahui, sengaja tidak diperbaiki

Semuanya sudah dipastikan **tidak** memunculkan error di logcat perangkat:

| Item | Alasan |
|---|---|
| `libfwlock.so`, `libsecureui.so` | Tidak ada di repo vendor mana pun — OPPO memang tidak pernah mengirimnya. `qseecomd` mencatat gagal lalu tetap `running`. |
| `android.hidl.base@1.0.so` 32-bit | Dituntut HAL `vendor.qti.hardware.iop` (perf boost). Tidak tersedia di repo mana pun. |
| `libvcel.so` 64-bit | Dituntut `lib-imsvt.so` (IMS video telephony). Tidak tersedia. |
| `libmmsw_*.so` 32-bit | Dituntut `libvpplibrary.so` (video post-processing). Tidak tersedia. |
| `libOmxAmrwbplusDec.so`, `libOmxWmaDec.so` 64-bit | Dituntut `libOmxCore.so` 64-bit, sementara layanan OMX yang benar-benar berjalan adalah yang 32-bit. Tidak ada di repo 64-bit. |

## 6. Batasan `ZYGOTE_FORCE_64` yang perlu diketahui pengguna

`ro.product.cpu.abilist` di perangkat hanya berisi `arm64-v8a`. Konsekuensinya
langsung: **aplikasi yang hanya punya pustaka native 32-bit tidak bisa dipasang
atau dijalankan.** Aplikasi Java murni dan aplikasi dengan `arm64-v8a` aman.

Ini pertukaran yang disengaja demi hemat RAM (satu zygote, bukan dua). Kalau
nanti ada aplikasi penting yang 32-bit-only, jalan keluarnya adalah beralih ke
`zygote64_32` — dan seluruh stack 32-bit yang dilengkapi di fase ini justru
menjadi prasyaratnya.

## 7. Berkas di fase ini

```
A37-vendor-v5.mk                       vendor makefile hasil fase ini (228 entri lib, 111 lib64)
blob-baru-32bit.txt                    23 blob baru + ukuran + SHA256 + asal
alat/audit-dt-needed.sh                skrip audit DT_NEEDED, bisa dipakai ulang
perubahan-device-tree/Android.bp       install_symlink libmedia dua arch
perubahan-device-tree/device.mk        pendaftaran libmedia_a37_vendor64
perubahan-device-tree/libshims-Android.mk  stub libmedia dua arch
```

Salinan disimpan di sini karena git di `device/oppo/A37`, `vendor/oppo/A37`, dan
`hardware/ril` rusak sejak `.repo/project-objects` dihapus untuk membebaskan
disk — `.git` di sana berupa symlink ke direktori itu.

## 8. Putaran kedua: apa yang baru ketahuan setelah image jadi

Audit atas image hasil build pertama menemukan **lapisan kedua** — blob yang baru
ditambahkan ternyata memuat blob lain lagi. Tiga pelajaran, semuanya dibayar
dengan siklus build ulang:

### 8.a Satu pohon vendor memakai DUA mekanisme pemasangan

`libloc_api_v02` dan `libloc_ds_api` bukan entri `PRODUCT_COPY_FILES` melainkan
`cc_prebuilt_library_shared` di `vendor/oppo/A37/Android.bp` dengan
`compile_multilib: "64"`. Menambahkan barisnya ke `A37-vendor.mk` karena itu
**tidak berpengaruh sama sekali**, dan build tetap sukses tanpa peringatan.

Ketahuan hanya karena isi image diperiksa satu per satu — 22 dari 23 blob masuk.

> Memeriksa daftar blob tidak cukup. Yang harus diperiksa adalah isi image yang
> benar-benar terbangun.

### 8.b Closure harus dihitung sampai berhenti sendiri, lalu disimulasikan

Putaran kedua memakai iterasi: unduh, hitung `DT_NEEDED` + string `dlopen`, ulangi
sampai tidak ada kebutuhan baru. Hasilnya diverifikasi terhadap **simulasi** isi
`vendor/lib` pasca-perubahan sebelum build dijalankan, bukan sesudahnya.

### 8.c Rantai RenderScript 32-bit dibuang, rantai GPS dipertahankan

|  | Rantai RS 32-bit | Rantai GPS 32-bit |
|---|---|---|
| Terpakai? | Tidak | Tidak |
| Kenapa tidak | HAL-nya hanya dimuat proses aplikasi; ROM ini tidak punya proses aplikasi 32-bit | HAL gnss berjalan 64-bit, memuat `lib64/hw/gps.msm8916.so` |
| Ongkos menutup | `libllvm-qcom.so` **19 MB** | `libloc_ds_api.so` **28 KB** |
| Keputusan | dibuang | dilengkapi |

Perbedaan perlakuannya semata ongkos, dan disengaja.

Tersisa satu `dlopen` menggantung yang disadari:
`android.hardware.renderscript@1.0-impl.so` 32-bit (modul AOSP, bukan milik pohon
ini) tidak akan menemukan `libRSDriver_adreno.so`. Ia tidak pernah dimuat.

## 9. Build: `SOONG_GOMEMLIMIT` wajib untuk 64-bit

Build pertama menuju OOM setelah 29 menit. Diukur saat itu:

```
soong_build   RSS 10,4 GB + swap 30,3 GB = ~41 GB
sistem        RAM 11 GB, swap 31 GB -> sisa 425 MB
```

Go tidak memperlakukan swap sebagai tekanan memori, jadi menaikkan swap justru
memberi heap lebih banyak ruang untuk tumbuh. `tools/build.sh` kini menyetel
`SOONG_GOMEMLIMIT=6GiB` secara baku; jejaknya turun ke ~20 GB dan stabil.

Ini mengoreksi `patches/README-bpfless.md` yang menyimpulkan "swap saja cukup" —
kesimpulan itu diambil dari build 32-bit dan tidak berlaku untuk 64-bit.

Ongkosnya nyata dan harus diperhitungkan: tahap analisis `soong_build`
memakan **~60 menit** per build pada mesin ini.
