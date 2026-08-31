# Kandidat backport kernel berikutnya — OPPO A37, kernel 3.10.108

Ditulis 30 Agustus 2026. **Belum dikerjakan.** Dicatat sekarang supaya tidak
hilang, dikerjakan setelah Adiantum terbukti.

Pembanding sepanjang dokumen ini adalah `acroreiser/android_kernel_lenovo_a6010`
branch `lineage-23.2` (`/root/a37-23/src/kernel-a6010`). Alasannya bukan
kebetulan:

- kernel **3.10.108 yang sama persis**
- msm8916 sekeluarga, generasi LineageOS yang sama (23.2)
- seluruh kode kandidat di bawah ada di `mm/`, `kernel/sched/`, `lib/` —
  **tidak bergantung arsitektur**, meski pohon mereka arm32 dan kita arm64

Itu sebabnya backport f2fs dari mereka kemarin berjalan mulus, dan itu pula yang
membuat daftar ini jauh lebih murah daripada mengambil dari mainline.

---

## 0. Apa yang berubah sejak `PLAN-PSI-EBPF.md`

Dokumen itu (`android_build_oppo_A37-22`, 18 Agustus 2026) sudah menilai PSI
LAYAK dan eBPF TIDAK DISARANKAN. Kesimpulannya masih berlaku. Yang berubah satu
hal, dan besar:

> Rencana lama mengasumsikan PSI diambil dari **mainline v4.20** lalu diadaptasi
> sendiri ke 3.10. Ternyata acroreiser **sudah mengerjakan adaptasi itu**, di
> versi kernel yang sama, dan sudah menambal enam bug lanjutan di atasnya.

Dua dari empat "kesulitan yang HARUS diantisipasi" di dokumen lama — perbedaan
API scheduler (butir 3) dan perubahan API `percpu`/`seqcount` (butir 4) — sudah
terpecahkan di pohon donor. Sisanya (`sched_clock()` belum sinkron saat boot
awal, dan penambahan anggota `task_struct`) tetap harus diperiksa sendiri.

---

## 1. Inventaris: ada di acroreiser, tidak ada di kita

Diambil dengan membandingkan isi direktori, bukan dari ingatan:

```
kernel/sched/psi.c              <- prioritas 1
kernel/sched/cpufreq_schedutil.c
kernel/sched/membarrier.c
kernel/sched/qhmp_core.c, qhmp_fair.c, qhmp_sched.h
kernel/sched/wait.c
mm/workingset.c                 <- prioritas 2
mm/list_lru.c                   <- prioritas 2 (prasyarat workingset)
mm/vmacache.c                   <- prioritas 3
mm/userfaultfd.c                <- JANGAN, lihat §5
lib/lockref.c                   <- prioritas 3
lib/win_minmax.c, lib/xxhash.c, lib/zstd, lib/lz4kd
lib/percpu-refcount.c, lib/percpu_ida.c, lib/once.c, lib/clz_ctz.c
lib/test_bpf.c  (+ kernel/bpf/, 20 berkas)   <- JANGAN, lihat §5
```

Arah sebaliknya — yang kita punya dan mereka tidak — semuanya sisa lama:
`drivers/staging/android/{binder*,logger*,lowmemorykiller,alarm-dev}`.
Mereka sudah pindah ke `drivers/android/` (dengan `binderfs`) dan membuang
`logger` serta `lowmemorykiller`.

---

## 2. Prioritas 1 — PSI (Pressure Stall Information)

### Keadaan

```
                          A37          acroreiser
kernel/sched/psi.c        tidak ada    1289 baris
include/linux/psi.h       tidak ada      63
include/linux/psi_types.h tidak ada     170
                                      -----
                                       1522 baris berkas baru
```

Titik kait di luar `psi.c`, sepuluh berkas:

```
kernel/cgroup/cgroup.c      kernel/sched/sched.h    mm/page_alloc.c
kernel/sched/stats.h        mm/compaction.c         mm/filemap.c
include/linux/cgroup.h      mm/vmscan.c             include/linux/psi.h
```

Sudah matang di sana — enam commit perbaikan menyusul di atas backport awalnya:

```
8b4353299f7  BACKPORT: cgroup: make per-cgroup pressure stall tracking configurable
0528597a9c0  Revert "sched: psi: set RT priority 98 to psimon thread"
edc42e6fc49  sched: psi: set RT priority 98 to psimon thread
138595ce335  psi: Fix a division error in psi poll()
a4eab5a8c18  sched/psi: create /proc/pressure/* only when psi enabled
3145d9be832  BACKPORT: psi: Fix uaf issue when psi trigger is destroyed while being polled
```

Perhatikan pasangan `edc42e6fc49` lalu `0528597a9c0` — mereka menaikkan prioritas
RT `psimon` lalu **mencabutnya kembali**. Jangan salin keadaan pertengahan; ikuti
keadaan akhir branch. Pelajaran yang sama seperti ROW iosched di
`PLAN-LOS23.md` §6.

Defconfig mereka: `CONFIG_PSI=y`, `# CONFIG_PSI_DEFAULT_DISABLED is not set`.

### Kenapa ini yang teratas

ROM kita **sudah ditulis dengan mengharapkan PSI**:

```
device/oppo/A37/device.mk:1031   ro.lmk.use_psi=false
arch/arm64/configs/lineageos_a37f_defconfig:540
                                 # CONFIG_ANDROID_LOW_MEMORY_KILLER is not set
```

lmkd userspace sudah yang bekerja (driver in-kernel mati), tapi jalannya lewat
vmpressure. Catatan panjang di `device.mk:1005-1030` sudah mencatat bahwa kalau
PSI tersedia, `ro.lmk.use_psi` harus `true` dan `ro.lmk.use_new_strategy`
seharusnya default `true` karena `ro.config.low_ram=true`.

Bedanya: vmpressure memberi rasio efisiensi pemindaian yang kasar; PSI memberi
**waktu tersendat sebenarnya** dalam mikrodetik.

### ⚠️ Kejujuran yang harus ikut tercatat

Jalur vmpressure sekarang **terukur bekerja benar**. Dari catatan di
`device.mk`: di bawah tekanan nyata lmkd membunuh 4-5 proses berurutan menurut
`oom_score_adj` (975, 985, 995) tanpa menyentuh aplikasi depan, dan OOM killer
kernel tidak pernah ikut campur.

Jadi PSI adalah **peningkatan akurasi keputusan, bukan perbaikan kerusakan**.
Sama seperti peringatan di `PLAN-PSI-EBPF.md` §2: kerjakan hanya kalau app-kill
masih terasa mengganggu setelah tuning zram/swappiness.

### Verifikasi

Ikuti `PLAN-PSI-EBPF.md` §5 apa adanya — `/proc/pressure/*` ada, angkanya
bergerak di bawah tekanan, lmkd benar-benar memakainya, lalu pembanding app-kill
dengan metode yang sama seperti sebelumnya.

---

### SELESAI — 31 Agustus 2026, branch `psi` (`367e1f5c7d07`)

```
/proc/pressure/cpu     some avg10=72.80  total=45239951
/proc/pressure/io      some avg10=11.36  full avg10=5.50
/proc/pressure/memory  0 -> some total=1458600 setelah 1,2 GB
                       ditulis-baca dengan cache dibuang
[psimon] berjalan       dmesg nol WARNING/BUG/Oops
```

`ro.lmk.use_psi` masih `false` — lmkd belum memakainya. Sengaja dipisah.

#### Yang dilewatkan perkiraan di atas

Hitungan "1522 baris + kait di 10 berkas" benar untuk PSI-nya sendiri, tetapi
**melewatkan seluruh lapisan pendukung**. PSI hulu memakai API yang tidak ada di
3.10, dan acroreiser punya karena pohon mereka lebih dimodernkan secara
keseluruhan:

```
kthread_delayed_work    shim di atas primitif 3.10
wq_worker_last_func     backport dari 4.20
jiffies_to_nsecs        pembantu kecil
calc_load, calc_load_n, this_rq_lock, __task_rq_lock, __task_rq_unlock
                        dibuka dari static di core.c
PF_MEMSTALL             0x00000001, BUKAN 0x01000000 -- bit itu sudah
                        dipakai PF_SPREAD_PAGE di pohon ini
task_struct             psi_flags, sched_psi_wake_requeue
```

Inti `kthread_worker` 4.9 **tidak** diganti: strukturnya tidak kompatibel
(menambah `delayed_work_list` dan `canceling`, membuang `kthread_work.done`) dan
renamenya menyentuh 11 pemakai termasuk `drivers/gpu/msm/kgsl.c` dan
`adreno_dispatch.c`.

#### Tiga kegagalan boot, dan pelajarannya

| | penyebab | sifat |
|---|---|---|
| 1 | `psi_disabled` di `.bss` = false; PSI hidup sebelum `psi_init()` | urutan |
| 2 | `psi_init()` di `sched_init()`; 3.10 tak punya `workqueue_init_early()` | urutan |
| 3 | shim `kthread_create_worker` balapan `worker->task` | semantik shim |

**Tidak satu pun disebabkan lapisan yang kurang.** Nomor 1 dan 2 lahir dari
perbedaan urutan inisialisasi 3.10 vs 4.x, yang tidak terlihat dari kode PSI dan
hanya ketahuan dengan menjalankannya. Nomor 3 lahir karena shim ditulis dari
"apa yang dibutuhkan pemanggil", bukan dari membaca implementasi aslinya sampai
tuntas — perbandingan berdampingan langsung menunjukkan bahwa 4.9 mengisi
`worker->task` SEBELUM `wake_up_process()`.

Kesimpulannya untuk pekerjaan berikutnya: **tiru semantik dengan teliti, jangan
bawa seluruh lapisan.** Modernisasi menyeluruh (jump_label baru, inti kthread
4.9, cgroup-defs.h) akan menyentuh kode arch dan driver GPU, dan tidak akan
mencegah nomor 1 maupun 2.

#### Yang membuat diagnosis mungkin

Perbaikan (1) yang membuat (2) terlihat. Sebelum itu kernel mati sebelum pstore
hidup, sehingga `console-ramoops-0` hanya berisi sesi lama — nol informasi.
Setelah PSI mulai dalam keadaan mati, kernel bertahan cukup lama untuk menulis
`dmesg-ramoops` yang berisi backtrace sebenarnya.

Untuk kerja kernel berikutnya di perangkat ini: **selalu periksa ramoops setelah
kegagalan boot**, dan kalau ramoops kosong, itu sendiri sebuah petunjuk — artinya
matinya sebelum pstore hidup, yaitu sangat awal.

---

## 3. Prioritas 2 — `mm/workingset.c` + `mm/list_lru.c`

Keduanya tidak ada di kita, ada di mereka. `list_lru` adalah prasyarat
infrastruktur; `workingset` yang memberi manfaatnya.

Gunanya: mengenali **refault** — halaman yang baru dibuang lalu diminta lagi.
Tanpa itu kernel tidak bisa membedakan page cache yang sehat dari page cache
yang berputar sia-sia, dan akan membuang halaman yang justru sedang dipakai.

Di perangkat dengan sisa RAM ~90 MB dari 1887 MB, di situlah jank lahir.
Berpasangan wajar dengan PSI: PSI **mengukur** tersendatnya, `workingset`
**mengurangi** penyebabnya. Kalau keduanya dikerjakan, kerjakan PSI dulu supaya
ada alat ukur sebelum mengubah perilaku reclaim.

---

## 2b. Tabel kunci bersama untuk DIRECT_KEY — sekarang ada angkanya

Ditambahkan 31 Agustus 2026, setelah Adiantum berjalan di perangkat.

Sebelumnya ini cuma dugaan. Sekarang terukur langsung dari `/proc/crypto` pada
sistem yang hidup:

```
name    adiantum(xchacha12,aes)
driver  adiantum(xchacha12-neon, aes-generic, nhpoly1305-neon)
refcnt  3011   (uptime 7 menit, setelah pemindaian paket)
        2148   (uptime 2 menit, baru boot)
```

Sekitar **3000 instans tfm hidup bersamaan**, satu per inode, karena `fs/crypto`
kita mengalokasikan tfm per inode (`keyinfo.c:370`, `:384`) sementara acroreiser
membaginya lewat hashtable ber-refcount (`fs/ext4/crypto_key.c:23,95,278`).

Dalam mode DIRECT_KEY seluruhnya memakai **kunci master yang sama**, jadi ~3000
salinan itu menyimpan kunci identik. Tiap instans membawa empat tfm bersarang;
yang terbesar kunci NH 1072 byte. Selain memori, tiap inode juga membayar
`setkey` Adiantum senilai 1136 byte keystream XChaCha12.

Angka ini menaikkan prioritas butir ini — tapi tidak mengubah urutan: perangkat
berjalan normal, dan PSI tetap lebih dulu karena ia yang menyediakan alat ukur.

---

## 4. Prioritas 3 — `lib/lockref.c` + `mm/vmacache.c`

Paling murah dan paling rendah risikonya dari seluruh daftar. Keduanya tidak
mengubah format apa pun dan tidak menyentuh perilaku, hanya jalur pencarian:

- `lockref` — mempercepat penelusuran path di dcache (hulu 3.12)
- `vmacache` — cache VMA per-thread (hulu 3.15)

Cocok dikerjakan lebih dulu kalau tujuannya membiasakan alur backport dari pohon
donor tanpa mempertaruhkan apa pun.

---

## 5. Yang sengaja TIDAK dikerjakan

| Kandidat | Alasan |
|---|---|
| `mm/userfaultfd.c` | acroreiser punya berkasnya tetapi defconfig mereka `# CONFIG_USERFAULTFD is not set`. Mereka membackport lalu memutuskan tidak menyalakan. Jangan kejar sesuatu yang pohon rujukan sendiri tinggalkan. |
| eBPF (`kernel/bpf/`, 20 berkas) | Celah **fungsi**, bukan performa: penghitungan kuota data per-aplikasi. `device.mk:950` sudah menyetel `ro.kernel.ebpf.supported=false` secara sadar dan `bpfloader` sudah ditangani. `PLAN-PSI-EBPF.md` §3 sudah menetapkan penghalang sebenarnya: **cgroup v2 tidak ada**, dan itu jauh lebih besar daripada eBPF-nya sendiri. |
| binder baru (`drivers/android/` + `binderfs`) | Punya kita masih di `drivers/staging/android` dan **jalan**. Risiko besar, imbalan tidak jelas. |
| `cpufreq_schedutil.c`, `qhmp_*` | msm8916 satu klaster A53; governor `interactive` bawaan CAF sudah disetel matang. `schedutil` juga menuntut perombakan cpufreq. |
| EROFS | Lihat §7. |

---

## 6. f2fs — sudah mentok, sumber murah habis

```
A37 lineage-23 (asli LineageOS)   908 commit fs/f2fs
A37 adiantum   (setelah backport) 1071
acroreiser lineage-23.2           1071
acroreiser lineage-22.2           1071
acroreiser a6010-rebased           911
```

Sejajar penuh. **Tidak ada branch acroreiser mana pun yang lebih maju.** Lanjut
berarti mengambil langsung dari mainline dan mengadaptasi sendiri.

Fitur on-disk kita berhenti di `fs/f2fs/f2fs.h:116-123`, dari `ENCRYPT` (0x0001)
sampai `QUOTA_INO` (0x0080) — setara **mainline 4.15**. Belum ada:
`INODE_CRTIME` (4.16), `VERITY` (4.19), `SB_CHKSUM` (5.0), `CASEFOLD` (5.4),
`COMPRESSION` (5.6), `RO` (5.15).

Kalau suatu saat mau satu langkah maju, `SB_CHKSUM` yang paling masuk akal:
kecil, terisolasi, menambah deteksi kerusakan superblock. `COMPRESSION` menarik
untuk `/data` 10,8 GB tetapi fitur on-disk besar dan bersinggungan dengan
enkripsi.

⚠️ **Risiko f2fs berbeda jenis dari yang lain di dokumen ini.** Bug Adiantum
langsung kelihatan — tidak bisa dekripsi, selesai. Bug f2fs muncul sebagai
korupsi diam-diam berminggu-minggu kemudian, di tempat data pengguna tinggal.
Dari 201 commit kemarin saja sudah muncul satu (shutdown menggantung). Yang
gejalanya keras ketahuan; yang tidak keras tidak.

### Temuan sampingan: mkfs sudah jauh di depan kernel

`external/f2fs-tools` mengenal `SB_CHKSUM`, `CASEFOLD`, `COMPRESSION`,
`INODE_CRTIME` — semuanya di luar jangkauan kernel kita. Dan `-g android`
menyalakan fitur tanpa syarat:

```
mkfs/f2fs_format_main.c:154-159
    ENCRYPT, QUOTA_INO, PRJQUOTA, EXTRA_ATTR, VERITY
```

`VERITY` (0x0400) tidak dikenal kernel kita. **Ini aman** — sudah diperiksa:
`fs/f2fs/super.c` `sanity_check_raw_super()` tidak memvalidasi field fitur sama
sekali, dan `F2FS_HAS_FEATURE` (`f2fs.h:125-126`) hanya menguji bit yang
dikenal, jadi bit asing diabaikan. Terbukti empiris juga: `/data` perangkat
sekarang memang sudah f2fs dan mount normal.

Pelajarannya untuk rencana ke depan: **menaikkan versi f2fs kernel tidak
otomatis menaikkan fitur.** Yang menentukan fitur adalah mkfs, dan mkfs kita
sudah lebih baru. Memakai fitur baru berarti mengubah cara format — artinya wipe
lagi.

---

## 7. EROFS — dinilai, ditolak

Sistem berkas hanya-baca terkompresi untuk partisi `system`/`vendor`. Masuk
mainline sebagai staging di v4.19, naik jadi `fs/erofs` di v5.4 (diperiksa
langsung ke kernel.org: `v5.3` → HTTP 404, `v5.4` → 200, 17 berkas).

Tiga alasan menolak, berurutan:

1. **Tidak menyentuh masalah yang kita punya.** EROFS hanya-baca; ia tidak bisa
   dipakai untuk `/data`, jadi nol hubungan dengan FBE, Adiantum, maupun f2fs.
2. **Temboknya keras.** `struct bvec_iter` baru ada sejak 3.14; di pohon kita
   `bvec_iter` = 0 kemunculan, `bi_iter` = 0, masih `bi_sector` gaya lama.
   Seluruh jalur I/O EROFS (`data.c`, `zdata.c`, `zmap.c`) harus ditulis ulang.
   Bandingkan: Adiantum cuma cipher, tidak menyentuh VFS sama sekali, dan tetap
   makan waktu berhari-hari. EROFS **adalah** VFS.
3. **Manfaatnya belum terukur.** `BOARD_SYSTEMIMAGE_PARTITION_SIZE` = 2,66 GiB.
   Sisa ruang sebenarnya **belum pernah diukur** — kalau masih longgar, seluruh
   usaha ini tidak punya alasan.

Kalau ruang `/system` benar-benar jadi masalah, urutannya: ukur sisanya dulu,
lalu bandingkan squashfs (`fs/squashfs` sudah ada di pohon kita, 17 berkas,
tinggal dinyalakan) versus membuang muatan yang tidak terpakai. Dua-duanya jauh
lebih murah.

---

## 8. Urutan kerja

```
0. Adiantum terbukti boot, /data diformat, dipakai beberapa hari   <- prasyarat
1. Ukur ulang app-kill (PLAN-PSI-EBPF.md §5) — menentukan apakah 3 perlu
2. lockref + vmacache          murah, membiasakan alur backport donor
3. PSI                         branch terpisah, sendirian, agar bisa dibandingkan
4. workingset + list_lru       setelah PSI, karena PSI jadi alat ukurnya
```

Jangan menumpuk. Kalau semuanya masuk sekaligus lalu ada yang rusak, tidak akan
ketahuan yang mana — pelajaran dari enam percobaan MTP/adb yang gagal
berurutan (`PLAN-FBE.md` Fase 7).

---

## 9. Rujukan

- `PLAN-PSI-EBPF.md` — repo `android_build_oppo_A37-22`, analisis PSI/eBPF
  lengkap termasuk penghalang cgroup v2 dan cara verifikasi
- `PLAN-LOS23.md` §6 — penyetelan kernel opsional, dan peringatan "jangan salin
  keputusan pertengahan branch"
- `acroreiser/android_kernel_lenovo_a6010` branch `lineage-23.2` — pohon donor
