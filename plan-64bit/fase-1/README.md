# Fase 1 — vendor tree 64-bit

Dikerjakan 5 September 2026. **Selesai, terverifikasi.**

---

## 1. Hasil

Vendor tree dual-arch terbentuk dan lolos audit:

```
proprietary/     329 berkas   114 MB
  vendor/lib64   114 pustaka  semuanya ELF 64-bit aarch64
  vendor/lib     160 pustaka  semuanya ELF 32-bit ARM
  sisanya        firmware, etc, bin, framework, app

A37-vendor.mk        349 baris   322 PRODUCT_COPY_FILES + 6 PRODUCT_PACKAGES
Android.bp            90 baris   6 modul
BoardConfigVendor.mk   7 baris   disalin apa adanya
```

Audit yang dijalankan:

| Pemeriksaan | Hasil |
|---|---|
| Tiap entri `PRODUCT_COPY_FILES` menunjuk berkas yang ada | 322 diperiksa, **0 hilang** |
| Seluruh `vendor/lib64/*.so` benar-benar 64-bit | 114 diperiksa, **0 salah** |
| Seluruh `vendor/lib/*.so` benar-benar 32-bit | 160 diperiksa, **0 salah** |

Salah arsitektur tidak akan tertangkap saat build — ia muncul sebagai HAL yang
gagal dimuat saat boot. Karena itu audit ini dijalankan sebelum apa pun.

---

## 2. Gabungan dua sumber, sesuai temuan Fase 0

```
rb-vendor_oppo_A37-64bit  ->  114 berkas   (seluruh vendor/lib64)
rb-vendor_oppo_A37        ->  215 berkas   (pustaka 32-bit + 43 blob yang
                                            tidak ada di repo 64-bit)
```

Tanpa sumber kedua, build akan kehilangan seluruh tumpukan Bluetooth, DRM
widevine, perf daemon, codec audio OMX, dan firmware GPU.

---

## 3. Perkakas: generator resmi tidak bisa dipakai

`device/oppo/A37/setup-makefiles.sh` **tidak dapat dijalankan**, dan ini bukan
temuan baru — `A37-vendor.mk` yang sekarang berjalan memuat catatan yang sama:

```
# setup-makefiles.sh tidak bisa dijalankan lagi -- ia memanggil
# vendor/cm/build/tools/extract_utils.sh yang sudah tidak ada di pohon
# LineageOS 23, dan isinya masih menyebut DEVICE=a6000 VENDOR=lenovo warisan
# a6010 yang tidak pernah diperbarui.
```

LineageOS 23 menyediakan `tools/extract-utils/` berbasis Python, tetapi API-nya
menuntut `extract-files.py` bergaya baru yang belum ada di device tree ini.

Karena itu makefile Fase 1 **dihasilkan dengan skrip sendiri**, meniru pola
`A37-vendor.mk` 32-bit yang sudah terbukti berjalan: `PRODUCT_COPY_FILES` untuk
mayoritas blob, `PRODUCT_PACKAGES` + `Android.bp` hanya untuk enam modul yang
butuh penanganan khusus.

---

## 4. Keputusan pada `Android.bp`

Dari delapan modul di `Android.bp` 32-bit:

| Modul | Perlakuan |
|---|---|
| `libloc_api_v02`, `libloc_ds_api`, `libtime_genoff` | **naik ke arm64** — `android_arm64`, `compile_multilib: "64"`, sumber dari `vendor/lib64/` |
| `qcrilmsgtunnel`, `shutdownlistener`, `imscmlibrary` | tidak arch-specific (APK dan JAR), tidak berubah |
| `libTimeService`, `TimeService` | **dihapus** — keduanya tidak ada di `proprietary-files.txt` LOS 23.2, jadi tidak ikut dibawa |

`check_elf_files: false` dipertahankan di seluruh modul: blob berasal dari
Android 10 dan sebagian dependensinya tidak lengkap di pohon 23.2.

---

## 5. Temuan sampingan: daftar asli punya duplikat

`proprietary-files.txt` LOS 23.2 memuat `vendor/lib/libmmipl.so` **dua kali**.
Karena itu 330 entri menghasilkan 329 berkas unik. Tidak berbahaya — `cp`
menimpa dengan isi yang sama — tetapi layak diperbaiki di daftar aslinya.

---

## 6. Yang belum dikerjakan, dan disengaja

**Daemon IMS belum diaktifkan.** Daftar Fase 0 mempertahankan komentar yang
membuang `imsqmidaemon` dan `imsdatadaemon`, sehingga keduanya tidak ikut
tersalin meski tersedia di repo 64-bit dan penghalang arsitekturnya sudah
hilang. Menghidupkannya adalah pekerjaan terpisah yang sebaiknya dilakukan
**setelah** ROM 64-bit terbukti boot — menambah variabel sebelum itu hanya
mempersulit diagnosis.

**Vendor tree belum dipasang ke pohon LOS.** Ia berada di `/root/staging64/A37`
dan sengaja tidak menimpa `vendor/oppo/A37` yang sekarang berfungsi. Pemasangan
adalah langkah pertama Fase 2, bersama perubahan `BoardConfig.mk`.

---

## 7. Berkas

```
A37-vendor.mk          hasil generate, 322 COPY_FILES + 6 PACKAGES
Android.bp             6 modul, tiga di antaranya arm64
BoardConfigVendor.mk   salinan
```

Blob itu sendiri (114 MB) tidak disimpan di repo ini; ia dibentuk ulang dari
dua repo vendor dengan `proprietary-files-64bit.txt` dari Fase 0.

---

## 8. Status terhadap rencana induk

Fase 1 selesai sesuai rencana, dengan satu penyesuaian yang sudah diperkirakan
Fase 0: vendor tree dibentuk dari dua sumber, bukan satu.

Yang **tidak** berubah: kendala RAM 1,84 GB dan margin partisi system belum
tersentuh sama sekali. Keduanya baru terukur di Fase 5, dan gerbang keputusan
di rencana induk §9 tetap berlaku penuh — terutama kesediaan membatalkan bila
pengukuran menunjukkan ROM 64-bit lebih lambat daripada yang 32-bit sekarang.
