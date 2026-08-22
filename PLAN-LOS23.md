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

## 5. Rencana kernel

Setelah K2b terjawab, isi bagian ini menyusut drastis. Yang **wajib** hanya K3,
K4, dan K5 — semuanya kecil dan mandiri. K1, K2, dan K2a dipertahankan sebagai
catatan jalur alternatif, bukan pekerjaan yang direncanakan.

### K1 (OPSIONAL). Lewati gerbang versi NetBpfLoad — satu baris

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

### K2 (OPSIONAL). Backport tumpukan eBPF (98 commit)

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

### K2a (OPSIONAL). Prasyarat yang tidak terlihat: cgroup v2

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

### K2b. TERJAWAB: eBPF tidak wajib

Pertanyaan ini sempat saya gantung sebagai percabangan berisiko. Ternyata sudah
ada jawabannya, dan jawabannya **tidak wajib** — dengan preseden yang jauh lebih
ekstrem dari A37.

`zhafknight/los_patches/los-23.2_n7000/` adalah set patch LineageOS 23.2 untuk
**Samsung Galaxy Note GT-N7000 / Exynos 4210** — perangkat 2011 dengan kernel 3.0,
jauh lebih tua dari A37. README-nya menyebut kemampuan yang disediakan, dua di
antaranya persis kebutuhan kita:

```
- legacy-kernel, cgroup v1, and process-group compatibility
- BPF-less networking, netd, and DNS resolver compatibility
```

**cgroup v1**, bukan v2. **BPF-less**, bukan eBPF.

Kuncinya patch `NetBpfLoad-Relax-all-kernel-version-and-capability-checks`
(ada di dua tempat: `zk-patches/.../043-gsi-staging-0001-...` dan
`MisterZtr/LineageOS_gsi` `patches/trebledroid-staging/`). Ia mengubah setiap
gerbang fatal menjadi peringatan:

```diff
     if (isAtLeast25Q2 && !isAtLeastKernelVersion(5, 4)) {
-        ALOGE("Android 25Q2 requires kernel 5.4.");
-        failed = true;
+        ALOGW("[GSI] Android 25Q2 requires kernel 5.4.");
     }
```

Rantai BPF-less selengkapnya, semuanya sudah tersedia sebagai patch jadi:

| Repo | Patch |
|---|---|
| Connectivity | `NetBpfLoad-Relax-all-kernel-version-and-capability-checks` |
| Connectivity | `BpfHandler-and-BpfNetMaps-convert-fatal-errors-to-non-fatal` |
| Connectivity | `Support-non-working-BPF-maps-on-old-BPF-less-kernel` |
| Connectivity | `treat-non-optional-BPF-program-load-failures-as-non-fatal` |
| Connectivity | `net-Gracefully-fallback-when-eBPF-firewall-maps-are-unavailable` |
| Connectivity | `netd-Remove-4.14-kernel-restrictions` |
| DnsResolver | `Dont-abort-if-the-DnsHelper-failed-to-init-on-BPF-less` |
| frameworks/native | `Disable-gpuservice-on-old-BPF-less-kernel` |
| system/vold | `vold-use-sdcardfs-as-fallback-when-FUSE-BPF-is-unavailable` |

Karena gerbangnya dilucuti di userspace, **K1 pun tidak diperlukan**: tidak ada
lagi yang perlu ditipu soal versi kernel. Spoofing tetap boleh dipakai, tapi
sebagai pilihan, bukan keharusan.

Perbandingan biayanya tidak berimbang:

| Jalur | Biaya | Status |
|---|---|---|
| **B. Userspace BPF-less** | **89 patch**, sudah jadi | dipakai di perangkat kernel 3.0 |
| A. Backport cgroup v2 + eBPF | ~1.300 commit kernel | dipakai a6010 |

**Keputusan: tempuh jalur B.** Jalur A turun status menjadi opsional — hanya
relevan kalau nanti ada fitur yang benar-benar menuntut eBPF berfungsi (mis.
statistik data per-aplikasi atau firewall berbasis BPF), dan itu pun sebagai
proyek tersendiri.

Konsekuensi lain: rentetan `reboot_on_failure` yang saya khawatirkan tidak lagi
jadi jebakan, karena kegagalan BPF sudah diubah menjadi non-fatal di hulu rantai.

### K3 (WAJIB). Syscall yang hilang

```
close_range()      + CLOSE_RANGE_UNSHARE + CLOSE_RANGE_CLOEXEC   (5 commit)
epoll_pwait2()                                                    (2 commit)
MADV_WIPEONFORK                                                   (1 commit)
ARM: wire up ...  + ARM: fix syscall table derps
```

Kecil, mandiri, konflik rendah. Bisa dikerjakan paralel dengan K2.

### K4 (WAJIB). SELinux

```
selinux: ignore unknown extended permissions
Revert "selinux: Android kernel compatibility with M userspace"
+ 3 perbaikan Makefile/dependensi flask.h
```

Kernel A37 sudah mendukung xperms sepenuhnya — `AVTAB_XPERMS_ALLOWED` di
`security/selinux/ss/avtab.c:371`, dan `POLICYDB_VERSION_MAX` bernilai
`POLICYDB_VERSION_XPERMS_IOCTL`. Yang dibutuhkan hanya *ignore unknown*, karena
policy Android 16 membawa xperm yang kernel 3.10 belum kenal.

Justru karena itu patch `init-cap-SELinux-policy-version-on-pre-4.9-kernels` dari
set GSI **tidak boleh dipakai** — lihat bagian 7b.

### K5 (WAJIB). Locking

```
BACKPORT: locking: Introduce __cleanup() based infrastructure
mm: fix build breakage after __cleanup()
+ 3 perbaikan rtmutex/futex
```

Diperlukan sebagai prasyarat build oleh sebagian backport lain.

---

## 6. Penyetelan kernel — opsional, setelah ROM hidup

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

## 7b. Sumber patch: dua yang saling melengkapi

Set patch n7000 menyebut tiga sumber lain. Ketiganya diperiksa:

| Sumber | Branch | Nilai |
|---|---|---|
| `Ultra-Legacy-Hippeastrum/legacy_support_patches` | **`lineage-23.2`** | **wajib** — 38 patch, termasuk 2 khusus QCOM |
| `J0SH1X/n7000_android_16_patches` | `lineage-23.0` | rujukan saja; berisi dump `uncommitted.diff` per repo, bukan patch terstruktur, dan bukan 23.2 |
| `rINanDO/galaxys2-patches` | `lineage-21.0` | terlalu tua; README n7000 sendiri menyebutnya "as reference" |
| `Mi-Thorium` (organisasi) | `a16_qpr2`, `a17` | **rujukan penting** — migrasi HIDL→AIDL, lihat di bawah |

### Mi-Thorium: rujukan penting untuk migrasi HIDL ke AIDL

**Koreksi.** Versi awal dokumen ini menolak organisasi ini sebagai tidak relevan.
Penilaian itu salah, dan salahnya dua lapis: pertama menilai relevansi hanya dari
versi kernel, lalu hanya membaca `default_branch` tiap repo alih-alih seluruh
daftar branch. Mereka justru sudah menggarap versi Android yang kita tuju.

```
a16/master   a16_qpr1/master   a16_qpr2/master   a17/master
```

`a16_qpr2` adalah Android 16 QPR2 — persis target LineageOS 23.2.

Platform mereka msm8937/8917/8940/SDM439 dengan kernel 4.9/4.19. Berbeda dari
A37, tapi sama-sama perangkat lawas, dan **mereka sudah melewati penghapusan HIDL
yang sekarang menghadang kita**.

#### 1. HIDL tidak dihapus seluruhnya di Android 16

Ini yang paling meluruskan. Di `a16_qpr2/master` mereka masih memakai **58 HAL
HIDL**, termasuk yang mendasar:

```
android.hardware.graphics.composer@2.1-service
android.hardware.graphics.allocator@2.0-impl
android.hardware.graphics.mapper@2.0-impl-2.1
android.hardware.keymaster@3.0-impl
android.hardware.gatekeeper@1.0-impl
android.hardware.audio@7.0-impl
```

Jadi keempat kegagalan build kita bukan gejala "HIDL mati". Yang dihapus hanya
HAL tertentu — vibrator, livedisplay, touch. Sisanya aman, dan tidak perlu
dimigrasi karena panik.

#### 2. Migrasi livedisplay: sudah mereka kerjakan

```
a11/master   vendor.lineage.livedisplay@2.0-service-sdm      <- HIDL
a16_qpr2     vendor.lineage.livedisplay-service.sdm          <- AIDL
             $(call soong_config_set_bool,livedisplay_sdm,enable_dm,false)
```

Dan yang menentukan: **nol perubahan manifest/VINTF di device tree mereka**.
Tidak ada satu pun rujukan `livedisplay` di `manifest.xml` mereka.

Sebabnya terbukti di pohon kita,
`hardware/lineage/interfaces/livedisplay/aidl/sysfs/Android.bp:30-46`:

```
init_rc: ["vendor.lineage.livedisplay-service.sysfs.rc"],
vintf_fragments: select(soong_config_variable("livedisplay_sysfs", "enable_dcc"), {...})
```

Servis AIDL membawa init rc dan VINTF fragment-nya sendiri, dipilih per fitur
lewat knob soong config. Itu kebalikan dari paket HIDL `-sysfs`, yang justru
dikeluhkan `manifest.xml:356-380` A37 karena TIDAK membawa fragment sehingga tiap
interface harus dideklarasikan manual.

**Konsekuensinya alasan penundaan di 8c gugur.** Saya menunda migrasi ini karena
takut salah deklarasi VINTF membuat servis `[restarting]` permanen. Untuk AIDL
justru deklarasi manualnya yang harus dibuang.

Untuk A37 langkahnya jadi presisi, karena manifest A37 hanya mendeklarasikan satu
interface livedisplay, `IDisplayColorCalibration`:

```
1. device.mk : vendor.lineage.livedisplay@2.0-service-sysfs
               -> vendor.lineage.livedisplay-service.sysfs
2. device.mk : $(call soong_config_set_bool,livedisplay_sysfs,enable_dcc,true)
3. manifest.xml : buang blok deklarasi VINTF livedisplay manual
```

Fragment yang akan terpakai sudah ada:
`vendor.lineage.livedisplay-service.sysfs-dcc.xml`.

#### 3. Vibrator: pakai HAL vendor, bukan implementasi AOSP

```
mithorium.mk:596   vendor.qti.hardware.vibrator.service
```

Mereka tidak pernah bergantung pada `android.hardware.vibrator@1.0-impl` milik
AOSP, sehingga penghapusannya tidak menyentuh mereka sama sekali. Untuk A37 perlu
diperiksa apakah `vendor/oppo/A37` punya blob setara — msm8916 lazimnya hanya
`timed_output` sederhana, jadi belum tentu ada.

#### 4. Shim RIL AIDL

```
android.hardware.radio-service.compat
```

Relevan langsung: LineageOS membuang fork `hardware/ril` di 23.2 (bagian 1), dan
ini jalur kompatibilitas AIDL untuk RIL lawas yang layak diperiksa saat Fase 6.

#### 5. Pola `.vendor` untuk blob lawas

```
android.hardware.bluetooth@1.0.vendor    android.hardware.drm@1.4.vendor
android.hardware.radio@1.4.vendor        android.hardware.gnss@2.1.vendor
android.hardware.keymaster@3.0.vendor    android.hardware.power@1.2.vendor
```

Varian `.vendor` dari HAL HIDL, dipasang berdampingan supaya blob lawas tetap
menemukan pustaka yang dicarinya.

#### 6. Arsitektur manifest yang berbeda dari kita

`local_manifests/lineage-23.2.xml` mereka punya **nol `remove-project`**. Mereka
tidak mengganti satu pun repo inti LineageOS. Sebagai gantinya seluruh penanganan
legacy diisolasi di namespace sendiri, `hardware/mithorium/*`, dengan berkas
penjaga lewat `linkfile`:

```
<linkfile src="guard-generic.bp"  dest="hardware/mithorium/audio/<CAF-tag>/Android.bp" />
<linkfile src="guard-qcom-qssi-display.mk" dest="hardware/mithorium/display/<CAF-tag>/Android.mk" />
```

Pohon HAL CAF di-pin per tag rilis (`LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0`),
bukan per branch LineageOS.

Pendekatan ini lebih bersih, tapi **belum tentu bisa kita tiru**: mereka tidak
perlu menambal `bionic`, `system/core`, atau `frameworks/native` karena msm8937
masih didukung hulu. A37 pre-UM memerlukan fork ULH, dan itu memaksa
`remove-project`.

#### 7. Android 16 tidak menuntut perubahan kernel — bukti kedua

Repo kernel mereka **tidak punya branch a16 maupun a17**; yang tertinggi
`mithorium/a15/master`. Artinya device tree Android 16 dan 17 mereka berjalan di
atas kernel a15 tanpa perubahan.

Ini menguatkan temuan Fase 2 dari arah lain: kernel A37 terbangun untuk Android 16
tanpa satu pun backport. Dua proyek berbeda, dua kernel berbeda, kesimpulan sama.

### Temuan yang menghalangi build: msm8916 dihapus dari lapisan QCOM

LineageOS 23.2 **tidak lagi mengenal msm8916 sama sekali**. Diperiksa langsung di
`src/qcom-common-23.2`:

```
$ grep -c msm8916 qcom_boards.mk qcom_defs.mk BoardConfigQcom.mk
qcom_boards.mk:0
qcom_defs.mk:0
BoardConfigQcom.mk:0
```

Platform tertua yang tersisa adalah `msm8937`. Yang hilang, dikembalikan oleh
`legacy_support_patches/hardware/qcom-caf/common/`:

```
QCOM_BOARD_PLATFORMS += msm8916
BR_FAMILY := msm8909 msm8916
QCOM_HARDWARE_VARIANT := msm8916
MSM_VIDC_TARGET_LIST := $(BR_FAMILY)
```

Dua patch: `0001-Revert-QCOM-RIP-pre-UM-families.patch` dan
`0002-QCOM-Bring-back-legacy-platform-definitions.patch`.

Tanpa ini `QCOM_HARDWARE_VARIANT` tidak pernah terisi dan pemilihan HAL QCOM
patah. Ini bukan penyetelan, melainkan syarat agar pohon bisa dibangun untuk A37.

### MisterZtr/LineageOS_gsi ditelusuri utuh

Repo ini sumber hulu bagi set n7000, jadi layak diperiksa sendiri — terutama apa
yang **tidak** diambil zhafknight, karena mereka menyaring untuk Exynos.

```
patches/trebledroid           191
patches/trebledroid-staging    95
patches/personal               28
TOTAL                         314   (n7000 mengambil 54, menyisakan 258)
```

Sebagian besar sisanya memang tidak relevan — 24 patch `device_phh_treble`,
9 `treble_app`, plus rentetan Mediatek dan Samsung. Tapi tiga hal layak diambil,
dan **dua justru harus ditolak**.

#### Layak diambil

| Patch | Alasan |
|---|---|
| `SurfaceFlinger-Restore-mPropagateBackpressure-for-HW` | sejalan dengan patch ULH `SF: Bring back support for disabling backpressure propagation` |
| `add-SurfaceFlinger-latch-unsignaled-and-backpressure` | penyetelan SF untuk GPU lemah |
| `add-prefer-hardware-codecs-toggle` | langsung menyambung kerja Codec 2.0 di 22.2 |
| `MediaProfiles-fall-back-to-defaults-when-XML-file-ca` | ketahanan bila XML profil media tidak lengkap |

#### Harus DITOLAK, dan ini yang paling penting dari pemeriksaan ini

**`Revert-Remove-framework-support-for-audio-HIDL-HAL-V5`** — tidak diperlukan.
A37 memakai HIDL audio **6.0** (`manifest.xml:38-40`), dan 6.0 masih terdaftar di
`src/av-23.2/media/libaudiohal/FactoryHal.cpp:53-58`:

```cpp
static const std::array<AudioHalVersionInfo, 4> sAudioHALVersions = {
    AudioHalVersionInfo(Type::AIDL, 1, 0),
    AudioHalVersionInfo(Type::HIDL, 7, 1),
    AudioHalVersionInfo(Type::HIDL, 7, 0),
    AudioHalVersionInfo(Type::HIDL, 6, 0),   // <- A37
};
```

**`init-cap-SELinux-policy-version-on-pre-4.9-kernels`** — berbahaya untuk A37.
Patch ini membatasi policydb ke versi 29 pada kernel di bawah 4.9, karena banyak
kernel lawas tidak punya backport ioctl xperms. Kernel A37 **punya**:

```
security/selinux/ss/avtab.c:371     AVTAB_XPERMS_ALLOWED
security/selinux/include/security.h POLICYDB_VERSION_MAX = POLICYDB_VERSION_XPERMS_IOCTL
```

Lebih buruk lagi, patch itu memutuskan lewat `uname()`, sedangkan A37 menyalakan
`ANDROID_TREBLE_SPOOF_KERNEL_VERSION` untuk `init` — jadi ia akan membaca awalan
palsu `"3.17"`, tetap menyimpulkan di bawah 4.9, dan membatasi policy tanpa alasan.

#### Pelajaran untuk penerapan nanti

Kedua penolakan di atas datang dari memeriksa kemampuan perangkat, bukan dari
mencocokkan nama patch. Satu umpan palsu bahkan hampir lolos:
`disable-OPPO-touch-firmware-update-to-prevent-kernel-panic` terdengar seperti
milik kita — ternyata untuk **OPPO F11 (CPH1911, MediaTek MT6771)**, bukan msm8916.

Aturan penerapan: setiap patch disaring terhadap kemampuan A37 yang sudah
diverifikasi, bukan terhadap kemiripan nama perangkat atau vendor.

### Konsekuensi: dua set patch dipakai bersama, bukan salah satu

Keduanya menutupi celah yang berbeda, dan tidak saling menggantikan:

| Set | Jumlah | Menutupi | Kelemahan untuk A37 |
|---|---|---|---|
| n7000 (zhafknight, dari GSI/MisterZtr) | 89 | BPF-less, cgroup v1, kernel legacy | Exynos 4210 — **nol** patch QCOM |
| ULH `legacy_support_patches` | 38 | QCOM pre-UM, HIDL, hwbinder, IPsec | tidak memuat rantai BPF-less selengkapnya (hanya 1 patch Connectivity) |

Rencana: ambil rantai BPF-less dan kompatibilitas kernel legacy dari set n7000,
ambil lapisan QCOM dan HIDL dari ULH, saring yang khas Exynos (Broadcom Wi-Fi,
RIL v6/v8/v9, `mkbootimg --dt`).

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

## 8b. Hasil Fase 1

Dikerjakan dan tuntas. Tiga hal berbeda dari yang direncanakan.

### Pohon tersinkron bersih

```
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
repo sync -c -j8 --no-clone-bundle --no-tags --force-sync

1172 / 1172 project     nol error     173 GB
```

Release config 23.2 adalah **`bp4a`**, bukan `bp1a` seperti 22.2.

### Dua patch QCOM ternyata tidak perlu diterapkan

Rencana menyebut "terapkan 2 patch QCOM pre-UM". Setelah sync, keduanya sudah ada
— ULH menggabungkannya langsung ke fork `hardware/qcom-caf/common`, dan keduanya
menjadi dua commit teratas:

```
7b11870 QCOM: Bring back legacy platform definitions
624fa24 Revert "QCOM: RIP pre-UM families"
```

Jadi memilih fork ULH di manifest sudah menyelesaikannya. Patch di
`legacy_support_patches` ditujukan bagi yang memakai `qcom-caf/common` hulu.

### Syarat lulus yang saya tetapkan sendiri ternyata keliru

Rencana menuntut `QCOM_HARDWARE_VARIANT` terisi `msm8916`. Diukur setelah sync,
nilainya **kosong** — dan itu benar, bukan kegagalan.

`QCOM_HARDWARE_VARIANT` hanya diset oleh `BoardConfigQcom.mk`, dan A37 **tidak
pernah meng-include berkas itu**. Device tree menjelaskan alasannya sendiri di
`BoardConfig.mk:23-31`: msm8916 sudah dicabut dari daftar platform hulu sejak
lineage-20, sehingga gerbang di `hardware/qcom-caf/msm8916/media/Android.mk:5`

```make
ifeq ($(call is-board-platform-in-list, $(QCOM_BOARD_PLATFORMS)),true)
```

bernilai false dan modul media tidak pernah ikut. A37 mengatasinya dengan
mendeklarasikan platform sendiri di `BoardConfig.mk:44`, bukan lewat lapisan
`BoardConfigQcom.mk`.

Syarat yang benar karena itu `QCOM_BOARD_PLATFORMS`, dan itu terpenuhi:

```
QCOM_BOARD_PLATFORMS  = msm8916      <- gerbang is-board-platform-in-list lolos
TARGET_BOARD_PLATFORM = msm8916
TARGET_KERNEL_ARCH    = arm64
PLATFORM_VERSION      = 16
```

### Jebakan lingkungan: `grep` adalah fungsi shell

`lunch` mula-mula gagal untuk **semua** product, termasuk `aosp_arm64`, dengan

```
product_config.mk:226: error: Cannot locate config makefile for
                       product "lineage_A37-bp4a-userdebug"
```

Perhatikan seluruh combo diperlakukan sebagai nama product. Sebabnya
`build/make/envsetup.sh:588`:

```bash
local legacy=$(echo $1 | grep "-")
```

Di lingkungan ini `grep` bukan `/usr/bin/grep` melainkan **fungsi shell** dari
profil pengguna yang mengalihkan ke `ugrep`. `ugrep "-"` menganggap `-` sebagai
awalan opsi dan gagal:

```
$ echo "lineage_A37-bp4a-userdebug" | grep "-"
ugrep: no PATTERN specified

$ echo "lineage_A37-bp4a-userdebug" | /usr/bin/grep "-"
lineage_A37-bp4a-userdebug
```

`legacy` jadi kosong, lunch mengambil jalur "format baru", dan seluruh string
masuk sebagai `product`. Tidak terlihat sebagai alias — fungsi menang atas PATH
dan tidak muncul di `alias`.

**Penanganan:** jalankan `unset -f grep` sebelum `source build/envsetup.sh` pada
setiap sesi build. Sesudahnya `lunch lineage_A37-bp4a-userdebug` menghasilkan
`TARGET_PRODUCT=lineage_A37` dengan benar.

---

## 8c. Fase 2 sedang berjalan

### Kernel terbangun — tanpa satu pun backport

Milestone pertama Fase 2 tercapai:

```
m -j8 bootimage   ->  build completed successfully (11:09)

boot.img                            19.888.128 byte
kernel                              18.327.160 byte
KERNEL_OBJ/arch/arm64/boot/Image
```

**K3 dan K5 ternyata tidak dibutuhkan untuk membangun kernel.** Rencana menandai
keduanya WAJIB, tapi itu diturunkan dari 167 commit acroreiser yang seluruhnya
dikerjakan demi eBPF. Karena jalur yang dipilih userspace BPF-less, kernel
3.10.108 apa adanya kompilasi bersih dengan toolchain Android 16.

`epoll_pwait2` tetap perlu ditangani, tapi itu soal runtime grafis, bukan build.

### Tiga kegagalan build, tiga sumber perbaikan berbeda

| # | Kegagalan | Kelas | Sumber perbaikan |
|---|---|---|---|
| 1 | 2 modul HAL hilang (vibrator, livedisplay) | HIDL dihapus | ditunda ke Fase 6 |
| 2 | `hardware/display_defs.h` tidak ditemukan | header dihapus | ULH `legacy_support_patches` |
| 3 | `attribute vendor_hal_soter_client is not declared` | sepolicy | patch kit 22.2 kita sendiri |
| 4 | `unknown type hal_lineage_livedisplay_hwservice` | HIDL dihapus | konsekuensi keputusan #1 |
| 5 | `property_get(..., false)` ditolak | **compiler makin ketat** | perbaikan sendiri |

Kegagalan #5 berbeda kelas dari empat sebelumnya. Empat pertama soal API atau
berkas yang hilang; yang kelima soal kode lama yang sebenarnya selalu salah tapi
baru sekarang ditolak:

```
bt_vendor_qcom.c:343:49: error: initialization of pointer of type 'const char *'
                         to null from a constant boolean expression
   property_get(BT_VND_FILTER_START, value, false);
```

Parameter ketiga bertipe `const char*`; kode melewatkan `false`. Clang r563880c
menolaknya. Diganti `NULL` — mempertahankan perilaku persis, karena itu memang
nilai yang selama ini dihasilkan. Bahwa `NULL` idiom yang benar terbukti dari
berkas yang sama: enam pemanggilan lain sudah memakainya.

Kelas ini biasanya datang bergerombol, jadi perkirakan muncul lagi di blob CAF
lain.

Yang kedua membuktikan keputusan Fase 0 bahwa `legacy_support_patches` wajib:
set n7000 berbasis Exynos tidak akan pernah membawa patch display QCOM.

Yang ketiga menunjukkan nilai dokumentasi kit lama. Pesan commit patch 22.2
merekam kekeliruan yang pernah dibuat — versi pertamanya juga mendeklarasikan
`vendor_hal_gnss_qti` dan `vendor_hal_perf_default`, dan itu salah karena memicu
`Duplicate declaration of type`. Hanya soter yang benar-benar kurang. Tanpa
catatan itu kesalahan yang sama besar kemungkinan terulang.

Dua patch sepolicy 22.2 lainnya (`0302`, `0401`) **konflik** terhadap pohon 23.2
dan sengaja tidak dipaksakan.

### Catatan operasional: pakai `-j8`

Default Soong adalah `nproc + 2`, yang di mesin ini berarti `-j14`. Dengan nilai
itu build dibunuh SIGTERM (`exit status 143`) dua kali. Diukur saat build aktif,
memori tinggal **602 MB dari 11.958 MB**.

```
-j14   dibunuh dua kali
-j8    selesai, rc=0
```

Catatan jujur: `143` adalah SIGTERM, sedangkan OOM killer kernel mengirim SIGKILL
(137) — jadi kemungkinan pengawas di atas kernel yang bereaksi terhadap tekanan
memori, bukan kernel itu sendiri. Mekanismenya belum terbukti penuh, tapi
hubungannya dengan `-j` konsisten.

Sebutkan `-j8` eksplisit di setiap build 23.2.

---

## 8d. Fase 2 SELESAI — ROM 23.2 terbangun

```
#### build completed successfully (08:31) ####
lineage-23.2-20260822_171611-UNOFFICIAL-A37.zip   807.232.220 byte
post-sdk-level=36   ota-type=BLOCK
```

Dua belas kegagalan, sembilan kelas berbeda. **Tidak satu pun menyentuh kernel** —
konsisten dengan keputusan Fase 0 menempuh jalur userspace BPF-less.

| # | Kegagalan | Kelas | Sumber perbaikan |
|---|---|---|---|
| 1 | 2 modul HAL hilang | HIDL dihapus | ditunda ke Fase 6 |
| 2 | `display_defs.h` | header dihapus | ULH `legacy_support_patches` |
| 3 | atribut soter | sepolicy | **kit 22.2** |
| 4 | tipe hwservice HIDL | HIDL dihapus | konsekuensi #1 |
| 5 | `property_get(..., false)` | compiler ketat | sendiri |
| 6 | `SYN_TIME_SEC` | header kernel tak diekspor | sendiri |
| 7 | typedef `acdb_init` | typedef salah, tersingkap | sendiri |
| 8 | `%ld` untuk `int64_t` | bug hulu, hanya 32-bit | sendiri |
| 9 | `check_elf_files` skrip | pemeriksaan baru | sendiri |
| 10 | `sepolicy_test` | sepolicy | **kit 22.2** |
| 11 | `check_vintf_compatible` | matriks VINTF | **kit 22.2** (pola) |
| 12 | `zip: Bad address` | symlink diikuti | **kit 22.2** |

Empat kali kit 22.2 langsung terpakai. Bukan kebetulan: kelas masalahnya sama —
perangkat pre-UM non-Treble yang dibangun sebagai root.

### Kegagalan #12 layak dicatat tersendiri

Saya sempat menuduh disk penuh dan membebaskan 38 GB; build tetap gagal di titik
sama. Justru ketidakcocokan itu yang menyingkap sebabnya — `Bad address` adalah
`EFAULT`, bukan `ENOSPC`.

Yang sesungguhnya: `RECOVERY/RAMDISK/d` symlink ke `/sys/kernel/debug`, dan zip
mengikutinya sampai membaca debugfs mesin build. Petunjuknya ada tepat sebelum
gagal — `zip warning: file size changed while zipping`.

Pesan commit patch 22.2 bahkan mencatat syarat pemicunya: hanya terjadi bila
`target_file` berupa direktori DAN build berjalan sebagai root.

### Yang belum terbukti

ROM belum pernah di-flash. Build hijau membuktikan ia **terbangun**, bukan ia
**boot**. Syarat lulus Fase 2 menuntut boot ke bootanimation.

Yang sengaja dinonaktifkan untuk sampai ke titik ini, semuanya bertanda TODO
Fase 6: vibrator, LiveDisplay, dan tiga baris sepolicy hwservice.

---

## 9. Urutan kerja

Setiap fase punya syarat lulus. Jangan lanjut sebelum terpenuhi.

| Fase | Isi | Lulus bila |
|---|---|---|
| **0** | ~~Pertanyaan terbuka~~ — keduanya sudah terjawab: cgroup v2 (K2a) dan RenderEngine (bagian 7) | selesai |
| **1** | ~~Manifest + sync + patch QCOM~~ **SELESAI** — lihat bagian 8b | `QCOM_BOARD_PLATFORMS` memuat msm8916; `lunch` menghasilkan `TARGET_PRODUCT=lineage_A37` |
| **2** | ~~K3 + K5~~ tidak diperlukan; 12 kegagalan build diperbaiki — lihat 8d | ROM terbangun ✓ · boot **belum diuji** |
| **3** | Userspace: system/core cgroup, bionic, sepolicy legacy | boot sampai homescreen |
| **4** | Terapkan rantai patch BPF-less (9 patch, lihat K2b) | tidak bootloop, jaringan hidup tanpa BPF |
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

**Risiko terbesar sudah hilang.** Sebelum K2b terjawab, rencana ini bertumpu pada
kemungkinan backport ~1.300 commit kernel. Sekarang jalurnya 89 patch userspace
yang sudah jadi dan terbukti di perangkat kernel 3.0.

Yang tersisa:

**Rantai patch belum tentu berlaku apa adanya.** 89 patch itu disusun untuk
Exynos 4210, bukan msm8916. Yang tidak relevan (Broadcom Wi-Fi, RIL v6/v8/v9,
`mkbootimg --dt`) harus disaring, dan sebagian mungkin bentrok dengan patch A37
yang sudah ada dari 22.2.

**Grafis.** SkiaGL terbukti menjatuhkan SurfaceFlinger di Adreno 306 (bagian 7).
Fork ULH atau patch GLES RenderEngine dari set n7000 diperlukan; ini pekerjaan
userspace terbesar yang tersisa.

**hardware/ril berpindah tangan.** Fork LineageOS dihapus di 23.2. Patch RIL 22.2
kita tidak bisa dipakai apa adanya; set n7000 punya 2 patch `hardware/ril`, ULH
punya fork `lineage-23.2`.

**Jaringan tanpa eBPF berarti fitur hilang, bukan cuma "aman".** Statistik data
per-aplikasi, firewall berbasis BPF, dan pembatasan latar belakang bergantung
padanya. Di 22.2 kita hidup tanpa itu dan tidak terasa mengganggu; harapkan hal
yang sama, tapi jangan janjikan setara.

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

Rujukan patch (di `ref/`):

```
zk-patches         zhafknight/los_patches — 89 patch LOS 23.2 untuk n7000 (kernel 3.0)
gsi-23.2           MisterZtr/LineageOS_gsi branch lineage-23.2
ulh-patches-23.2   ULH legacy_support_patches — 38 patch, termasuk 2 khusus QCOM
j0sh1x             J0SH1X n7000_android_16_patches — dump diff, lineage-23.0, rujukan
dt-a37             device tree A37 lineage-22
```

Ditambahkan ke `src/`: `qcom-common-23.2` (hardware/qcom-caf/common 23.2), dipakai
membuktikan msm8916 sudah dihapus dari lapisan QCOM.

`rINanDO/galaxys2-patches` tidak diunduh — mentok di `lineage-21.0`.

Belum diunduh: `android_device_qcom_sepolicy` (`lineage-23.2-legacy`),
`android_hardware_qcom-caf_common`, `MisterZtr/LineageOS_gsi`, device tree A37
sendiri.
