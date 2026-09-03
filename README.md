# Kit port LineageOS 23.2 — OPPO A37 (msm8916)

Lanjutan dari [`android_build_oppo_A37-22`](https://github.com/rigaz29/android_build_oppo_A37-22),
yang berakhir dengan ROM 22.2 stabil dan dipakai harian di perangkat.

Isinya hasil analisis kode sumber, bukan perkiraan. Fase 0 (analisis) selesai;
Fase 1 (menyiapkan pohon) sedang berjalan.

| Berkas | Isi |
|---|---|
| [`PLAN-LOS23.md`](PLAN-LOS23.md) | Dokumen utama. Rencana kernel wajib/opsional, userspace, device tree, 8 fase kerja |
| [`RILIS.md`](RILIS.md) | Membangun ROM rilis: kunci penandatanganan, jebakan `testkey.x509.pem`, kenapa varian `user` tidak bisa boot, `-j4` dan ruang disk |
| `analysis/kernel-22.2-to-23.2.txt` | 167 commit kernel a6010 dari `lineage-22.2` ke `lineage-23.2` |
| [`A37-23.xml`](A37-23.xml) | Local manifest LOS 23.2. 8 `remove-project`, 16 project, 14 linkfile — sudah divalidasi parser XML dan diuji `repo manifest` |

## Tiga temuan yang membentuk seluruh rencana

**1. Android 16 menolak versi kernel kita, dan itu fatal.**
`NetBpfLoad.cpp:1629` menuntut kernel 5.4 dan `return`, bukan sekadar
memperingatkan. Kernel A37 adalah 3.10.108.

Gerbang 64-bit di `:1647` **tidak** menyala: kernel A37 dibangun arm64
(`BoardConfig.mk:301`) meski userspace-nya 32-bit, dan `isKernel64Bit()` berpindah
personality dulu sebelum membaca `uname()` sehingga tetap melihat `aarch64`.
Perbaikannya karena itu cuma satu baris defconfig, bukan pekerjaan kernel.

**2. eBPF dan cgroup v2 TIDAK wajib di-backport.**
Ada rantai patch userspace yang sudah jadi dan terbukti: `zhafknight/los_patches`
menjalankan LineageOS 23.2 di Galaxy Note N7000 — kernel 3.0, jauh lebih tua dari
A37 — dengan **cgroup v1** dan **BPF-less networking**. Patch kuncinya mengubah
gerbang fatal `NetBpfLoad` menjadi peringatan.

Perbandingannya: **89 patch userspace** lawan **~1.300 commit kernel** (backport
cgroup v2 + eBPF ala acroreiser). Jalur userspace yang dipilih; backport kernel
turun status menjadi opsional.

**3. SkiaGL sudah pernah dicoba di A37 dan menjatuhkan SurfaceFlinger.**
Android 16 membuang mesin GLES lama, jadi `debug.renderengine.backend=gles` yang
dipakai 22.2 menjadi tidak bermakna dan perangkat akan diam-diam mendapat SkiaGL.

**4. LineageOS 23.2 tidak lagi mengenal msm8916.**
`grep -c msm8916` pada `hardware/qcom-caf/common` 23.2 menghasilkan **0** di
`qcom_boards.mk`, `qcom_defs.mk`, dan `BoardConfigQcom.mk`; platform tertua yang
tersisa `msm8937`. ULH `legacy_support_patches` mengembalikannya. Tanpa itu
`QCOM_HARDWARE_VARIANT` tidak terisi dan pohon tidak bisa dibangun untuk A37.

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
- [MisterZtr](https://github.com/MisterZtr) — `LineageOS_gsi`, patch GSI `lineage-23.2`
- [zhafknight](https://github.com/zhafknight) — `los_patches`, 89 patch LOS 23.2 untuk N7000 (kernel 3.0); bukti bahwa BPF-less berjalan
- [Mi-Thorium](https://github.com/Mi-Thorium) — msm8937/SDM439 di branch `a16_qpr2` dan `a17`; rujukan migrasi HIDL→AIDL dan bukti kedua bahwa Android 16 tidak menuntut perubahan kernel
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
