# Forward-port kernel OPPO A37 — 3.10.108 ke 4.4

Dokumen rencana. Ditulis 5 September 2026.
Semua angka di sini hasil pengukuran atau pemeriksaan langsung terhadap kode,
bukan perkiraan. Sumber tiap angka dicantumkan supaya bisa diperiksa ulang.

---

## 0. Vonis di depan

**Bisa dikerjakan, tetapi 4.4 adalah target yang salah.** Bukti terkuatnya satu
baris:

```
CAF msm-4.4  drivers/clk/msm : clock-gcc-8996.c  clock-gcc-8998.c        <- tidak ada 8916
CAF msm-4.9  drivers/clk/msm : clock-cpu-8939.c  clock-gcc-8909.c
                               clock-rpm-8909.c  clock-gcc-8952.c        <- keluarga kita
```

`clock-cpu-8939.c` adalah driver clock CPU untuk keluarga SoC A37 sendiri, dan
msm8909 praktis adalah msm8916 versi dipangkas. Keduanya ada di **4.9**, tidak
ada satupun di **4.4**.

Konsekuensinya: memilih 4.4 berarti memindahkan seluruh BSP msm8916 ke pohon
yang tidak mengenal SoC ini sama sekali — sementara 4.9 lebih baru, lebih aman
secara keamanan, dan sudah membawa SoC sekeluarga. **4.4 lebih banyak kerja
untuk hasil lebih buruk.**

Rencana di bawah tetap ditulis untuk 4.4 sesuai permintaan, dengan setiap titik
di mana 4.9 mengubah biaya ditandai `[4.9 LEBIH MURAH]`. Keputusan akhir ada di
§11.

---

## 1. Metode

Yang diperiksa, dan bagaimana:

| Sumber | Cara | Hasil |
|---|---|---|
| Pohon kernel kita | `find`/`git` lokal | §2 |
| CAF msm-4.4 | GitHub API cermin `android-linux-stable/msm-4.4` | §3.1 |
| CAF msm-4.9 | idem | §3.2 |
| CAF msm-3.18 | idem | §3.3 |
| CIP 4.4 SLTS | `kernel.org/pub/.../cip/4.4/` | §3.4 |
| Android common | `android.googlesource.com/kernel/common/+refs` | §3.5 |

CodeLinaro (`git.codelinaro.org`) membatasi laju permintaan otomatis (HTTP 429),
jadi isinya diperiksa lewat cermin GitHub `android-linux-stable/*` yang
menyalin rilis CAF apa adanya dan menggabungkan `linux-stable` di atasnya.
Cermin ini yang dipakai luas oleh pengembang kernel Android, dan nama cabangnya
(`kernel.lnx.4.4.r40-rel`) identik dengan tag CAF asli.

---

## 2. Titik berangkat: apa yang kita punya

```
versi          : 3.10.108
riwayat git    : 50 commit  <- impor vendor ter-squash, TIDAK ADA leluhur CAF
remote         : gh   = rigaz29/kernel_oppo_msm8939
                 ref  = acroreiser/android_kernel_lenovo_a6010 (donor backport)
DTS perangkat  : arch/arm/boot/dts/qcom/msm8916-mtp-15399.dts  (852 byte)
                 board-id <8 0 15399>, dibangun lewat CONFIG_MACH_15399
                 arch/arm64/boot/dts/qcom -> symlink ke arch/arm/boot/dts/qcom
defconfig      : lineageos_a37f_defconfig, 601 opsi `=y`, 0 modul
```

**Riwayat 50 commit itu penting.** Tidak ada leluhur CAF berarti tidak ada yang
bisa di-`rebase`. Forward-port ini bukan operasi git, melainkan pemindahan kode
per-subsistem dengan tangan.

### Volume kode yang harus ikut pindah

| Jalur | Baris | Berkas |
|---|---:|---:|
| `drivers/media/platform/msm` (kamera) | 229.333 | 404 |
| `drivers/power` | 118.383 | 134 |
| `drivers/video/msm` (MDSS tampilan) | 104.827 | 107 |
| `sound/soc/msm` | 99.736 | 65 |
| `drivers/input/touchscreen` | 87.410 | 111 |
| `drivers/platform/msm` | 83.072 | 113 |
| `drivers/soc/qcom` | 62.206 | 115 |
| `drivers/gpu/msm` (KGSL) | 45.405 | 61 |
| `drivers/thermal` | 23.815 | 26 |
| `drivers/crypto/msm` | 20.241 | 18 |
| **DTS `arch/arm/boot/dts/qcom`** | **179.285** | **800** |
| **Jumlah kasar** | **~1.050.000** | **~1.950** |

Angka ini batas atas. Yang benar-benar wajib jauh lebih kecil karena hanya
601 opsi yang aktif di defconfig, dan sebagian besar 800 berkas DTS itu milik
papan lain (QRD, CDP, SKU sekian) yang tidak kita pakai. Penyaringan nyata
dilakukan di Fase 0 (§8).

### Yang hilang dari 3.10, dan itu alasan proyek ini ada

Diperiksa langsung di pohon:

```
TIDAK ADA    eBPF            (kernel/bpf tidak ada, sys_bpf tidak terdaftar)
TIDAK ADA    cgroup v2       (CGROUP2_SUPER_MAGIC 0 kemunculan)
TIDAK ADA    overlayfs
TIDAK ADA    incremental-fs
ADA          cgroup v1
ADA          PSI             <- hasil backport kita sendiri
ADA          workingset      <- hasil backport kita sendiri
```

Tiga yang pertama adalah sebab **60 patch BPF-less userspace** harus ada di ROM
ini. Kernel 4.4 menutup ketiganya, dan itu imbalan utama proyek ini.

---

## 3. Survei sumber

### 3.1 CAF `msm-4.4` — cabang `kernel.lnx.4.4.r40-rel` (Linux 4.4.250)

Kerangka driver CAF **lengkap ada**:

```
drivers/video/fbdev/msm   120 entri   (MDSS)
drivers/gpu/msm            77 entri   (KGSL) — termasuk adreno_a3xx.c
drivers/soc/qcom          143 entri
drivers/clk/msm            31 entri
sound/soc/msm              19 entri
drivers/media/platform/msm  8 entri   <- kecil, kamera dipangkas
```

`adreno_a3xx.c` ada — Adreno **A306** milik A37 masih didukung KGSL 4.4.
Ini poin positif besar.

Tetapi dukungan SoC-nya salah keluarga:

```
clock  : 8996, 8998 saja
DTS    : apq8016 apq8096 apq8098 msm8916 msm8996 msm8998
         sdm455 sdm630 sdm636 sdm658 sdm660 sda6xx msmhamster
```

`msm8916` di daftar itu **menyesatkan**. Berkasnya hanya lima, dan penamaannya
mainline, bukan CAF:

```
msm8916.dtsi  msm8916-pins.dtsi  msm8916-mtp.dts  msm8916-mtp.dtsi  pm8916.dtsi
apq8016-sbc.dts  apq8016-sbc.dtsi  apq8016-sbc-pmic-pins.dtsi  apq8016-sbc-soc-pins.dtsi
```

CAF memakai `msm8916-pinctrl.dtsi`; mainline memakai `msm8916-pins.dtsi`. Dan
BSP CAF 3.10 kita punya **800** berkas DTS, bukan lima. Kesimpulannya: yang ada
di msm-4.4 adalah dukungan **upstream** msm8916 tingkat Dragonboard 410c —
CPU, clock dasar, pinctrl, UART, SD, USB. **Tanpa MDSS 8916, tanpa KGSL 8916,
tanpa kamera, tanpa audio WCD.**

### 3.2 CAF `msm-4.9` — cabang `kernel.lnx.4.9.r11-rel` (Linux 4.9.250)

```
clock : clock-cpu-8939.c   clock-gcc-8909.c   clock-rpm-8909.c
        clock-gcc-8952.c   clock-gcc-8953.c   clock-cpu-8953.c
DTS   : msm8917 (51 berkas)  msm8937 (32)  msm8909 (31)  sdm439 (30)
        msm8953 (59)  apq8053 (32)  sdm632  sdm670  sdm845
defconfig arm64 : msm8937_defconfig  msm8953_defconfig  sdm670  sdm845
```

msm8917/8937 adalah penerus langsung msm8916: sama-sama Cortex-A53 empat inti,
MDSS segenerasi, Adreno 3xx/5xx kecil, PMIC pm8916/pm8937 sekeluarga.
msm8909 adalah msm8916 dipangkas.

### 3.3 CAF `msm-3.18` — `kernel.lnx.3.18.r34-rel`

Punya `clock-gcc-8916.c`, `clock-rpm-8916.c`, `clock-cpu-8939.c`. Menjanjikan
di permukaan, tetapi DTS-nya hanya menyisakan **5 berkas** 8916/8939
(`msm8916-regulator.dtsi`, `msm8939-common.dtsi`, `msm8939-cpu.dtsi`,
`msm8916-mdss-panels.dtsi`, `msm8939-mdss-panels.dtsi`) — sisa yang dipakai
turunan msm8937, bukan BSP utuh. Tidak ada defconfig 8916/8939.

**Ditolak sebagai batu loncatan.** Biayanya hampir sama dengan langsung ke
sasaran akhir, tetapi hasilnya kernel yang sudah EOL dan tetap tanpa eBPF penuh.

### 3.4 CIP 4.4 SLTS — `kernel.org/pub/linux/kernel/projects/cip/4.4/`

```
rilis terbaru : linux-cip-4.4.302-cip114   19 Agustus 2026
varian RT     : linux-cip-4.4.302-cip113-rt62   30 Juli 2026

versi SLTS yang dirawat CIP: 4.4  4.19  5.10  6.1  6.12
```

**Ini membatalkan anggapan umum bahwa 4.4 mati sejak Februari 2022.** Yang mati
adalah LTS biasa (berhenti di 4.4.302). CIP melanjutkannya sebagai Super Long
Term Support dan masih merilis bulan lalu.

Nilainya untuk kita: **perbaikan keamanan**, bukan dukungan perangkat keras.
CIP murni generik — nol kode Qualcomm. Tidak bisa jadi basis, tetapi bisa
ditumpuk di atas basis CAF (§6).

Perhatikan selisihnya: CAF msm-4.4 berhenti di **4.4.250**, CIP di **4.4.302** —
52 rilis stabil tertinggal, lima tahun perbaikan keamanan.

### 3.5 Android common `android-4.4`

Seluruh cabangnya bertanda `deprecated/`:

```
deprecated/android-4.4        deprecated/android-4.4-o      deprecated/android-4.4-p
deprecated/android-4.4-llvm   deprecated/android-4.4-o-mr1  deprecated/android-4.4-p-release
deprecated/android-4.4.y      deprecated/android-4.4-o-release
```

Yang aktif sekarang: `android14-6.1`, `android15-6.6`, `android16-6.12`,
`android17-6.18`.

Google tidak lagi menambal 4.4 untuk Android. Patch Android yang kita butuhkan
(binder, ashmem, ION, lowmemorykiller, sync) sudah ada di dalam CAF msm-4.4 dan
msm-4.9, jadi cabang ini tidak diperlukan sebagai basis — hanya berguna sebagai
rujukan bila ada patch Android yang hilang.

### 3.5b CAF `msm-4.19` — diperiksa, ditolak

Menggoda karena CIP juga merawat 4.19. Tetapi SoC sasarannya generasi 2019 ke
atas: `sm8150` (msmnile), `sm6150` (talos/trinket), `kona`, `lito`, `atoll`,
`bengal`. **Tidak ada satupun keluarga 8916/8917/8937.**

Jaraknya dari msm8916 lebih jauh daripada msm-4.4, sementara biaya adaptasi API
lebih tinggi. Ditolak.

### 3.6 Ringkasan perbandingan

| | msm-4.4 | msm-4.9 |
|---|---|---|
| Versi | 4.4.250 | 4.9.250 |
| MDSS | 120 berkas | 123 |
| KGSL | 77 | 85 |
| `adreno_a3xx.c` (A306 kita) | ADA | ADA |
| eBPF | ADA (8) | ADA (12) |
| overlayfs | ADA | ADA |
| f2fs | 29 | 29 |
| ION | 20 | 24 |
| PSI | **TIDAK** | **TIDAK** |
| **clock keluarga 8916/8939** | **TIDAK** | **ADA** |
| **DTS SoC sekeluarga** | **TIDAK** | **msm8917/8937/8909** |

Catat: **tidak satupun punya PSI** (PSI baru masuk 4.20). Backport PSI yang
sudah kita kerjakan di 3.10 harus dikerjakan ulang untuk basis baru. Kabar
baiknya kita sudah tahu persis caranya, termasuk dua bug yang kita temukan
sendiri (`psi_flags` saat fork, dan invarian `tasks[]`).

---

## 4. Basis yang dipilih

**CAF `msm-4.4` cabang `kernel.lnx.4.4.r40-rel`, lalu ditumpuk 4.4.250 → 4.4.302
dari CIP.**

Alasan:

1. Kerangka driver CAF sudah ada, dan driver kita ditulis dengan idiom CAF yang
   sama. Memindahkan MDSS 3.10 ke MDSS 4.4 jauh lebih murah daripada ke
   `drivers/gpu/drm/msm` mainline yang arsitekturnya berbeda total.
2. `adreno_a3xx.c` ada — GPU kita tidak perlu ditulis ulang.
3. Patch Android (binder/ION/ashmem) sudah menyatu.
4. Menumpuk CIP menutup lubang keamanan lima tahun tanpa mengorbankan BSP.

Yang **tidak** dipilih dan alasannya:

- **CIP murni sebagai basis** — nol kode Qualcomm; berarti menulis ulang seluruh
  BSP dari nol, bukan memindahkannya.
- **`android-4.4`** — deprecated, dan tidak membawa BSP.
- **msm-3.18 sebagai batu loncatan** — biaya hampir sama, hasil lebih buruk (§3.3).
- **mainline 6.x** — dibahas terpisah di §10, karena ini alternatif serius,
  bukan penolakan.

---

## 5. Analisis kesenjangan

Empat lapisan yang harus dijembatani, diurutkan menurut biaya.

### 5.1 API internal kernel (3.10 → 4.4, lima tahun)

Yang paling banyak menyentuh driver kita:

| Perubahan | Rentang | Dampak |
|---|---|---|
| `clk` framework: `struct clk` jadi buram, `clk_hw` wajib | 3.15–4.0 | seluruh `drivers/clk/msm` kita |
| Regulator: `regulator_ops` berubah, devm makin wajib | 3.13+ | PMIC pm8916, SPMI |
| `fbdev` → CAF pindah ke `drivers/video/fbdev/msm` | 3.18 | seluruh MDSS |
| V4L2: `media_entity` refactor, `vb2` berubah | 3.16–4.0 | seluruh kamera |
| ASoC: `snd_soc_codec` → `component` dimulai | 4.4+ | audio WCD |
| IOMMU: `iommu_group`, `arm-smmu` ditulis ulang | 3.16–4.2 | KGSL, MDSS, kamera |
| DMA API: `dma_map_ops` berubah, CMA | 3.16+ | ION, semua DMA |
| `struct file_operations`: `read_iter`/`write_iter` | 3.16 | tiap char device |
| PM/QoS + `cpuidle` ditulis ulang | 3.19+ | lpm-levels 8916 |
| `genirq`/`irqdomain` hierarkis | 3.17+ | GIC, SPMI, GPIO |
| sysfs/kobject: atribut jadi `const` | 3.11+ | luas, tapi mekanis |
| `timer` API: `setup_timer` → `timer_setup` | 4.15 | **tidak kena** di 4.4 |

Yang terakhir menunjukkan keuntungan berhenti di 4.4/4.9 dibanding 5.x: banyak
perubahan API paling menyakitkan (timer, `access_ok`, `get_user_pages`,
`ioremap_nocache`, folio) terjadi **setelah** 4.9.

### 5.2 BSP SoC — inti pekerjaan

Yang harus dipindah dari 3.10 kita:

```
clock-gcc-8916.c   clock-rpm-8916.c   clock-cpu-8939.c     [4.9 LEBIH MURAH: sudah ada]
pinctrl msm8916                                            [4.9 LEBIH MURAH: 8917 nyaris identik]
DTS SoC msm8916 + pm8916 + msm8916-mtp-15399               [4.9 LEBIH MURAH: 8917/8909 jadi rujukan]
lpm-levels / cpuidle 8916
spmi-pmic-arb + pm8916 regulator/GPIO/MPP
sdhci-msm (eMMC/SD)
MDSS: mdss_mdp, mdss_dsi, panel A37                        <- blok terbesar tunggal
KGSL: bagian 8916 (gpu clock, IOMMU, DT)
sound/soc/msm: msm8x16-slimbus + WCD9306/9326 codec
prima (WLAN, in-kernel, drivers/staging/prima)
kamera msm: 66 blob userspace bergantung padanya            <- risiko tertinggi
```

### 5.3 ABI ke userspace — risiko yang paling sering diremehkan

433 berkas proprietary dipakai A37:

```
kamera   : 66 blob
radio    : 18
gpu      : 14  (driver userspace Adreno, bicara ke KGSL lewat ioctl)
audio    :  6
```

Blob ini dibangun untuk kernel 3.10. Yang berisiko putus:

- **KGSL ioctl** — relatif stabil antar versi CAF, risiko sedang.
- **MDSS fb ioctl** — `MSMFB_*`, dipakai HAL gralloc/hwcomposer, risiko sedang.
- **Kamera** — `msm_cam` ioctl dan subdev V4L2 berubah banyak antara 3.10 dan
  4.4. **Risiko tertinggi, dan berpotensi menjadi penghenti proyek.**
- **Audio** — kontrol mixer ALSA; nama kontrol harus dipertahankan persis
  (kita sudah tahu betapa sensitifnya ini dari pekerjaan `RX1 Digital Volume`).

### 5.4 Integrasi Android

Yang menjadi lebih mudah:

- **60 patch BPF-less bisa dipensiunkan** — eBPF tersedia.
- cgroup v2 memungkinkan hierarki terpadu yang diharapkan Android 16.
- overlayfs membuka jalan bagi fitur yang selama ini kita hindari.

Yang menjadi pekerjaan baru:

- **Backport PSI harus diulang** untuk basis baru (kita sudah punya patchnya).
- `sepolicy` kemungkinan besar perlu penyesuaian.
- `fstab`, `init.target.rc`, dan seluruh setelan sysfs yang kita hafal
  (`default_pwrlevel`, `process_reclaim`, mixer) harus divalidasi ulang.

---

## 6. Menumpuk CIP di atas CAF

Setelah basis CAF berdiri:

```
git remote add cip https://git.kernel.org/pub/scm/linux/kernel/git/cip/linux-cip.git
git fetch cip v4.4.302-cip114
```

Terapkan bertahap, bukan sekaligus: 4.4.250 → 4.4.260 → ... → 4.4.302, uji boot
tiap tahap. Konflik akan terpusat di `drivers/` yang disentuh CAF. Ini pekerjaan
mekanis dan bisa ditunda sampai Fase 6 — jangan lakukan sebelum perangkat boot,
karena akan mencampur dua sumber kegagalan.

---

## 7. Kriteria lulus tiap fase

Setiap fase punya satu ukuran objektif. Tidak lanjut sebelum terpenuhi.

| Fase | Kriteria lulus |
|---|---|
| 0 | Basis terbangun (`make msm_defconfig && make`), belum boot |
| 1 | Konsol serial/ramoops hidup, `console_init` tercapai |
| 2 | `adb shell` jalan, `/data` termount |
| 3 | Bootanimation terlihat di layar |
| 4 | SurfaceFlinger `usesDeviceComposition=true`, tanpa fallback GPU |
| 5 | Audio, WiFi, sensor, telepon berfungsi |
| 6 | LOS 23 boot penuh, 60 patch BPF-less dicabut, PSI aktif |
| 7 | Stabil 72 jam, tidak ada regresi vs 3.10 |

---

## 8. Rencana kerja

### Fase 0 — Persiapan dan penyaringan (perkiraan 20–40 jam)

1. Buat repo baru, impor `kernel.lnx.4.4.r40-rel` sebagai commit dasar dengan
   riwayat utuh (jangan di-squash — kita akan sangat membutuhkannya).
2. **Saring DTS.** Dari 800 berkas, tentukan yang benar-benar dirujuk
   `msm8916-mtp-15399.dts` secara transitif. Perkiraan hasil: 60–100 berkas.
   Ini menurunkan volume DTS dari 179K baris menjadi mungkin ~25K.
3. **Saring driver.** Dari 601 opsi `=y`, petakan tiap opsi ke berkas sumber.
   Buang yang tidak dipakai A37 (papan QRD/CDP, sensor yang tidak terpasang).
4. Bangun basis apa adanya untuk memastikan toolchain benar.

Keluaran: daftar berkas wajib yang terukur, bukan tebakan. **Fase ini yang
menentukan apakah sisa rencana realistis.**

### Fase 1 — Boot ke konsol (60–120 jam)

Urutan wajib, tiap langkah menopang berikutnya:

1. DTS SoC minimal: CPU, memori, timer, PSCI, GIC.
2. `clock-gcc-8916.c` + `clock-rpm-8916.c` diadaptasi ke `clk_hw`.
   `[4.9 LEBIH MURAH: tinggal pakai]`
3. pinctrl msm8916. `[4.9 LEBIH MURAH: adaptasi dari 8917]`
4. UART (`msm_serial_hs`) + `earlycon`.
5. ramoops sudah dikonfigurasi di cmdline kita — manfaatkan untuk log crash awal.

Titik gagal paling umum: clock. Kalau GCC salah, tidak ada yang hidup dan tidak
ada log. Siapkan `earlycon` sebelum apapun.

### Fase 2 — Penyimpanan dan init (40–80 jam)

1. `spmi-pmic-arb` + `pm8916` regulator.
2. `sdhci-msm` untuk eMMC.
3. USB gadget + ADB.
4. Boot ramdisk LOS, jalankan `init`.

Kriteria lulus: `adb shell` menyala. Sejak titik ini seluruh alat diagnosis
yang kita pakai sepanjang proyek ini bisa dipakai lagi.

### Fase 3 — Tampilan (100–200 jam) — blok terbesar

MDSS kita 104.827 baris. Basis 4.4 punya MDSS 120 berkas untuk SoC lain, jadi
ini **adaptasi**, bukan penulisan ulang: bandingkan `mdss_mdp` 3.10 kita dengan
4.4, pindahkan bagian khusus 8916 (versi MDP, konfigurasi DSI PHY, panel).

Panel A37 ada di DTS kita. Ini yang paling mungkin memakan waktu di luar dugaan
— pengalaman kita dengan `mdss_dsi_event` menunjukkan subsistem ini penuh
kejutan.

### Fase 4 — GPU (40–80 jam)

`adreno_a3xx.c` sudah ada di basis. Pekerjaannya: DT KGSL, clock GPU, IOMMU,
lalu memastikan blob Adreno userspace (14 berkas) menerima ioctl KGSL 4.4.
Uji paling awal: `kgsl-3d0` muncul di sysfs, `gpuclk` terbaca.

### Fase 5 — Sisanya (150–300 jam)

Berurutan menurut risiko naik: audio → WiFi (`prima`) → sensor → BT → modem →
**kamera terakhir**. Kamera 229K baris dengan 66 blob adalah kandidat terkuat
untuk dinyatakan gagal; rencanakan kemungkinan A37 kehilangan kamera.

### Fase 6 — Integrasi Android (60–120 jam)

1. Cabut 60 patch BPF-less, aktifkan eBPF di userspace LOS.
2. Backport ulang PSI (patch kita sendiri, sudah terbukti).
3. Tumpuk CIP 4.4.250 → 4.4.302.
4. sepolicy, fstab, `init.target.rc`.

### Fase 7 — Stabilisasi (60+ jam)

Ulangi seluruh pengukuran yang sudah jadi patokan di proyek ini: FPS
`timestats`, PSI, `allocstall`, suhu, `dumpsys meminfo`. Bandingkan langsung
dengan angka 3.10 yang sudah kita punya.

**Total kasar: 530–1.100 jam.** Rentangnya lebar karena kamera dan MDSS bisa
meleset jauh. Bandingkan dengan penilaian komunitas untuk pekerjaan serupa di
msm8916 — "multiple hundreds of hours" — yang sejalan dengan angka ini.

---

## 9. Register risiko

| Risiko | Peluang | Dampak | Mitigasi |
|---|---|---|---|
| Blob kamera tidak kompatibel | tinggi | fitur hilang permanen | Terima kemungkinan A37 tanpa kamera; kerjakan paling akhir |
| MDSS jauh lebih sulit dari perkiraan | sedang | jadwal molor 2x | Fase 3 diberi anggaran terbesar; gagal cepat lebih baik |
| Blob GPU menolak ioctl KGSL 4.4 | sedang | tidak ada akselerasi | Uji ioctl lebih awal di Fase 4, sebelum investasi besar |
| Clock salah, tidak ada log | sedang | buntu di Fase 1 | `earlycon` + ramoops disiapkan lebih dulu |
| Proyek ditinggalkan separuh jalan | tinggi | 3.10 tetap dipakai | Tiap fase berdiri sendiri; 3.10 tidak pernah disentuh |
| 4.4 EOL, tidak ada patch keamanan CAF | pasti | kerentanan | Tumpuk CIP (§6) |

Mitigasi terpenting ada di baris kelima: **kerjakan di repo terpisah.** Pohon
3.10 yang sekarang berfungsi tidak boleh disentuh sama sekali. ROM yang jalan
sekarang tetap jalan apa pun yang terjadi pada proyek ini.

---

## 10. Alternatif yang harus ikut ditimbang

### 10.1 CAF msm-4.9 alih-alih 4.4 `[DIREKOMENDASIKAN]`

Lebih baru, masih di sisi "sebelum" perubahan API paling menyakitkan, dan
membawa `clock-cpu-8939.c` plus DTS msm8917/8937/8909 sebagai rujukan dekat.
Struktur rencana di atas berlaku tanpa perubahan; yang berubah hanya biaya
Fase 1 dan 2 yang turun cukup besar.

Kelemahan: 4.9 juga EOL (Januari 2023) dan **tidak punya padanan CIP** — CIP
SLTS merawat 4.4, 4.19, 5.10, 6.1, dan 6.12, tetapi melewati 4.9. Jadi 4.4+CIP
unggul dalam keamanan jangka panjang, sementara 4.9 unggul dalam biaya
pengerjaan.

Versi CIP lain tidak menolong: 4.19 ke atas sudah kehilangan seluruh keluarga
SoC kita (§3.5b), jadi 4.4 adalah satu-satunya versi yang sekaligus dirawat CIP
**dan** masih membawa kerangka driver CAF yang cocok.

**Pertukarannya jujur begini:** 4.4 lebih aman tapi lebih mahal dikerjakan;
4.9 lebih murah tapi tanpa dukungan keamanan berkelanjutan.

### 10.2 Mainline 6.x lewat `msm8916-mainline`

Proyek `msm8916-mainline` dan postmarketOS sudah menjalankan msm8916 di kernel
6.x dengan DRM/KMS berfungsi dan GPU lewat freedreno. Ini jalur yang paling
hidup secara upstream.

Tetapi arahnya berbeda: itu menukar seluruh tumpukan HAL Android CAF dengan
tumpukan mainline. Blob kamera, audio, dan RIL kita tidak akan dipakai. Untuk
LineageOS 23 yang bergantung pada HAL vendor, ini bukan forward-port melainkan
proyek yang sama sekali lain.

Layak dipertimbangkan **kalau** tujuannya distribusi Linux, bukan Android.

### 10.3 Tetap di 3.10

Pilihan yang sah, dan sejauh ini terbukti. Proyek ini sudah membuktikan 3.10
bisa menjalankan Android 16 dengan 60 patch userspace. Biaya pemeliharaannya
nyata tetapi terukur, dan setiap pengukuran di sesi-sesi terakhir menunjukkan
sistemnya sehat: PSI 0,18%, lmkd nol pembunuhan, komposisi tanpa fallback GPU.

Yang benar-benar dibeli dengan 530–1.100 jam: eBPF, cgroup v2, overlayfs, dan
pencabutan 60 patch. **Tidak ada satupun dari itu yang akan terasa oleh
pengguna A37.** Yang membatasi perangkat ini CPU dan RAM, dan kernel 4.4 tidak
mengubah keduanya.

---

## 11. Gerbang keputusan

Tiga pertanyaan, berurutan. Jangan lanjut kalau jawabannya tidak.

1. **Tujuannya belajar atau hasil?** Kalau hasil untuk pengguna A37, §10.3
   menang telak. Kalau belajar forward-port kernel, proyek ini sangat berharga.
2. **4.4 atau 4.9?** Bukti di §3 mengarah kuat ke 4.9 kecuali dukungan keamanan
   CIP jadi syarat mutlak.
3. **Bersedia kehilangan kamera?** Kalau tidak, hentikan sekarang — §5.3
   menempatkan ini sebagai risiko tertinggi dan tidak ada mitigasi yang murah.

Kalau ketiganya lolos, mulai dari **Fase 0** dan jangan lewati penyaringannya.
Fase 0 murah, dan hasilnya yang menentukan apakah sisa rencana ini realistis
atau optimistis.

---

## 12. Rujukan

Diberikan dalam permintaan:

- CodeLinaro — https://git.codelinaro.org/explore
- CIP 4.4 SLTS — https://www.kernel.org/pub/linux/kernel/projects/cip/4.4/
- Android common kernel — https://android.googlesource.com/kernel/common/

Dipakai dalam riset ini:

- Cermin CAF msm-4.4 — https://github.com/android-linux-stable/msm-4.4
  (`kernel.lnx.4.4.r40-rel`, Linux 4.4.250)
- Cermin CAF msm-4.9 — https://github.com/android-linux-stable/msm-4.9
  (`kernel.lnx.4.9.r11-rel`, Linux 4.9.250)
- Cermin CAF msm-3.18 — https://github.com/android-linux-stable/msm-3.18
- msm8916-mainline — https://github.com/msm8916-mainline
- postmarketOS MSM8916 — https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_410_(MSM8916)
- Diskusi 4.4.x untuk msm8916 — https://xdaforums.com/t/how-to-build-linux-4-4-x-for-galaxy-msm8916-devices.4523411/

Dokumen terkait di repo ini:

- `../PLAN-BACKPORT-KERNEL.md` — backport fitur ke 3.10 (arah sebaliknya)
- `../PLAN-LOS23.md` — 60 patch BPF-less dan alasannya
- `../RILIS.md` — jebakan build rilis
