# Rencana port LineageOS 23.2 ke OPPO A37

Dokumen kerja. Semua klaim di bawah ditelusuri ke berkas, baris, atau hash commit
di sumber yang sudah diunduh ke `src/`. Yang belum diverifikasi ditandai tegas —
jangan diperlakukan sebagai fakta.

Basis: kernel `rigaz29/kernel_oppo_msm8939` branch `lineage-22`, device tree
`rigaz29/rb_device_oppo_A37` branch `lineage-22`. Keduanya ROM 22.2 yang sudah
terbukti stabil di perangkat.

---

## 1. Sasaran

LineageOS 23.2 = **Android 16**.

```
src/manifest-23.2/default.xml   revision="refs/tags/android-16.0.0_r4"
project: 993   (22.2: 969)
```

Perbedaan manifest: 105 project baru, 82 dihapus. Satu yang langsung mengenai
kita:

```
DIHAPUS  LineageOS/android_hardware_ril
BARU     platform/hardware/ril          (kembali ke AOSP)
```

Port A37 22.2 memakai patch di `hardware/ril` (`LD_PRELOAD libril_shim` pada
`rild.rc`). Fork LineageOS-nya tidak ada lagi di 23.2. ULH masih memelihara
`Ultra-Legacy-Hippeastrum/android_hardware_ril` branch `lineage-23.2` — itu
kandidat pengganti, belum diperiksa isinya.

---

## 2. Temuan penentu: gerbang versi kernel

Ini yang menentukan seluruh bentuk rencana. `NetBpfLoad` di Android 16 menolak
kernel kita dua kali, dan keduanya `return`, bukan peringatan.

`src/conn-23.2/bpf/loader/NetBpfLoad.cpp:1629`

```cpp
// 25Q2 bumps the kernel requirement up to 5.4
if (isAtLeast25Q2 && !isAtLeastKernelVersion(5, 4)) {
    ALOGE("Android 25Q2 requires kernel 5.4.");
    return 6;
}
```

Ada gerbang kedua tepat di bawahnya, `NetBpfLoad.cpp:1647` — tapi yang ini
**tidak** menyala di A37, dan alasannya dijelaskan di bawah:

```cpp
if (isKernel32Bit() && isAtLeast25Q2) {
    ALOGE("Android 25Q2 requires 64 bit kernel.");
    return 9;
}
```

Kernel A37: **3.10.108**, dibangun sebagai **arm64** (`BoardConfig.mk:301`
`TARGET_KERNEL_ARCH := arm64`), dengan userspace 32-bit (`:159` `TARGET_ARCH := arm`,
`:161` `armeabi-v7a`). Konfigurasi khas msm8916.

Yang benar-benar menyala hanya **satu**: gerbang versi 5.4.

Gerbang 64-bit di `:1647` **tidak menyala**, dan alasannya halus. Deteksinya
`bpf/headers/include/bpf/KernelUtils.h:174`:

```cpp
cache = !!strstr(u.machine, "64");
```

Sekilas ini tampak menjatuhkan kita, karena `adb shell uname -m` di perangkat
menjawab `armv8l` — tidak mengandung "64". Tapi shell adalah proses 32-bit yang
berjalan di bawah personality `PER_LINUX32`. `isKernel64Bit()` justru menangani
kasus ini secara sengaja (`KernelUtils.h:141-152`):

```cpp
int p = personality(0xffffffff);
int q = personality((p & ~PER_MASK) | PER_LINUX);   // pindah ke personality asli
if (q != p) return false;
struct utsname u;
(void)uname(&u);                                     // baru baca machine sebenarnya
```

Ia berpindah ke personality asli lebih dulu, supaya proses 32-bit tetap melihat
machine string kernel yang sesungguhnya. Di kernel arm64 itu `aarch64` — mengandung
"64", sehingga `isKernel64Bit()` bernilai benar dan `:1647` terlewati.

Bandingkan juga dengan syarat 25Q4 di `:1636` yang hanya `ALOGW` — pembedaan
fatal/non-fatal itu disengaja upstream, bukan kelalaian.

**Konsekuensi:** pendekatan 22.2 — mematikan eBPF lewat
`ro.kernel.ebpf.supported=false` dan menjaga `NetdUpdatable.cpp` — tidak cukup
lagi. Gerbangnya sekarang di NetBpfLoad, sebelum kode kita menyentuh apa pun.

---

## 3. Jalan yang sudah pernah ditempuh orang

`acroreiser/android_kernel_lenovo_a6010` punya branch `lineage-22.2` sampai
`lineage-23.2`. a6010 adalah **msm8916 dengan kernel 3.10**, sekelas A37.

```
git rev-list --count origin/lineage-22.2..origin/lineage-23.2   ->  167 commit
```

Kategori (daftar penuh: `analysis/kernel-22.2-to-23.2.txt`):

| Kategori | Jumlah |
|---|---|
| eBPF / BTF / bpf maps | **98** |
| defconfig / device | 18 |
| Revert | 18 |
| syscall baru | 14 |
| mm / vmscan / oom | 14 |
| sched / iosched / block | 12 |
| HACK Treble / linker | 7 |
| SELinux | 5 |
| locking / rtmutex | 5 |

**59% dari seluruh kerja kernel adalah eBPF.** Itu ukuran pekerjaannya.

### Peringatan penting soal basis

Kernel A37 **bukan** turunan kerja acroreiser. Keduanya berpisah pada 2018:

```
merge-base: d27773cc6d3  "wlan: Use request manager to handle WE_SET_POWER requests"  (2018-04-05)

A37 punya, a6010-22.2 tidak :   263 commit
a6010-22.2 punya, A37 tidak :  7098 commit
a6010-23.2 punya, A37 tidak :  7265 commit
```

Kernel A37 adalah kernel OPPO/CAF (`msm8939`) yang dimodernisasi jalur sendiri.
Artinya **merge branch acroreiser bukan pilihan** — jalurnya cherry-pick terpilih,
dan setiap pick berpotensi konflik karena 7.098 commit basis yang berbeda.

---

## 4. Jarak kernel A37 ke syarat Android 16

Diperiksa langsung pada `origin/lineage-22` kernel A37:

| Kebutuhan | Status A37 |
|---|---|
| BTF (`include/uapi/linux/btf.h`) | **tidak ada** |
| bpf ringbuf (`kernel/bpf/ringbuf.c`) | **tidak ada** |
| bpf sk_storage (`net/core/bpf_sk_storage.c`) | **tidak ada** |
| bpf lpm_trie (`kernel/bpf/lpm_trie.c`) | **tidak ada** |
| `close_range()` | **tidak ada** |
| `epoll_pwait2()` | **tidak ada** |
| `MADV_WIPEONFORK` | **tidak ada** |
| SELinux extended permissions | ada |
| `pgscan_kswapd` untuk lmkd | ada |

Defconfig yang **sebenarnya dipakai** adalah
`arch/arm64/configs/lineageos_a37f_defconfig` (684 baris), bukan varian `arch/arm/`
(613 baris) yang bernama sama — `TARGET_KERNEL_ARCH := arm64` yang menentukan.
Berkas itu tidak punya satu pun `CONFIG_BPF*`, tapi spoofing sudah menyala:

```
CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION=y
CONFIG_ANDROID_TREBLE_BYPASS_KERNEL_VERSION_CHECKS=y
CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION_PREFIX="3.17"
CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="3.17"
```

Awalan `"3.17"` itu warisan 22.2 dan terlalu rendah untuk Android 16.

### Kabar baik: kerangka spoofing sudah ada

Kernel A37 sudah membawa mekanisme pemalsuan versi kernel:

```
A37 punya   : ANDROID_TREBLE_SPOOF_KERNEL_VERSION
              ANDROID_TREBLE_SPOOF_KERNEL_VERSION_PREFIX
              ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX
              ANDROID_TREBLE_BYPASS_KERNEL_VERSION_CHECKS

A37 kurang  : ANDROID_TREBLE_SPOOF_BPF_KERNEL_BITNESS      <- tidak diperlukan, kernel A37 arm64
              ANDROID_TREBLE_LEGACYRIL_HACK
              ANDROID_TREBLE_MOUNT_LEGACY_LINKERCONFIG
```

Cara kerjanya, `src/kernel-a6010/include/linux/utsname.h:72-111`: `utsname()`
mengembalikan salinan yang direkayasa — awalan versi palsu plus
`machine = "aarch64"` — **hanya untuk proses tertentu**:

```c
if (!strcmp(current->comm, "bpfloader") || !strcmp(current->comm, "netbpfload"))
        strcpy(fake_release_prepended, CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX);
...
#ifdef CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_BITNESS
        strcpy(utsname_spoofed.machine, "aarch64");
#endif
```

Nilai yang dipakai a6010 (commit `411b2bcb05d`, hanya mengubah defconfig):

```
CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="5.4.295"
CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_BITNESS=y
```

---

## 5. Rencana kernel — WAJIB

Urut, karena saling bergantung.

### K1. Lewati gerbang versi NetBpfLoad — satu baris

Jauh lebih murah dari dugaan semula. Mekanisme spoofing **sudah aktif** di
`arch/arm64/configs/lineageos_a37f_defconfig`; yang salah hanya nilainya:

```diff
-CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="3.17"
+CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX="5.4.295"
```

Satu baris. Tidak ada Kconfig yang perlu di-port, tidak ada kode kernel yang
disentuh.

`ANDROID_TREBLE_SPOOF_BPF_KERNEL_BITNESS` yang dipakai a6010 **tidak diperlukan**
di A37: kernel kita memang arm64, jadi `isKernel64Bit()` sudah bernilai benar
tanpa rekayasa apa pun (lihat bagian 2). a6010 membutuhkannya karena kernelnya
32-bit.

Pertimbangkan juga menaikkan `SPOOF_KERNEL_VERSION_PREFIX` (yang non-BPF, kini
`"3.17"`) — tapi itu memengaruhi `system_server`, `zygote`, `perfetto`, dan `init`
sekaligus, jadi ubah terpisah dan ukur akibatnya, jangan disatukan dengan yang BPF.

Perlu diingat: spoof hanya membuat NetBpfLoad *mau jalan*. Ia lalu akan benar-benar
memuat program BPF — dan di situlah K2 dibutuhkan.

### K2. Backport tumpukan eBPF (98 commit)

Urutan wajib, karena berlapis:

1. **Prasyarat** — `bpf: Rename bpf_verifer_log`, `encapsulate verifier log state`,
   `map_alloc_check callback`, `kv[mz]alloc helpers`, `hlist_is_singular_node`
2. **BTF** — `Introduce BPF Type Format (BTF)` lalu ±30 commit perbaikan BTF
   berturut. NetBpfLoad memakai BTF di `:641` dan `:1311`
3. **Map types** — `LPM_TRIE` (dipakai NetBpfLoad `:790`), `SK_STORAGE`,
   `DEVMAP_HASH` (`:808`, diemulasi lewat HACK)
4. **Ring buffer** — `Implement BPF ring buffer and verifier support`
5. **Socket** — `PTR_TO_SOCKET verifier type`, `bpf_sock`, `bpf_tcp_sock`,
   `getsockopt/setsockopt hooks`
6. **HACK NetBpfLoad** — `NetBpfLoad wants bpf progs to be always jited`,
   `fixup returned LPM_TRIE map flags`, `emulate BPF_MAP_TYPE_DEVMAP_HASH`
7. **Perbaikan keamanan** susulan — truncation mod32/div, ringbuf power-of-2,
   dead code sanitizing, dsb.

### K2a. Prasyarat yang tidak terlihat: cgroup v2

**Angka 98 commit di atas menyesatkan kalau berdiri sendiri.** Pertanyaan
Fase 0 sudah dijawab, dan jawabannya memperbesar cakupan secara drastis.

Di 22.2 kita menyimpulkan eBPF mustahil karena kernel 3.10 tidak punya cgroup v2,
sehingga `BPF_PROG_TYPE_CGROUP_SKB` tidak bisa di-attach. Kesimpulan itu benar
**untuk kernel kita**. acroreiser menyelesaikannya bukan dengan menghindar,
melainkan dengan mem-backport seluruh subsistem cgroup modern:

```
CGROUP2_SUPER_MAGIC   include/uapi/linux/magic.h, kernel/cgroup/cgroup.c
cgroup2_fs_type       kernel/cgroup/cgroup.c
cgroup_bpf            include/linux/bpf-cgroup.h, include/linux/cgroup-defs.h
```

Perhatikan jalurnya: **`kernel/cgroup/cgroup.c`**. Bentuk direktori itu tata letak
kernel 4.4+; 3.10 hanya punya `kernel/cgroup.c` tunggal — dan itulah yang masih
ada di kernel A37. Commit yang memindahkannya, `f9cee26f9a4 cgroup: move cgroup
files under kernel/cgroup/`, sudah ada di `lineage-22.2` a6010, jadi **tidak ikut
terhitung** dalam 167 commit.

Ukuran sebenarnya, dihitung dari titik pisah 2018 sampai `lineage-22.2` a6010:

```
commit menyentuh cgroup :  985
commit menyentuh bpf    :  374
+ 98 commit bpf di 22.2 -> 23.2
```

Jadi prasyarat eBPF untuk A37 berskala **~1.300 commit**, bukan 98. Defconfig
a6010 mengonfirmasi tujuan akhirnya:

```
CONFIG_CGROUP_BPF=y   CONFIG_BPF=y   CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y      CONFIG_BPF_EVENTS=y
```

### K2b. Kenapa tidak bisa sekadar dibiarkan gagal

Di 22.2 kita mematikan eBPF dan menambal `NetdUpdatable.cpp`. Di 23.2 itu lebih
berbahaya, karena `src/conn-23.2/bpf/loader/netbpfload.rc:15`:

```
service bpfloader /system/bin/false
    reboot_on_failure reboot,netbpfload-missing
```

Kegagalan `netbpfload` memicu **reboot**, bukan sekadar servis mati — artinya
bootloop. Konsumennya juga masih memeriksa hasilnya (`bpf/netd/BpfHandler.cpp:234`
menuntut `bpf.progs_loaded == "1"`).

Konsekuensinya, spoofing K1 saja **tidak cukup dan bahkan berbahaya**: ia membuat
NetBpfLoad lolos gerbang versi, lalu benar-benar mencoba memuat program BPF, gagal,
dan mereboot. K1 hanya aman kalau diikuti K2 — atau kalau Connectivity ditambal
seperti di 22.2 sekaligus `reboot_on_failure` dilucuti.

Ini percabangan besar yang harus diputuskan sadar, bukan ditemukan di tengah jalan:

| Jalur | Biaya | Status |
|---|---|---|
| **A. Backport penuh** cgroup v2 + eBPF | ~1.300 commit | terbukti jalan di a6010 |
| **B. Tambal Connectivity** + lucuti `reboot_on_failure`, tanpa spoof BPF | kecil, mirip 22.2 | **belum pernah diuji di 23.2** |

Jalur B lebih murah dan sejalan dengan pengalaman 22.2, tapi belum ada preseden.
Jalur A mahal tapi sudah ada yang membuktikan. Rekomendasi: **coba B lebih dulu**
di Fase 4 — kalau gagal, kerugiannya hanya beberapa hari, sedangkan memulai dari A
mengunci berminggu-minggu sebelum tahu ROM-nya bisa hidup.

### K3. Syscall yang hilang

```
close_range()      + CLOSE_RANGE_UNSHARE + CLOSE_RANGE_CLOEXEC   (5 commit)
epoll_pwait2()                                                    (2 commit)
MADV_WIPEONFORK                                                   (1 commit)
ARM: wire up ...  + ARM: fix syscall table derps
```

Kecil, mandiri, konflik rendah. Bisa dikerjakan paralel dengan K2.

### K4. SELinux

```
selinux: ignore unknown extended permissions
Revert "selinux: Android kernel compatibility with M userspace"
+ 3 perbaikan Makefile/dependensi flask.h
```

Kernel A37 sudah punya extended permissions, tapi *ignore unknown* adalah hal
berbeda — policy Android 16 membawa xperm yang kernel 3.10 belum kenal.

### K5. Locking

```
BACKPORT: locking: Introduce __cleanup() based infrastructure
mm: fix build breakage after __cleanup()
+ 3 perbaikan rtmutex/futex
```

Diperlukan sebagai prasyarat build oleh sebagian backport lain.

---

## 6. Rencana kernel — OPSIONAL

Tidak menghalangi boot. Kerjakan hanya setelah ROM hidup.

| Kelompok | Isi | Nilai |
|---|---|---|
| mm / lmkd | `stat_interval_jiffies`, `pgscan_*`, `do not swap anon just because free+file is low` | responsivitas di RAM 1 GB |
| sched | `pelt halflife 16ms` | responsivitas |
| I/O | ROW iosched, `REQ_URGENT`, `mmc: stop READ to serve URGENT` | latensi UI |
| Revert (18) | overclock 1.6 GHz, SCHED_FIFO, oom_reaper, `process_mrelease` | stabilitas |

Perhatikan: a6010 sempat pindah ke ROW iosched lalu **kembali ke CFQ**
(`2359fea40cb a6010: switch back to cfq`). Jangan salin keputusan pertengahan;
ikuti keadaan akhir branch.

Perhatikan juga rentetan `Revert` terhadap `oom_reaper` dan `process_mrelease` —
acroreiser membuangnya di 23.2. Kalau kernel A37 punya, pertimbangkan hal serupa.

---

## 7. Rencana userspace

Fork ULH `lineage-23.2` adalah daftar "apa yang perlu ditambal", karena fork itu
ada justru untuk itu. Diukur terhadap LineageOS 23.2:

### frameworks/native — 9 commit, yang terbesar

```
c7f2fee21b  Forward-port GLES Render Engine to 16 QPR2
cd1402b97d  Revert "Remove useFramebufferCache parameter in drawLayers()"
e2e91300f3  Revert "Delete genTextures and deleteTextures from RenderEngine"
93877b8601  renderengine: gles: unconditionally skip PostRenderCleanup
fcc10e3593  renderengine: gles: Fix QPR2 build errors
d4f1d339ca  renderengine: compilation fixes for 16 QPR1
e4247554be  SF: Bring back support for disabling backpressure propagation
b3ddc63b7b  libbinder: make threadpool shrinking non-fatal
9fe1c2a825  surfaceflinger: remove display_intf_headers dependency
```

Terverifikasi: `libs/renderengine/` di LineageOS 23.2 hulu **tidak lagi punya
`gl/`**, juga tidak punya `Description.cpp`, `Mesh.cpp`, `Texture.cpp`. ULH
mengembalikan semuanya.

#### Terjawab: forward-port ini WAJIB untuk A37

Jalur non-Vulkan resmi masih ada di hulu — `RenderEngine.cpp:53` memanggil
`SkiaGLRenderEngine::create(args)` untuk `GraphicsApi::GL`, dan enum-nya cuma
`{GL, Vk}`. Jadi secara mekanisme, device tanpa Vulkan tetap terlayani.

Masalahnya bukan mekanisme, melainkan perangkat kerasnya. Fork ULH **mengganti**,
bukan menambah pilihan — di titik cabang yang sama:

```cpp
hulu  :53   return android::renderengine::skia::SkiaGLRenderEngine::create(args);
ULH   :54   return android::renderengine::gl::GLESRenderEngine::create(args);
```

Tidak ada properti untuk memilih di antara keduanya.

Dan SkiaGL **sudah pernah dicoba di A37, dan gagal**. Tercatat di
`rb_device_oppo_A37` `device.mk:110-114` saat porting 22.2:

```
Adreno 306 dengan driver CAF lama tidak sanggup, dan SF mati dengan:
  F DEBUG: Abort message: 'Unable to generate SkImage. isTextureValid:1 dataspace:513'
empat belas kali berturut-turut di logcat -b crash.
```

Karena itu 22.2 menyetel `debug.renderengine.backend=gles` (`device.mk:129`)
bersama `persist.graphics.vulkan.disable=true` (`:138`), pada GPU yang
mendeklarasikan `ro.opengles.version=196608` — GLES 3.0, tanpa Vulkan.

Di 23.2 properti itu menjadi **tidak bermakna**: `gles` tidak lagi memetakan ke
apa pun karena `gl/` sudah dibuang, dan device akan diam-diam mendapat SkiaGL —
tepat backend yang terbukti menjatuhkan SurfaceFlinger di perangkat ini.

Satu keberatan yang jujur perlu dicatat: crash itu teramati pada Skia era
Android 12, dan Skia di Android 16 sudah banyak berubah. Bisa saja sekarang
berhasil. Tapi drivernya tidak berubah — blob CAF yang sama — jadi beban
pembuktian ada di pihak "sudah membaik".

**Sikap yang diambil:** uji sekali dengan SkiaGL hulu di Fase 5 (murah: bangun,
boot, lihat `logcat -b crash`). Kalau abort `SkImage` muncul lagi, langsung pakai
fork ULH. Anggarkan waktu dengan asumsi fork itu diperlukan.

### system/core — 3 commit

```
61b57678c  Fix support for devices without cgroupv2 support
90ef11465  Revert "libprocessgroup: CgroupSetup should fail if a required controller fails to mount"
f5f2bd6d9  Camera: Add feature extensions
```

Dua yang pertama langsung mengenai kita: kernel 3.10 tidak punya cgroup v2.

### bionic — 1 commit

```
7001b90a1  linker: partially allow text relocations
```

Untuk blob lama. Port 22.2 kita sudah punya patch bionic sendiri
(`rename()` → `renameat`); periksa apakah masih perlu di 23.2.

### system/sepolicy — 1 commit

```
83b174ea9  sepolicy: allow su domain in user builds
```

Tidak relevan; A37 dibangun `userdebug`.

### hardware/ril

LineageOS membuang fork-nya. ULH punya `lineage-23.2`. **Belum diperiksa.**

---

## 8. Device tree

`acroreiser/android_device_lenovo_a6010`: 61 commit dari `lineage-22.2` ke
`lineage-23.2`. Yang menonjol dan kemungkinan wajib:

```
535ad98  msm8916: switch to Radio Config 1.1
b51f279  msm8916: implement dummy RadioConfig 1.1
66b42ad  msm8916: sepolicy: label Radio Config 1.1
31bd4cb  msm8916: mount and configure cpusets
65c11d8  msm8916: remove Lineage Health HAL
510af2b  msm8916: drop apns-conf.xml copying from device tree
```

Sisanya penyetelan 1 GB RAM yang layak ditiru: `Disable triple buffer for 1G
memory optimization`, `reduce readahead for ext4`, `watermark_scale_factor`,
`SystemUIGo`, `allow background tasks on cpu 0-2`.

Ada juga `67159f8 hal3on1: draft fixes for stability` — port A37 memakai hal3on1,
jadi perbaikan ini relevan langsung.

Sepolicy legacy: `Ultra-Legacy-Hippeastrum/android_device_qcom_sepolicy` branch
**`lineage-23.2-legacy`** — penerus `device/qcom/sepolicy-legacy` yang dipakai
22.2.

---

## 9. Urutan kerja

Setiap fase punya syarat lulus. Jangan lanjut sebelum terpenuhi.

| Fase | Isi | Lulus bila |
|---|---|---|
| **0** | ~~Pertanyaan terbuka~~ — keduanya sudah terjawab: cgroup v2 (K2a) dan RenderEngine (bagian 7) | selesai |
| **1** | Siapkan manifest 23.2 + local manifest A37, sinkronkan pohon | `repo sync` selesai |
| **2** | K3 (syscall) + K5 (locking). **Jangan aktifkan K1 dulu** | kernel terbangun, boot ke bootanimation |
| **3** | Userspace: system/core cgroup, bionic, sepolicy legacy | boot sampai homescreen |
| **4** | Jalur B: tambal Connectivity + lucuti `reboot_on_failure` | tidak bootloop, jaringan hidup tanpa BPF |
| **4′** | Bila B gagal: K1 (satu baris defconfig) + K2 (cgroup v2 + eBPF, ~1.300 commit) | `netbpfload` tidak `return 6` |
| **5** | Uji SkiaGL hulu sekali; siapkan fork ULH RenderEngine sebagai rencana utama | tidak ada abort `SkImage` di `logcat -b crash` |
| **6** | Device tree: RadioConfig 1.1, cpusets, hal3on1 | telepon/kamera berfungsi |
| **7** | Opsional: mm, sched, I/O, revert | ukur sebelum/sesudah |

Fase 2 sengaja mendahulukan yang murah. K1 (spoof) **sengaja tidak dipasang di
Fase 2**, karena tanpa K2 ia justru mengubah kegagalan yang jinak menjadi bootloop
— lihat K2b.

Fase 4 adalah titik keputusan sesungguhnya. Jalur B dicoba lebih dulu karena
kegagalannya murah dan cepat ketahuan; jalur A (Fase 4′) hanya ditempuh kalau B
terbukti buntu.

---

## 10. Risiko utama

**eBPF adalah risiko terbesar, dan biayanya sepuluh kali dugaan awal.** Bukan 98
commit melainkan ~1.300, karena cgroup v2 harus ikut di-backport lebih dulu (K2a).
Semuanya di atas basis yang sudah berbeda 7.098 commit sejak 2018, sehingga tiap
pick berpotensi konflik. Kalau jalur A terpaksa ditempuh, perlakukan sebagai
proyek tersendiri, bukan satu fase.

**Spoofing tanpa eBPF berbahaya.** K1 membuat NetBpfLoad lolos gerbang lalu gagal
saat benar-benar memuat program, dan `reboot_on_failure` mengubahnya jadi bootloop.
Urutan salah di sini menghasilkan kegagalan yang jauh lebih sulit didiagnosis
daripada sekadar jaringan mati.

**32-bit userspace.** `NetBpfLoad.cpp:1718` menyebut `isUserspace32bit()` dengan
kernel ≥6.2; tidak mengenai kita sekarang, tapi menandakan arah upstream terus
mempersempit dukungan 32-bit.

**hardware/ril berpindah tangan.** Patch RIL 22.2 kita tidak bisa dipakai apa
adanya.

---

## 11. Inventaris sumber

Sudah diunduh ke `src/`:

```
manifest-22.2, manifest-23.2      manifest LineageOS
kernel-a6010                      acroreiser, 22.2..23.2 tersedia   (1,3 GB)
kernel-a37                        basis kita, branch lineage-22     (1,3 GB)
dt-a6010                          device tree referensi
conn-23.2                         Connectivity 23.2 (NetBpfLoad)
ulh/                              bionic, system_core, system_sepolicy,
                                  hardware_ril, frameworks_native   (381 MB)
```

Belum diunduh: `android_device_qcom_sepolicy` (`lineage-23.2-legacy`),
`android_hardware_qcom-caf_common`, `MisterZtr/LineageOS_gsi`, device tree A37
sendiri.
