# Kit port LineageOS 23.2 — OPPO A37 (msm8916)

Lanjutan dari [`android_build_oppo_A37-22`](https://github.com/rigaz29/android_build_oppo_A37-22),
yang berakhir dengan ROM 22.2 stabil dan dipakai harian di perangkat.

Repo ini **baru berisi rencana**, belum ada kode. Isinya hasil analisis kode
sumber, bukan perkiraan.

| Berkas | Isi |
|---|---|
| [`PLAN-LOS23.md`](PLAN-LOS23.md) | Dokumen utama. Rencana kernel wajib/opsional, userspace, device tree, 8 fase kerja |
| `analysis/kernel-22.2-to-23.2.txt` | 167 commit kernel a6010 dari `lineage-22.2` ke `lineage-23.2` |

## Tiga temuan yang membentuk seluruh rencana

**1. Android 16 menolak kernel kita dua kali, dan fatal.**
`NetBpfLoad.cpp:1629` menuntut kernel 5.4, `:1648` menuntut kernel 64-bit.
Keduanya `return`, bukan peringatan. Kernel A37 adalah 3.10.108 ARM 32-bit.

**2. Biaya eBPF sepuluh kali lipat dugaan awal.**
Bukan 98 commit melainkan ~1.300, karena cgroup v2 harus di-backport lebih dulu —
dan itu tidak terlihat di selisih `22.2..23.2` karena sudah masuk sebelumnya.

**3. SkiaGL sudah pernah dicoba di A37 dan menjatuhkan SurfaceFlinger.**
Android 16 membuang mesin GLES lama, jadi `debug.renderengine.backend=gles` yang
dipakai 22.2 menjadi tidak bermakna dan perangkat akan diam-diam mendapat SkiaGL.

Rinciannya, lengkap dengan kutipan kode dan nomor baris, ada di `PLAN-LOS23.md`.

## Basis

| Komponen | Sumber |
|---|---|
| Kernel | `rigaz29/kernel_oppo_msm8939` branch `lineage-22` |
| Device tree | `rigaz29/rb_device_oppo_A37` branch `lineage-22` |
| Vendor blob | `rigaz29/rb-vendor_oppo_A37` |

## Rujukan yang dipakai

- [LineageOS](https://github.com/LineageOS) — manifest dan sumber 23.2
- [Ultra-Legacy-Hippeastrum](https://github.com/Ultra-Legacy-Hippeastrum) — fork `lineage-23.2` untuk perangkat legacy
- [acroreiser](https://github.com/acroreiser) — a6010 (msm8916, kernel 3.10) sudah sampai `lineage-23.2`
- [MisterZtr](https://github.com/MisterZtr) — patch GSI
- [LineageOS-UL](https://github.com/LineageOS-UL) — pendahulu ULH, berhenti di `lineage-21.0`

## Menyiapkan ulang `src/`

`src/` dan `ref/` sengaja tidak ikut di-commit (3,1 GB, semuanya klon repo publik):

```sh
mkdir -p src ref && cd src
git clone --depth 1 -b lineage-23.2 https://github.com/LineageOS/android.git manifest-23.2
git clone --depth 1 -b lineage-22.2 https://github.com/LineageOS/android.git manifest-22.2
git clone --filter=blob:none --no-single-branch https://github.com/acroreiser/android_kernel_lenovo_a6010.git kernel-a6010
git clone --filter=blob:none -b lineage-22 https://github.com/rigaz29/kernel_oppo_msm8939.git kernel-a37
git clone --filter=blob:none --no-single-branch https://github.com/acroreiser/android_device_lenovo_a6010.git dt-a6010
git clone --filter=blob:none -b lineage-23.2 https://github.com/LineageOS/android_packages_modules_Connectivity.git conn-23.2
mkdir ulh && cd ulh
for r in android_bionic android_system_core android_system_sepolicy \
         android_hardware_ril android_frameworks_native; do
  git clone --filter=blob:none -b lineage-23.2 \
    "https://github.com/Ultra-Legacy-Hippeastrum/$r.git" "$r"
done
```

Untuk membandingkan kernel A37 dengan referensi:

```sh
cd src/kernel-a37
git remote add ref https://github.com/acroreiser/android_kernel_lenovo_a6010.git
git fetch --filter=blob:none ref lineage-22.2 lineage-23.2
```
