# Rantai BPF-less dan kompatibilitas kernel legacy

Sumber: `zhafknight/los_patches` set `los-23.2_n7000` (LineageOS 23.2 untuk
Samsung GT-N7000, Exynos 4210, kernel 3.0). Patch disalin apa adanya, tidak
dimodifikasi, supaya bisa ditelusuri balik ke hulunya.

Dipakai setelah bukti dari perangkat: ROM boot sampai detik 15,4 lalu
`init: Service bpfloader has 'reboot_on_failure' option and failed`, dengan
`NetBpfLoad: Android S & T require kernel 4.9.` (`NetBpfLoad.cpp:1609`).
Ini keputusan jalur B di `PLAN-LOS23.md` bagian K2b.

## Rantai BPF-less (21)

frameworks/native 009 | Connectivity 036 037 038 039 040 041 042 043 045 046
047 048 | DnsResolver 049 | system/bpf 050 051 052 | system/netd 053 054 093 |
system/vold 055

Inti: `043-NetBpfLoad-Relax-all-kernel-version-and-capability-checks` mengubah
setiap gerbang `ALOGE` + `return N` menjadi `ALOGW`, dan melepas
`reboot_on_failure reboot,bpfloader-failed` dari `netbpfload.35rc`.

## Kompatibilitas kernel legacy (16)

bionic 001 002 087 | frameworks/base 005 006 007 | frameworks/native 010 |
system/apex 020 092 | system/core 022 025 026 030 | lmkd 032 | sepolicy 033 |
Connectivity 091

Dipilih berdasar bukti di log perangkat sendiri, yang menunjukkan cgroup v2
tidak ada:

    libprocessgroup: Failed to open /sys/fs/cgroup/system/uid_0/pid_215/cgroup.procs
    init: createProcessGroup(0, 536) failed for service 'bpfloader'

`bionic/001` (epoll_pwait2 fall back ke epoll_pwait) menyelesaikan sebagian K3
di userspace, jadi backport syscall ke kernel tidak diperlukan untuk itu.

## Sengaja TIDAK diambil

`bionic/003-...MADV_WIPEONFORK...` — pohon ini sudah punya penyelesaian sendiri
di `patches/bionic/0001-arc4random-...`, ditambah backport kernelnya
(`BACKPORT: mm,fork: introduce MADV_WIPEONFORK`, commit db809bdd).

## Sudah ada di pohon, tidak perlu diterapkan

Lima patch gagal diterapkan karena fork ULH sudah memuatnya. Diverifikasi
dengan `git apply --check --reverse`, bukan diduga:

    system/core 023  Fix support for devices without cgroupv2 support
    system/core 024  Restore old kernel support in init and libprocessgroup
    system/libhidl 034
    system/libhwbinder 035
    frameworks/native 011

## Belum diambil, khas perangkat lain

Sisa set (Samsung brightness, SCO/eSCO Exynos, revert OMX software codec,
forward-port GLES RenderEngine, RIL v6-v9) belum dievaluasi untuk A37 dan
sebagian jelas tidak relevan.

## Tambahan setelah ROM mencapai boot animation

`frameworks/base/088-local-0001-services-tolerate-unavailable-Power-HAL-hint-support`

Diambil belakangan, setelah terbukti jadi penghenti boot. `system_server` mati
enam kali di `startOtherServices`, tidak pernah melewati fase 100:

    Failed to create service com.android.server.power.hint.HintManagerService
    Caused by: NullPointerException: Attempt to read from field
      'android.hardware.power.SupportInfo$HeadroomSupportInfo
       android.hardware.power.SupportInfo.headroom' on a null object reference
      at HintManagerService.<init>(HintManagerService.java:337)

Frasa `on a null object reference` menunjuk `mSupportInfo` sendiri yang null,
bukan `headroom` -- artinya `mPowerHal == null` dan blok pengisiannya dilewati
seluruhnya. A37 memang tidak punya Power HAL AIDL. Patch memberi `SupportInfo`
kosong sebagai fallback lalu mematikan headroom CPU/GPU.

Yang menyesatkan di sini: `system_server` dibunuh dengan SIGKILL
(`Process: Sending signal. PID: 5047 SIG: 9`) oleh dirinya sendiri setelah
fatal exception, sehingga tidak menghasilkan tombstone dan tidak muncul sama
sekali di daftar proses yang crash. Satu-satunya yang terlihat di sana adalah
cameraserver, yang ternyata bukan penyebab stuck.

Catatan alat ukur: `dmesg.txt` di /data/bootfail hanya memuat ~3 detik terakhir
karena ring buffer sudah berputar oleh banjir denial SELinux. Jangan memakainya
untuk menyimpulkan apa pun tentang awal boot -- pakai logcat.txt.

## Dicabut

`build_soong/0001-soong_ui-teruskan-SOONG_GOGC-SOONG_GOMEMLIMIT` dihapus.

Patch itu menekan puncak RSS soong_build agar muat di RAM 11,9 GB, tapi ongkosnya
berat: build penuh 8 menit menjadi 27 menit karena GC bekerja jauh lebih sering.
Dan pengukuran menunjukkan heap yang hidup memang ~10 GB -- dengan
SOONG_GOMEMLIMIT=6GiB pun RSS tetap memuncak di 9,4 GB, karena GOMEMLIMIT adalah
batas lunak yang dilampaui Go daripada mati.

Diganti dengan menaikkan swap ke 24 GB, yang menyelesaikan sebabnya, bukan
gejalanya.

## Koreksi besar: namespace linker vendor

Dua patch linkerconfig yang sempat ada di kit ini SUDAH DIBUANG, dan direktori
`system_linkerconfig` kini KOSONG. Hasil akhirnya nol perubahan: pohon
`system/linkerconfig` kembali persis ke keadaan hulu -- diverifikasi dengan
`git diff 1274364 HEAD`, keluarannya kosong.

Sebelumnya yang disimpan di sana justru dua patch REVERT-nya. Itu TIDAK BISA
DIPAKAI: patch aslinya tidak pernah ada di kit, sehingga `git apply` atas kedua
revert itu gagal pada checkout baru -- diverifikasi dengan `git apply --check`,
keduanya GAGAL. Yang perlu diwariskan dari episode ini adalah penjelasan di
bawah, bukan berkas patch-nya.

Patch aslinya menambahkan `/system/${LIB}` ke search path namespace vendor,
untuk menolong blob kamera menemukan pustaka platform. Itu SALAH dan merusak
jauh lebih banyak daripada yang diperbaiki.

`libbinder_ndk.so` ada di daftar tautan LLNDK namespace vendor ke system, jadi
secara bawaan ia dimuat DI namespace system dan berpasangan dengan libbinder
sistem. Search path dikonsultasikan SEBELUM tautan, sehingga penambahan itu
membayangi tautan tersebut: libbinder_ndk sistem berpasangan dengan libbinder
vendor, dan SEMUA HAL AIDL vendor gagal mendaftar.

  service.cpp:64] Check failed: result == STATUS_OK (result=-129)
                  Failed to register wifi HAL        (-129 = EX_TRANSACTION_FAILED)

Akibatnya Wi-Fi, RIL, dan Bluetooth mati sekaligus, dan halaman Wi-Fi di
Settings menggantung -- yang terlihat pengguna sebagai "Settings isn't
responding".

Dibuktikan langsung di perangkat dengan menyunting /linkerconfig/ld.config.txt
(ia di tmpfs, bisa ditulis root) lalu menghidupkan ulang servisnya:

  tanpa /system di search path  -> IWifi found, ISupplicant found, wlan0 muncul
  dengan /system di search path -> IWifi not found
  /system di urutan pertama     -> gagal total (static initializer crash)

Penggantinya: pasang varian vendor pustaka yang dibutuhkan ke /vendor/lib
(libsqlite.vendor, libstdc++_vendor + symlink). Itu cara acroreiser/ULH a6010
menyelesaikannya, dan tidak menyentuh linker sama sekali.
