# Forward-port kernel A37 — pindah repo

Rencana ini sekarang hidup di repo terpisah:

**https://github.com/rigaz29/kernel_oppo_msm8939-419**

Alasannya ada di rencana itu sendiri: pohon 3.10 yang sekarang berfungsi tidak
boleh disentuh, jadi pekerjaan forward-port dikerjakan terpisah. ROM yang jalan
sekarang tetap jalan apa pun yang terjadi di sana.

## Ringkasan temuan

Sasaran **4.19**, bukan 4.4 seperti rencana awal:

```
LineageOS/android_kernel_xiaomi_msm8937   cabang lineage-23.2   Linux 4.19.325
  ADRENO_REV(ADRENO_REV_A306, 3, 0, 6, 0)   <- GPU A37 tepat
  clock-cpu-8939.c                          <- clock CPU keluarga SoC kita
  cabang lineage-23.2                       <- versi ROM kita persis
```

Yang lebih baru justru lebih mudah, karena pekerjaannya bukan memindahkan 3.10
maju sembilan tahun melainkan menambahkan selisih msm8916 ke pohon msm8937 yang
sudah boot di ponsel sungguhan.

Versi dokumen sebelumnya (commit `ee58b17`) menyimpulkan 4.4/4.9 dan itu salah:
yang disurvei hanya pohon CAF mentah, kernel perangkat LineageOS tidak pernah
diperiksa.
