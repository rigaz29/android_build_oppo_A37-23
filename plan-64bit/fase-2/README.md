# Fase 2 — BoardConfig dan pemasangan

Dikerjakan 5 September 2026. **Selesai, terverifikasi lewat `get_build_var`.**

---

## 1. Cabang terpisah, ROM 32-bit tetap utuh

```
device/oppo/A37   lineage-23-64bit   304f1790   (dari lineage-23 bc04b737)
vendor/oppo/A37   lineage-23-64bit   8bdc7e4    (dari 1a23fb2)
kernel            TIDAK DISENTUH
```

Untuk kembali ke ROM 32-bit: `git checkout lineage-23` di device tree dan
vendor. Tidak ada yang perlu dibatalkan.

---

## 2. Perubahan arsitektur

```make
TARGET_BOARD_SUFFIX := _64
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

TARGET_SUPPORTS_64_BIT_APPS := true
```

`TARGET_KERNEL_ARCH := arm64` **tidak berubah** — ia sudah begitu sejak awal.
Kernel selama ini menjalankan userspace 32-bit lewat compat layer, jadi
peralihan ini murni urusan userspace.

---

## 3. Temuan: komentar lama justru menjelaskan kasus kita

`device.mk` memuat catatan ini sebelum daftar paket kamera:

```
# Varian tanpa akhiran _32 yang dipakai: _32 hanya berarti compile_multilib 32
# untuk platform 64-bit berblob 32-bit (Mi-Thorium). A37 TARGET_ARCH=arm murni
# 32-bit, sama seperti a6010.
```

Sejak `TARGET_ARCH := arm64`, **A37 persis menjadi kasus yang dimaksud**:
platform 64-bit dengan blob kamera 32-bit. Paketnya diganti ke

```
android.hardware.camera.provider-service_32.lineage
```

Infrastrukturnya tidak perlu dibuat — sudah ada di
`hardware/lineage/interfaces/camera/aidl/provider/Android.bp:38`, lengkap
dengan `compile_multilib: "32"` dan `init_rc` tersendiri.

Ini contoh bagus kenapa komentar di device tree ini layak dipertahankan:
catatan yang ditulis untuk menjelaskan keputusan lama ternyata menjadi
petunjuk langsung saat keadaannya berubah.

---

## 4. Zygote

`lineage_A37.mk` sekarang mewarisi `core_64_bit.mk`, yang menyediakan:

```
init.zygote64.rc  init.zygote64_32.rc
ro.zygote = zygote64_32          <- zygote 64-bit dengan anak 32-bit
TARGET_SUPPORTS_32_BIT_APPS := true
TARGET_SUPPORTS_64_BIT_APPS := true
```

`zygote64_32` yang dibutuhkan, bukan `zygote64`: proses 32-bit tetap harus bisa
di-fork untuk HAL kamera.

Perhatikan `base_vendor.mk:36` menyetel `ro.zygote?=zygote32` dengan `?=`
(soft assign), sehingga `ro.zygote=zygote64_32` dari `core_64_bit.mk` yang
menang. Ini perlu diperiksa ulang di `build.prop` hasil build.

---

## 5. Verifikasi

Dijalankan lewat `get_build_var` setelah `lunch lineage_A37-bp4a-userdebug`:

| Variabel | Nilai |
|---|---|
| `TARGET_ARCH` | `arm64` |
| `TARGET_CPU_ABI` | `arm64-v8a` |
| `TARGET_2ND_ARCH` | `arm` |
| `TARGET_2ND_CPU_ABI` | `armeabi-v7a` |
| `TARGET_KERNEL_ARCH` | `arm64` |
| `ro.zygote` | `zygote64_32` |
| paket kamera | `android.hardware.camera.provider-service_32.lineage` |
| paket `init.zygote*` | 3 |

Dan pada vendor tree, seluruh 322 entri `PRODUCT_COPY_FILES` diperiksa ulang
setelah pemasangan: **0 hilang**.

---

## 6. Yang belum dikerjakan

**Fase 3 (shim) sengaja dilewati untuk sementara.** Shim yang ada
(`libshim_camera`, `libcamera_shim`, `libshim_camera_sensor`) melayani blob
kamera yang **tetap 32-bit**, sehingga kemungkinan besar tidak perlu diubah.
Yang naik ke 64-bit hanya 114 pustaka yang sebagian besar tidak bershim.

Pendekatan yang dipilih: **bangun dulu, lihat apa yang benar-benar gagal**,
baru buat shim yang dibutuhkan. Membuat shim untuk masalah yang belum terbukti
ada hanya menambah variabel.

**Build belum dijalankan.** Itu Fase 4, dan di situlah kendala partisi 2.727 MB
akan terlihat nyata — `system.img` 32-bit sekarang 1.849 MB, dan dual-lib
diperkirakan menaikkannya ke 2.310-2.590 MB.

---

## 7. Berkas

```
0001-device-tree-64bit.patch   perubahan BoardConfig.mk, device.mk, lineage_A37.mk
```

Vendor tree tidak disertakan (114 MB); ia ada di cabang `lineage-23-64bit`
repo `rb-vendor_oppo_A37`.
