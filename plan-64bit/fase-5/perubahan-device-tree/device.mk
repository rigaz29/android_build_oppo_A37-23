#
# Copyright (C) 2016 The CyanogenMod Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Boot animation
TARGET_SCREEN_HEIGHT := 1280
TARGET_SCREEN_WIDTH := 720

# AAPT CONFIG
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xhdpi

# Display
# composer@2.1-impl → composer@2.1-service (18.1: impl dihapus, service saja)
# Sumber: msm8916-common lineage-18.1
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.mapper@2.0-impl-2.1 \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.memtrack@1.0-impl \
    android.hardware.memtrack@1.0-service \
    gralloc.msm8916 \
    hwcomposer.msm8916 \
    libtinyxml \
    memtrack.msm8916 \
    copybit.msm8916

# RenderScript HAL
PRODUCT_PACKAGES += \
    android.hardware.renderscript@1.0-impl

# Properties
#
# debug.sf.latch_unsignaled=1 DIBUANG — sedang diuji sebagai penyebab glitch
# wallpaper sesaat setelah layar dinyalakan. Properti itu membuat
# BufferLayer::fenceHasSignaled() (frameworks/native/.../BufferLayer.cpp:579)
# mengembalikan true tanpa memeriksa acquire fence sama sekali, sehingga
# SurfaceFlinger boleh menampilkan buffer yang render-nya BELUM selesai. Itu
# cocok dengan gejala "sebentar tidak pas lalu benar sendiri". Default AOSP
# memang 0, jadi membuangnya = kembali ke perilaku benar.
#
# debug.sf.disable_backpressure DIBUANG — terbukti menghambat kelancaran UI.
# Properti ini mematikan backpressure di SurfaceFlinger scheduler
# (FrameTargeter.cpp: considerBackpressure=false), sehingga app yang lambat
# render tidak ditekan dan bebas menumpuk frame di pipeline. Di Adreno 306
# yang GPU-nya sudah kewalahan, ini memonopoli GPU dan memperparah jank.
# Sebelumnya ditahan untuk bisection glitch wallpaper; latch_unsignaled sudah
# teridentifikasi sebagai penyebab glitch, jadi properti ini tidak lagi
# diperlukan. Default AOSP (0, backpressure aktif) = perilaku benar.
#
# Tujuh properti berikut dibuang karena NOL pembaca di seluruh tree
# (frameworks/, hardware/, system/, vendor/qcom/) — cuma pajangan:
#   debug.enable.sglscale, debug.egl.hw, debug.sf.disable_hwc,
#   debug.sf.recomputecrop, debug.cpurend.vsync, debug.sf.gpu_comp_tiling,
#   debug.performance.tuning
# Catatan: debug.sf.recomputecrop sekilas paling mencurigakan untuk masalah
# "tidak pas ke layar", tapi Android 10 tidak membacanya sama sekali.
#
# Yang tetap ada karena terbukti dibaca: debug.composition.type dan
# debug.mdpcomp.idletime dibaca hardware/qcom-caf/msm8916/display (tree display
# yang benar-benar dibangun device ini), debug.sf.hw dibaca SurfaceFlinger.cpp,
# debug.hwui.use_buffer_age dibaca frameworks/base/libs/hwui/Properties.h.
PRODUCT_PROPERTY_OVERRIDES += \
    debug.composition.type=c2d \
    ro.surface_flinger.max_frame_buffer_acquired_buffers=3 \
    ro.surface_flinger.vsync_event_phase_offset_ns=5000000 \
    ro.surface_flinger.vsync_sf_event_phase_offset_ns=7500000 \
    debug.mdpcomp.idletime=600 \
    persist.hwc.mdpcomp.enable=true \
    persist.hwc.ptor.enable=true \
    pm.dexopt.shared=quicken \
    pm.dexopt.downgrade_after_inactive_days=10 \
    debug.sf.hw=1 \
    video.accelerate.hw=1
# dex2oat compiler filter.
#
# KOREKSI terhadap catatan sebelumnya, yang menyatakan "TIDAK ADA app yang
# di-AOT compile". Itu tidak akurat untuk aplikasi SISTEM. Diukur langsung di
# perangkat pada ROM sebelum perubahan ini:
#
#   82 dari 83 APK sistem punya .odex (hanya qcrilmsgtunnel yang tidak)
#   total .odex di /system   95.855.736 byte  (91 MB kode native, ELF)
#   total .vdex di /system    7.806.647 byte
#   SystemUI            .odex 52,4 MB  vs .vdex 900 KB   -> rasio 58x
#   Launcher3QuickStep  .odex 26,2 MB  vs .vdex 333 KB   -> rasio 79x
#
# Rasio sebesar itu hanya mungkin kalau isinya memang kode terkompilasi penuh.
# Aplikasi sistem SUDAH di-AOT compile lewat WITH_DEXPREOPT saat build.
#
# Penyebab salah baca: untuk aplikasi sistem yang sudah di-preopt, "dumpsys
# package" melaporkan keadaan salinan di /data -- yang memang tidak ada karena
# tidak perlu dikompilasi ulang. Itu tampak seperti status=verify, padahal
# bukan berarti aplikasinya berjalan interpreted.
#
# Guard ifneq(TARGET_BUILD_VARIANT,eng) yang dilepas di BoardConfig.mk juga
# tidak berpengaruh pada build ini: variannya userdebug, bukan eng, sehingga
# WITH_DEXPREOPT memang sudah aktif sejak awal. Konsekuensinya perkiraan
# "system image membesar 300-500 MB" tidak akan terjadi.
#
# Yang BENAR-BENAR diperbaiki blok ini adalah aplikasi yang dipasang PENGGUNA
# ke /data. Di situ speed-profile tanpa berkas .prof memang jatuh ke verify,
# sehingga aplikasi berjalan interpreted + JIT -- lambat di Cortex-A53 1,2 GHz.
# Menyetelnya ke speed memaksa AOT penuh saat pemasangan.
# SELURUH BLOK INI DICABUT 31 Agustus 2026 -- kembali ke default AOSP.
# Sebelumnya berbunyi:
#
#     pm.dexopt.install=speed                      (default: speed-profile)
#     pm.dexopt.install-fast=speed                 (default: skip)
#     pm.dexopt.install-bulk=speed                 (default: speed-profile)
#     pm.dexopt.install-bulk-secondary=speed       (default: verify)
#     pm.dexopt.install-bulk-downgraded=speed      (default: verify)
#     pm.dexopt.install-bulk-secondary-downgraded=speed  (default: verify)
#     pm.dexopt.ab-ota=speed                       (default: speed-profile)
#     pm.dexopt.cmdline=speed                      (default: verify)
#     dalvik.vm.systemservercompilerfilter=speed
#     dalvik.vm.systemuicompilerfilter=speed
#
# Default AOSP ada di build/make/target/product/runtime_libart.mk:117-127.
#
# ALASAN MENCABUT: pemasangan APK jadi sangat lama, dan itu dilaporkan sebagai
# keluhan nyata. Diukur di perangkat dengan dex2oat langsung pada
# messaging.apk (11 MB):
#
#     verify         1 dtk    oat 49 KB
#     speed-profile  1 dtk    oat 49 KB
#     speed         12 dtk    oat 11,2 MB     <- 12x lebih lambat
#
# Alasan ASLI blok ini tetap SAHIH secara fakta, dan pengukuran di atas
# membuktikannya: speed-profile tanpa berkas .prof memang menghasilkan keluaran
# yang identik dengan verify, sehingga aplikasi baru berjalan interpreted + JIT.
# Yang berubah bukan faktanya, melainkan penilaian atas pertukarannya --
# 12 detik per APK setiap kali memasang, ditukar dengan kecepatan yang hanya
# terasa sampai background dexopt mengambil alih.
#
# Jalur itu memang berjalan di perangkat ini: pm.dexopt.bg-dexopt=speed-profile
# (blok di bawah, sama dengan default) dan sudah ada 188 profil di
# /data/misc/profiles/cur/0/. Jadi aplikasi tetap akan dikompilasi penuh,
# hanya saat perangkat idle dan mengisi daya, bukan saat pengguna menunggu.
#
# dalvik.vm.systemuicompilerfilter TIDAK PERLU diset di sini: LineageOS sudah
# menyetelnya ke speed di vendor/lineage/config/common.mk:261.
# dalvik.vm.systemservercompilerfilter dibiarkan default ART (speed-profile).

# JANGAN setel keempat filter jalur boot ke speed. Ini BUKAN kehati-hatian
# teoretis: build 20260826_135516 menyetel pm.dexopt.first-boot=speed dan
# perangkat GAGAL BOOT -- tertahan di bootanimation lalu dilempar bootwatchdog
# ke recovery.
#
# Terbaca di /data/bootfail dari kejadian itu:
#   tertahan-detik.txt              365
#   sys.system_server.start_count   1        (system_server TIDAK crash)
#   baris dex2oat di logcat         2343     (2260 di antaranya dex2oat32)
#   nol baris FATAL
#   tiga baris terakhir: dex2oat32 masih mengompilasi androidx.fragment.app
#   dan kotlin.reflect.jvm saat watchdog memotong, bootanimation masih berputar
#
# Penyebabnya: dengan first-boot=speed, PackageManager meng-AOT compile SELURUH
# aplikasi pada boot pertama setelah flash. Di Cortex-A53 1,2 GHz itu jauh
# melewati batas bootwatchdog, dan karena tidak pernah selesai, setiap boot
# mengulang dari nol -- bootloop permanen, bukan sekadar boot lambat sekali.
#
# Diverifikasi bahwa ini memang penyebabnya: mengubah keempat properti menjadi
# verify langsung di build.prop lewat recovery membuat perangkat boot bersih di
# 123 detik dengan start_count=1.
#
# Default AOSP untuk keempatnya adalah verify (build/make/target/product/
# runtime_libart.mk:113-116, memakai ?= sehingga override apa pun menang).
# Karena itu keempatnya cukup TIDAK di-override sama sekali.
#
# Filter install-* di atas aman: jalur itu berjalan saat pengguna memasang
# aplikasi, bukan saat boot, dan di situlah manfaat speed benar-benar terasa.

# Dua filter di bawah SENGAJA tidak ikut speed.
#
# bg-dexopt berjalan berkala di latar belakang. Dengan speed ia mengompilasi
# ulang seluruh aplikasi setiap siklus; di Cortex-A53 dengan RAM 2 GB itu
# mahal -- CPU penuh, panas, dan baterai terkuras, untuk pekerjaan yang sudah
# dilakukan saat pemasangan. speed-profile membiarkannya bekerja terarah
# berdasarkan profil pemakaian nyata.
#
# inactive justru ADA untuk menurunkan aplikasi yang lama tidak dipakai ke
# verify demi menghemat penyimpanan. Menyetelnya ke speed membatalkan tujuan
# setelan itu dan menahan kode native untuk aplikasi yang tidak dibuka.
PRODUCT_PROPERTY_OVERRIDES += \
    pm.dexopt.bg-dexopt=speed-profile \
    pm.dexopt.inactive=verify

# debug.hwui.renderer=opengl DIBUANG di 20 — properti MATI, dan menyesatkan.
#
# frameworks/base/libs/hwui/Properties.cpp:198-199:
#     rendererProperty = GetProperty(PROPERTY_RENDERER, useVulkan ? "skiavk" : "skiagl");
#     if (rendererProperty == "skiavk") { ... }
# Hanya "skiavk" yang dicocokkan; nilai lain -- termasuk "opengl" -- jatuh ke
# SkiaGL. Pipeline OpenGL lama HWUI sudah dicabut sejak Android 10, jadi baris
# ini tidak pernah berpengaruh di 19.1 maupun 20.
#
# Menyesatkannya: SurfaceFlinger MEMANG menghindari Skia lewat
# debug.renderengine.backend=gles di bawah (perbaikan 10.B), sehingga baris ini
# mudah dibaca seolah rendering aplikasi juga non-Skia. Tidak. HWUI berjalan di
# SkiaGL, dan di Android 13 tidak ada alternatifnya.
#
# JANGAN tambahkan ro.hwui.render_ahead sebagai gantinya (meghs A37 lineage-20
# dan a6010 lineage-20.0 sama-sama memakainya): properti itu juga MATI di A13.
# Getter render_ahead() ada di Properties.cpp:42 tapi TIDAK PERNAH dipanggil;
# anggota Properties::renderAhead tidak ada; setRenderAheadDepth/
# mRenderAheadDepth -- mekanisme Android 11-nya -- sudah dicabut seluruhnya.
# Diverifikasi dengan grep seluruh frameworks/base, 8 Agustus 2026.

# SurfaceFlinger di Android 12 — WAJIB, tanpa ini SF crash-loop dan ROM berhenti
# di logo OPPO (Fase 10.B).
#
# A12 mengganti RenderEngine default SurfaceFlinger dari GLES ke Skia:
# RenderEngine.h:317-318 menyetel SKIA_GL_THREADED. Adreno 306 dengan driver CAF
# lama tidak sanggup, dan SF mati dengan:
#   F DEBUG: Abort message: 'Unable to generate SkImage. isTextureValid:1 dataspace:513'
# empat belas kali berturut-turut di logcat -b crash.
#
# RenderEngine.cpp:32-44 membaca debug.renderengine.backend dan menerima
# "gles", "threaded", "skiagl", "skiaglthreaded". Dipilih `gles` mengikuti dua
# sumber yang sepakat: ROM referensi 19.1 A37 yang TERBUKTI boot di perangkat ini
# (system-build.prop:134) dan device tree a6010 lineage-19.1 (device.mk:78).
# cyanogen msm8916-common memakai `threaded`; kalau `gles` bermasalah, itu
# alternatif pertama yang dicoba.
#
# debug.sf.disable_client_composition_cache DIBUANG — terbukti penyebab utama
# GPU stall 4950ms dan 2736 HWC missed frames. Properti ini mematikan caching
# hasil komposisi klien di SurfaceFlinger, sehingga SETIAP frame di-render
# ulang penuh oleh GPU meski layer tidak berubah. Di Adreno 306 (19.2 GFLOPS)
# ini membebani GPU secara masif: histogram GPU menunjukkan 31% frame Launcher
# dan 19% frame SystemUI stuck di 4950ms (timeout GPU fence). Setelah dibuang,
# HWC kembali melakukan device composition (usesDeviceComposition=true),
# missed frames turun dari 2736 ke 6, dan P50 frame time Launcher turun dari
# 42ms ke 6ms. Default AOSP (0, cache aktif) = perilaku benar.
#
# Tiga properti sisanya BUKAN penyebab crash — semuanya penyetelan SF untuk GPU
# legacy yang dipunyai ROM referensi dan tidak kita punya. Ditambahkan sekaligus
# agar konfigurasinya sepadan dengan referensi yang terbukti. ⚠️ Kalau nanti
# muncul gejala baru di SF, ketiga baris inilah yang pertama di-bisect, bukan
# debug.renderengine.backend.
PRODUCT_PROPERTY_OVERRIDES += \
    debug.renderengine.backend=gles \
    debug.sf.enable_gl_backpressure=1 \
    debug.sf.enable_planner_prediction=false \
    debug.sf.recomputecrop=0

# Screen density
PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=280 \
    persist.graphics.vulkan.disable=true \
    persist.dbg.ims_volte_enable=1 \
    persist.dbg.volte_avail_ovr=1 

# Disable buffer age
PRODUCT_PROPERTY_OVERRIDES += \
    debug.hwui.use_buffer_age=false

# DRM
# clearkey @1.2 → @1.3 (Sumber: msm8916-common lineage-18.1)
#
# LOS 21: clearkey HIDL DICABUT. Diverifikasi di tree UL 21 — hanya varian AIDL
# yang tersisa; @1.4-service.clearkey tidak ada lagi:
#
#   grep -rho 'name: "android.hardware.drm[^"]*clearkey"' --include=Android.bp .
#     android.hardware.drm-service.clearkey        ← dipakai (non-lazy)
#     android.hardware.drm-service-lazy.clearkey
#     android.hardware.drm@latest-service.clearkey
#
# @1.0-impl dan @1.0-service MASIH ADA dan tetap dipakai (dicek terpisah).
# fqname clearkey di manifest.xml harus ikut dibuang — Fase 3.
PRODUCT_PACKAGES += \
    android.hardware.drm@1.0-impl \
    android.hardware.drm@1.0-service \
    android.hardware.drm-service.clearkey \
    android.hardware.drm@1.1.vendor \
    libprotobuf-cpp-lite-26-a37 \
    libprotobuf-cpp-lite-26-a37_symlink

# Widevine.
#
# runtime protobuf 3.0.0 dibangun dari sumber di protobuf26/; blob-nya sendiri
# (biner service, libwvhidl.so, init rc) datang lewat A37-vendor.mk.
# Rinciannya di proprietary-files.txt.
#
# android.hardware.drm@1.1.vendor WAJIB. Biner Widevine adalah prebuilt, jadi
# Soong tidak tahu ia menautnya, dan /vendor/lib hanya punya @1.0 -- yang ikut
# terpasang sebagai dependensi android.hardware.drm@1.0-service. Tanpa varian
# vendor @1.1, servisnya crash-loop tiap 5 detik:
#
#   F linker: CANNOT LINK EXECUTABLE
#     "/vendor/bin/hw/android.hardware.drm@1.1-service.widevine":
#     library "android.hardware.drm@1.1.so" not found
#
# Uji shell sebelumnya TIDAK menangkap ini karena LD_LIBRARY_PATH-nya menyertakan
# /system/lib; servis sungguhan berjalan di namespace linker vendor yang tidak
# bisa melihat ke sana. Pola .vendor sama seperti android.hardware.bluetooth@1.0
# di atas.

PRODUCT_PROPERTY_OVERRIDES += \
    ro.opengles.version=196608

# ⚠️ ro.hardware.egl=adreno — WAJIB. Tanpa ini SurfaceFlinger crash-loop dan ROM
# berhenti di logo OPPO.
#
# libEGL memilih driver dengan menempelkan nilai properti ke nama pustaka:
# libEGL_${prop}.so di /vendor/lib/egl. Urutan propertinya
# (Loader.cpp:72-76 HAL_SUBNAME_KEY_PROPERTIES):
#
#     persist.graphics.egl  ->  ro.hardware.egl  ->  ro.board.platform
#
# Dan Loader.cpp:304 BERHENTI setelah properti PERTAMA yang terisi:
#     // Abort regardless of whether subsequent properties are set, the value
#     // must be set correctly with the first property that has a value.
#     break;
#
# Perangkat ini mengirim /vendor/lib/egl/libEGL_adreno.so (plus GLESv1_CM dan
# GLESv2 adreno). Tanpa ro.hardware.egl, dua properti pertama kosong sehingga
# loop jatuh ke ro.board.platform=msm8916, mencari libEGL_msm8916.so yang tidak
# ada, lalu BERHENTI. Terlihat di logcat perangkat (report/bootfail/):
#
#     D libEGL: Failed to load drivers from property ro.board.platform
#               with value msm8916
#     F libEGL: couldn't find an OpenGL ES implementation, make sure one of
#               persist.graphics.egl, ro.hardware.egl and ro.board.platform is set
#     F DEBUG : pid 679, name: surfaceflinger  >>> /system/bin/surfaceflinger <<<
#               signal 6 (SIGABRT)
#               #06 android::renderengine::gl::GLESRenderEngine...
#
# SurfaceFlinger lalu di-restart init tiap ~5 detik, menyeret zygote ikut mati,
# sehingga boot tidak pernah selesai.
#
# ⚠️ LOS 20 BOOT TANPA PROPERTI INI — jangan jadikan itu alasan membuangnya.
# Perangkat LOS 20 yang berjalan pun hanya punya ro.board.platform (diperiksa di
# bugreport-nya), jadi Android 13 masih punya jalur cadangan yang Android 14
# cabut. Ini regresi hulu, bukan kesalahan konfigurasi lama.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware.egl=adreno

# Trust HAL DIBUANG di LOS 21 — hardware/lineage/interfaces/ tidak punya trust/
# lagi, termasuk di fork UL. meghs juga membuangnya di lineage-21
# ("Drop legacy trust HAL — dead"). Tidak ada penggantinya; fiturnya hilang.

# Audio
# 18.1: audio@5.0→@6.0, service nama baru, BT audio stack baru
# Sumber: msm8916-common lineage-18.1
PRODUCT_PACKAGES += \
    audio.primary.msm8916 \
    audio.bluetooth.default \
    audio.r_submix.default \
    audio.usb.default \
    tinymix \
    libaudio-resampler \
    libqcomvisualizer \
    libqcomvoiceprocessing \
    libqcompostprocbundle \
    android.hardware.audio@6.0-impl \
    android.hardware.audio.service \
    android.hardware.audio.effect@6.0-impl \
    android.hardware.bluetooth.audio@2.0-impl

# Bluetooth: pustaka antarmuka HIDL untuk blob QTI.
#
# Tanpa baris ini vendor.bluetooth-1-0-qti CRASH-LOOP tiap 5 detik. Diverifikasi
# di perangkat lewat adb (15 Agustus 2026):
#
#   init.svc.vendor.bluetooth-1-0-qti = restarting
#   linker: CANNOT LINK EXECUTABLE
#           "/vendor/bin/hw/android.hardware.bluetooth@1.0-service-qti":
#           library "android.hardware.bluetooth@1.0.so" not found
#
# Servisnya blob prebuilt (vendor/oppo/A37/proprietary/vendor/bin/hw/), jadi soong
# tidak tahu ketergantungannya dan tidak pernah memasang pustakanya. readelf pada
# blob itu mengonfirmasi DT_NEEDED android.hardware.bluetooth@1.0.so.
#
# HARUS varian `.vendor`, bukan `android.hardware.bluetooth@1.0` biasa: konsumennya
# biner di /vendor sehingga memakai namespace linker vendor. Diperiksa di
# module-info.json — hanya varian .vendor yang memasang ke
# system/vendor/lib/android.hardware.bluetooth@1.0.so; varian polos hanya
# menghasilkan pustaka HOST, dan varian .product memasang ke /system/product/lib.
#
# Tidak perlu menambal hardware/interfaces meski blok hidl_interface di
# bluetooth/1.0/Android.bp tidak punya vendor_available (dicabut sejak a1169dd600,
# 2017) — varian .vendor tetap tersedia lewat mekanisme VNDK.
PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.0.vendor

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml

# Audio
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/acdbdata/15399/Handset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Handset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/Hdmi_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Hdmi_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/Headset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Headset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/Speaker_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Speaker_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/WorkspaceFile.qwsp:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/WorkspaceFile.qwsp \
    $(LOCAL_PATH)/audio/acdbdata/15399/Bluetooth_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Bluetooth_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/General_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/General_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/15399/Global_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/15399/Global_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_General_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_General_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Global_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Global_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Handset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Handset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Hdmi_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Hdmi_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Headset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Headset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Speaker_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Speaker_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/MTP_Bluetooth_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/MTP_Bluetooth_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Handset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Handset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Hdmi_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Hdmi_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Headset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Headset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Speaker_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Speaker_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Bluetooth_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Bluetooth_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_General_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_General_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Global_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/MTP/msm8939-tapan-snd-card/MTP_WCD9306_Global_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Headset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Headset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Speaker_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Speaker_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Bluetooth_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Bluetooth_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_General_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_General_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Global_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Global_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Handset_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Handset_cal.acdb \
    $(LOCAL_PATH)/audio/acdbdata/QRD/QRD_Hdmi_cal.acdb:$(TARGET_COPY_OUT_SYSTEM)/etc/acdbdata/QRD/QRD_Hdmi_cal.acdb \
    $(LOCAL_PATH)/audio/audio_platform_info.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_platform_info.xml \
    $(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_VENDOR)/etc/mixer_paths.xml \
    $(LOCAL_PATH)/audio/mixer_paths_mtp.xml:$(TARGET_COPY_OUT_VENDOR)/etc/mixer_paths_mtp.xml \
    $(LOCAL_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/a2dp_in_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_in_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/a2dp_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.audio.low_latency.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.low_latency.xml \
    frameworks/native/data/etc/android.software.sip.voip.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.sip.voip.xml \
    frameworks/native/data/etc/android.hardware.telephony.ims.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.ims.xml


# Properties
PRODUCT_PROPERTY_OVERRIDES += \
    ro.vendor.audio.sdk.fluencetype=none \
    persist.vendor.audio.fluence.voicecall=true \
    persist.vendor.audio.fluence.voicerec=true \
    persist.vendor.audio.fluence.speaker=false \
    vendor.audio.offload_wakelock=false \
    persist.debug.wfd.enable=1 \
    persist.sys.wfd.virtual=1

# Properties
PRODUCT_PROPERTY_OVERRIDES += \
    audio.deep_buffer.media=true \
    audio.offload.min.duration.secs=30 \
    audio.offload.video=true \
    ro.af.client_heap_size_kbyte=7168 \
    ro.audio.flinger_standbytime_ms=300 \
    vendor.voice.path.for.pcm.voip=true \
    vendor.audio.av.streaming.offload.enable=true \
    vendor.audio.offload.buffer.size.kb=64 \
    ro.config.vc_call_vol_steps=7 \
    ro.config.media_vol_steps=25 \
    vendor.audio.offload.gapless.enabled=true

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.midi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.midi.xml

# Bluetooth
#
# libbt-vendor kini berada di dalam soong namespace sendiri. Commit
# "bt: Convert libbt-vendor to blueprint" (hardware/qcom-caf/bt) menaruh
# `soong_namespace {}` di libbt-vendor/Android.bp, jadi namanya adalah
# hardware/qcom-caf/bt/libbt-vendor dan modulnya TIDAK TERLIHAT sampai
# namespace itu diimpor.
#
# Yang mendaftarkannya bukan hardware/qcom-caf/common: BoardConfigQcom.mk di
# sana hanya menambahkan bootctrl, display-commonsys, dan data-ipa-cfg-mgr --
# diperiksa di versi ULH maupun versi LineageOS resmi lineage-22.2. Jadi ini
# memang tugas device tree.
#
# Tanpa baris ini build gagal di fase Make dengan
#   "device/oppo/A37/lineage_A37.mk includes non-existent modules in
#    PRODUCT_PACKAGES: libbt-vendor"
# padahal modulnya ada di hardware/qcom-caf/bt/libbt-vendor/Android.bp:10.
PRODUCT_SOONG_NAMESPACES += \
    hardware/qcom-caf/bt/libbt-vendor

PRODUCT_PACKAGES += \
    libbt-vendor \

# Salinan libbase-v28.so DIBUANG di LOS 21.
#
# Snapshot VNDK v28 tidak ada lagi di tree (prebuilts/vndk/v28 hilang), jadi
# PRODUCT_COPY_FILES ini akan menggagalkan build. Membuangnya aman —
# diverifikasi dua arah, bukan diasumsikan:
#
#   [ -d prebuilts/vndk/v28 ]                        TIDAK ADA
#   readelf -d atas 284 berkas .so di vendor/oppo    0 DT_NEEDED libbase-v28
#
# ⚠️ Angka di atas hasil PENGUKURAN ULANG 10 Agustus 2026. Pemeriksaan pertama
# memakai `llvm-readelf`, yang TIDAK ADA di mesin build ini — perintahnya gagal,
# `grep` menghitung nol baris dari pesan error, dan hasilnya tak bisa dibedakan
# dari "nol pemakai" yang sah. Kesimpulannya kebetulan benar, metodenya tidak.
#
# Mesin ini punya readelf/nm GNU, bukan varian LLVM. Setiap pemeriksaan simbol
# atau DT_NEEDED WAJIB disertai uji kontrol yang membuktikan tool-nya membaca
# sesuatu, misalnya:
#   readelf -d <satu berkas> | grep -c NEEDED     -> harus > 0
#
# Kalau nanti ada blob yang mencarinya saat runtime, gejalanya dlopen gagal —
# bukan build gagal. Nol pemakai di atas yang menutup kemungkinan itu.

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml

# Camera
#
# @2.4-service (binderized) SENGAJA TIDAK dipasang; yang dipakai hanya
# @2.4-impl lewat jalur passthrough, sesuai deklarasi passthrough di
# manifest.xml.
#
# Memasang keduanya sekaligus adalah sumber restart loop 5 detik: service
# binderized memanggil registerAsService(), yang ditolak kalau transport
# menurut manifest bukan HWBINDER (ServiceManagement.cpp:838-847), lalu
# service-nya keluar dan di-restart init selamanya.
#
# Percobaan memperbaikinya dengan mengubah transport jadi hwbinder (build
# 20260803_161352) membuat HAL kamera pindah ke prosesnya sendiri, dan
# hasilnya layar hitam di homescreen. Jadi jalur passthrough — yang terbukti
# jalan di build 20260803_140427 — dipertahankan, dan loop-nya dihentikan
# dengan tidak memasang service binderized-nya sama sekali.
#
# 27 Agu 2026: DIPINDAH KE PROVIDER AIDL atas keputusan pemilik perangkat,
# setelah peringatan di atas ditimbang. Rinciannya di PLAN-LOS23.md bagian 12.
#
# Yang MENURUNKAN risikonya dibanding percobaan 20260803: a6010 menjalankan
# kombinasi yang sama persis -- hal3on1 + provider AIDL LineageOS -- di msm8916
# dan berhasil. Jadi bukan lompatan ke wilayah yang belum pernah dijajaki.
#
# Rantai HAL TIDAK berubah sama sekali. CameraProvider.cpp:190-197 memuat modul
# lewat hw_get_module(CAMERA_HARDWARE_MODULE_ID) yang sama, jadi hal3on1 ->
# CameraWrapper -> blob tetap apa adanya. Adapter melaporkan
# CAMERA_DEVICE_API_VERSION_3_3 (HAL3on1-adapter.cpp:113) dan provider AIDL
# menerima 3_3 secara eksplisit (CameraProvider.cpp:277).
#
# Yang BERUBAH adalah model prosesnya: dari HAL di dalam cameraserver menjadi
# /vendor/bin/hw/android.hardware.camera.provider-service.lineage yang terpisah.
# Itu persis perubahan yang dulu menghasilkan layar hitam. Kalau terulang,
# tangkap log cameraserver + vendor.camera.provider saat gagal -- itu jawaban
# yang tidak pernah didapat pada 20260803.
#
# BUILD 64-BIT: varian _32 yang dipakai. Sejak TARGET_ARCH := arm64, A37 persis
# menjadi kasus yang dimaksud -- platform 64-bit berblob kamera 32-bit, sama
# seperti Mi-Thorium. Definisinya ada di
# hardware/lineage/interfaces/camera/aidl/provider/Android.bp:38, dengan
# compile_multilib: "32" dan init_rc-nya sendiri.
#
# Kalau kembali ke build 32-bit, kembalikan ke varian tanpa _32.
#
# CARA MENGEMBALIKAN kalau gagal: kembalikan paket ini ke
# android.hardware.camera.provider@2.4-impl DAN kembalikan blok HIDL
# android.hardware.camera.provider di manifest.xml (lihat riwayat git).
PRODUCT_PACKAGES += \
    android.hardware.camera.provider-service_32.lineage \
    camera.device@1.0-impl \
    libshim_camera \
    libshim_camera_sensor \
    libcamera_shim \
    camera.msm8916 \
    camera.legacy.msm8916 \
    Aperture
# APLIKASI KAMERA: Aperture di 20 (Camera2 di 19.1, Snap di 18.1).
#
# LOS 20 menggantikan Camera2 dengan Aperture sebagai aplikasi kamera bawaan;
# meghs A37 lineage-20 dan a6010 lineage-20.0 sama-sama memakai Aperture.
# Modulnya ada di tree: packages/apps/Aperture/app/Android.bp:11.


# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml

# Properties
#
# persist.camera.disable.anight mematikan jalur multi-frame cahaya rendah milik
# blob OPPO. Tanpa itu, MEMOTRET dengan kamera DEPAN menjatuhkan cameraserver:
#
#   F libc: Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x190
#           in tid ... (binder), pid ... (cameraserver)
#   Cause: null pointer dereference
#     #00 pc 002ac580  /vendor/lib/hw/camera.vendor.msm8916.so
#                      (VDSuperPhoto_AddFrame+0)
#     #01 pc 00001cee  [anon:.bss]
#   D CXCP: CameraId-1: onError 5 -> ERROR_CAMERA_SERVICE
#
# Crash-nya DI DALAM blob, di offset +0 fungsi itu, membaca 0x190 dari pointer
# null -- konteks SuperPhoto tidak pernah diinisialisasi padahal AddFrame
# dipanggil. Blob memang menyediakan VDInitializeSuperPhoto/VDInitializeLowLight,
# jadi jalur ini bagian dari fitur "auto night" bawaan OPPO.
#
# Kamera DEPAN yang kena karena ruangan gelap membuat jalur cahaya rendah aktif;
# kamera belakang pada pencahayaan normal tidak pernah melewatinya.
#
# Terverifikasi di perangkat, keduanya sesudah properti ini disetel:
#   depan   : foto tersimpan 1944x2592, cameraserver tetap running, nol SIGSEGV
#   belakang: foto tersimpan, tidak ada regresi
PRODUCT_PROPERTY_OVERRIDES += \
    persist.camera.cpp.duplication=false \
    persist.camera.disable.anight=1 \
    persist.camera.hal.debug.mask=0

# vendor_init DICABUT 2 September 2026 -- libinit_msm8916 tidak pernah tertaut
# ke init di 23.2, dan sebagai static lib entri PRODUCT_PACKAGES ini pun tidak
# memasang apa pun. Sumbernya tetap di init/ kalau suatu saat mau dihidupkan;
# caranya ada di BoardConfig.mk.

# GPS
PRODUCT_PACKAGES += \
    android.hardware.gnss@1.0-impl \
    android.hardware.gnss@1.0-service \
    gps.msm8916

# Charger images
# charger_res_images dihapus di 18.1 (Sumber: msm8916-common lineage-18.1)

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/gps/flp.conf:system/etc/flp.conf \
    $(LOCAL_PATH)/gps/gps.conf:system/etc/gps.conf \
    $(LOCAL_PATH)/gps/izat.conf:system/etc/izat.conf \
    $(LOCAL_PATH)/gps/gps_debug.conf:$(TARGET_COPY_OUT_VENDOR)/etc/gps_debug.conf \
    $(LOCAL_PATH)/gps/sap.conf:system/etc/sap.conf \
    $(LOCAL_PATH)/gps/quipc.conf:system/etc/quipc.conf

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml

# PrivApp Permissions
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/privapp-permissions-qti.xml:system/etc/permissions/privapp-permissions-qti.xml

# Overlay
# overlay-lineage/ sebelumnya tidak pernah didaftarkan, sehingga isinya mati:
#   - config_deviceHardwareKeys=83 (Home+Back+AppSwitch+Volume) tidak pernah
#     terpasang, jadi menu Settings > Buttons tidak cocok dengan tombol fisik.
#   - config_deviceHardwareWakeKeys=64, config_trustLegacyEncryption=true dan
#     config_buttonBrightnessSettingDefault=0 juga ikut terabaikan.
# Nilai 83 cocok dengan keylayout/ft5x06_ts.kl (HOME, BACK, APP_SWITCH) plus
# gpio-keys.kl (VOLUME_UP/DOWN), jadi overlay ini memang milik device ini.
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay \
    $(LOCAL_PATH)/overlay-lineage

# Properties
PRODUCT_PROPERTY_OVERRIDES += \
    vendor.qcom.bluetooth.soc=smd \
    ro.bluetooth.dun=true \
    ro.bluetooth.hfp.ver=1.7 \
    ro.bluetooth.sap=true \
    ro.qualcomm.bt.hci_transport=smd

# Android 13 (T) gating profil Bluetooth via sysprop (BluetoothProperties
# libsysprop, orElse(false)): tanpa ini hanya GattService yang jalan — OPP/
# A2DP/HFP dsb. tak pernah start (ditemukan via M5 uji BT 7 Agu 2026).
# Set diverifikasi runtime di device: 11 profil services langsung aktif.
PRODUCT_PROPERTY_OVERRIDES += \
    bluetooth.profile.a2dp.source.enabled=true \
    bluetooth.profile.avrcp.target.enabled=true \
    bluetooth.profile.bas.client.enabled=true \
    bluetooth.profile.gatt.enabled=true \
    bluetooth.profile.hfp.ag.enabled=true \
    bluetooth.profile.hid.host.enabled=true \
    bluetooth.profile.map.server.enabled=true \
    bluetooth.profile.opp.enabled=true \
    bluetooth.profile.pan.nap.enabled=true \
    bluetooth.profile.pan.panu.enabled=true \
    bluetooth.profile.pbap.server.enabled=true \
    bluetooth.profile.sap.server.enabled=true

# Keymaster HAL
PRODUCT_PACKAGES += \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service

# Keystore
# keystore.msm8916 dihapus di 18.1 (Sumber: msm8916-common lineage-18.1)

# Network stack — 18.1: varian in-process (tanpa APEX)
# Sumber: msm8916-common lineage-18.1
#
# ⚠️ DIUBAH 17 Agustus 2026: InProcessNetworkStack -> NetworkStack.
#
# Akar hotspot/tethering mati DAN menu USB hang 60 detik, terukur di perangkat:
#
#   Permission [android.permission.MAINLINE_NETWORK_STACK]
#     sourcePackage = com.android.networkstack.inprocess
#     uid = 1000                 <- platform
#     prot = signature           <- HANYA untuk paket bersertifikat SAMA
#
# InProcessNetworkStack bersertifikat "platform" (Android.bp:451) dan
# mendefinisikan izin itu, sementara TetheringNext di APEX bersertifikat
# "networkstack" (sidik jari e708811f vs b4addb29). Sertifikat beda ->
# izin tidak pernah diberikan -> ConnectivityModuleConnector gagal di
# checkModuleServicePermission -> SystemServer tidak pernah menjalankan
# ServiceManager.addService("tethering") (SystemServer.java:3357-3364).
#
# Akibatnya "service check tethering" -> not found, TetheringManager
# menjalankan startPollingForConnector() yang polling selamanya, dan
# TetheringManager.isTetheringSupported() dari UsbBackend memblokir main
# thread Settings sampai 60 detik lalu melempar Callback timeout.
#
# NetworkStack (Android.bp:496) bersertifikat "networkstack" dan memakai
# AndroidManifest.xml yang mendefinisikan izin yang sama, sehingga sertifikat
# pendefinisi dan pemakainya cocok.
#
# Ongkosnya: network stack berjalan di prosesnya sendiri, bukan di dalam
# system_server. Beberapa puluh MB RAM pada perangkat 2 GB -- ditukar dengan
# hotspot, tethering, dan menu USB yang berfungsi.
#
# --- catatan lama, sebagian sudah tidak berlaku ---
# InProcessTethering WAJIB berpasangan dengan InProcessNetworkStack.
# Tanpa TetheringService, TetheringManager.isTetheringSupported() menunggu
# ConditionVariable yang tidak pernah di-signal, dan itu membekukan MAIN THREAD
# Settings saat homepage resume:
#
#   TetheringManager$RequestDispatcher.waitForResult(TetheringManager.java:406)
#   TetheringManager.isTetheringSupported(TetheringManager.java:1321)
#   settingslib.TetherUtil.isTetherAvailable(TetherUtil.java:32)
#   TetherPreferenceController.isAvailable(TetherPreferenceController.java:115)
#   TopLevelNetworkEntryPreferenceController.getSummary(...:74)
#   DashboardFragment.updatePreferenceStates -> onResume
#
# Gejalanya di device: Settings tampil putih polos tanpa toolbar (yang terlihat
# cuma Splash Screen window), tombol Back mati, dan "dumpsys activity" untuk
# proses itu balas "java.io.IOException: Timeout". Sub-halaman seperti
# DISPLAY_SETTINGS tetap normal karena tidak memanggil TetherUtil.
#
# Kenapa HARUS nama apex, bukan nama app-nya:
# com.android.tethering.inprocess adalah override_apex dengan
# base: "com.android.tethering" dan apps: ["InProcessTethering"]
# (frameworks/base/packages/Tethering/apex/Android.bp:40-47). Menambahkannya
# MENGGANTI isi apex dari Tethering (bersertifikat networkstack) menjadi
# InProcessTethering (bersertifikat platform). Menambahkan modul
# "InProcessTethering" saja tidak menggantikan apa pun — apex bawaan tetap
# terpasang dan tidak ada yang berubah.
#
# Sertifikat itulah inti masalahnya. MAINLINE_NETWORK_STACK berproteksi
# signature dan didefinisikan PlatformNetworkPermissionConfig (bersertifikat
# platform), sehingga Tethering.apk bersertifikat networkstack tidak bisa
# memperolehnya:
#   E SystemServer: BOOT FAILURE starting Tethering
#   java.lang.SecurityException: Networking module does not have permission
#     android.permission.MAINLINE_NETWORK_STACK
#     at ConnectivityModuleConnector.checkModuleServicePermission(...:291)
# Layanan tethering gagal start, lalu semua pemanggilan TetheringManager
# menggantung sampai timeout.
#
# Pasangan kanoniknya terlihat di build/make/target/product/go_defaults_common.mk:40-43
# (InProcessNetworkStack + com.android.tethering.inprocess). msm8916-common
# mendapatkannya otomatis lewat common_full_go_phone.mk; device ini memakai
# common_full_phone.mk sehingga harus dideklarasikan eksplisit.
#
# ⚠️ LOS 22 (Android 15): com.android.tethering.inprocess SUDAH TIDAK ADA.
#
# Diperiksa di pohon lineage-22.2 ter-sync (15 Agustus 2026):
#   - nol `override_apex` dan nol `InProcessTethering` di seluruh pohon
#   - build/make/target/product/go_defaults_common.mk TIDAK lagi menyebutnya,
#     padahal itulah pasangan kanonik yang dikutip analisis LOS 21 di atas
#   - InProcessNetworkStack MASIH ADA (packages/modules/NetworkStack/Android.bp:444)
#
# Jadi mekanisme perbaikannya dicabut hulu, bukan sekadar berpindah nama.
# Entrinya dibuang karena build gagal tanpa itu; InProcessNetworkStack
# dipertahankan karena modulnya masih ada dan tetap relevan.
#
# BELUM DIKETAHUI apakah gejala LOS 21 kembali: Tethering.apk bersertifikat
# networkstack tidak memperoleh MAINLINE_NETWORK_STACK, layanan tethering
# gagal start, lalu Settings tampil putih polos. Android 15 mungkin sudah
# menanganinya lewat jalur lain, mungkin juga tidak.
#
# YANG HARUS DIPERIKSA DI FASE 5, sebelum menyimpulkan apa pun:
#   logcat -s SystemServer | grep -i tethering
#   adb shell dumpsys activity | grep -i tether
#   cari "Networking module does not have permission"
# Kalau gejalanya muncul lagi, jalur penggantinya harus dicari dari awal --
# jangan mengembalikan baris ini, modulnya benar-benar tidak ada.
PRODUCT_PACKAGES += \
    NetworkStack

# FM DICABUT 31 Agustus 2026. Sebelumnya:
#
#     PRODUCT_PACKAGES += FMRadio libfmjni
#
# packages/apps/FMRadio adalah varian MEDIATEK. Ia meng-hardcode /dev/fm --
# jni/fmr/fm.h:78 dan jni/fmr/fmr.h:66 -- sedangkan perangkat ini Qualcomm dan
# memakai /dev/radio0 lewat V4L2. Aplikasinya TIDAK AKAN PERNAH bisa bekerja
# di sini, berapa kali pun sisi kernel diperbaiki. Terlihat di log perangkat:
#
#     E FMLIB_COM:  Open /dev/fm failed, No such file or directory
#     E FMLIB_CORE: FMR_open_dev failed, [fd=-1]
#
# Varian Qualcomm-nya sudah tidak ada di hulu: LineageOS/android_hardware_qcom_fm
# branch terakhirnya lineage-17.0, terakhir di-push 2022, nol branch untuk 18 ke
# atas. Dukungan FM Qualcomm dibuang LineageOS setelah Android 10.
#
# acroreiser sampai pada kesimpulan yang sama di perangkat msm8916 mereka.
# Riwayat device tree a6010:
#     81ab0bb0  FM: Switch implementations
#     3460807c  a6010: import RevampedFMRadio   <- impor app FM Qualcomm, ~3.800
#                                                  baris JNI, ke device tree sendiri
#     c1dfeec5  a6010: remove RevampedFMRadio   <- dibuang, 29 Desember 2024
# device.mk lineage-23.2 mereka kini nol sebutan FM.
#
# YANG TETAP DIPERTAHANKAN, sama seperti acroreiser:
#   CONFIG_RADIO_IRIS=y di defconfig kernel (commit 58a1664897ff) -- /dev/radio0
#     terbentuk dan drivernya terdaftar sebagai "radio-iris", terverifikasi di
#     perangkat. Ongkosnya 36 KB, dan ia prasyarat untuk solusi FM apa pun nanti.
#   BOARD_HAVE_QCOM_FM := true di BoardConfig.mk:572 -- dibaca
#     build/make/core/android_soong_config_vars.mk:421 dan diteruskan ke
#     namespace soong qcom_bluetooth, bukan ke aplikasi FM.
#
# Yang dicabut hanya APLIKASINYA, supaya ROM tidak memaketkan sesuatu yang
# pasti gagal saat dibuka.

# Google Assistant
PRODUCT_PROPERTY_OVERRIDES += \
    ro.opa.eligible_device=true

# Init scripts
PRODUCT_PACKAGES += \
    bootwatchdog.sh \
    fstab.qcom \
    init.target.rc \
    init.qcom.rc \
    init.qcom.power.rc \
    init.qcom.ssr.rc \
    init.qcom.usb.rc \
    init.recovery.qcom.rc \
    ueventd.qcom.rc

# For config.fs
PRODUCT_PACKAGES += \
    fs_config_files

# Encryption
# LOS 20: cryptfshw DICABUT — KOREKSI terhadap keputusan 19.1 "pertahankan
# cryptfshw". Di 19.1 modul ini dibangun dari hardware/lineage/interfaces/
# cryptfshw + vendor/qcom/opensource/interfaces/cryptfshw (terverifikasi dari
# log build bacon4.log); KEDUANYA sudah tidak ada di tree LOS 20 (grep seluruh
# tree: nol definisi). Mempertahankan baris di bawah menghentikan kati persis
# seperti dummy android.hidl.base@1.0. Yang menentukan /data terenkripsi atau
# tidak adalah `encryptable=` di fstab (§3.7), bukan ada-tidaknya HAL — fstab
# tanpa encryptable= sudah cukup. BoardConfig tetap menyetel
# TARGET_HW_DISK_ENCRYPTION := true (tidak dikonsumsi apa pun di LOS 20;
# retiredtab juga mempertahankannya).

# Media
PRODUCT_COPY_FILES += \
    frameworks/av/media/libstagefright/data/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_telephony.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_telephony.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video.xml

# Media
# CATATAN duplicate rule libmm-omxcore (lihat BUILD_BROKEN_DUP_RULES di
# BoardConfig.mk): modul ini juga disalin sebagai prebuilt oleh
# vendor/oppo/A37/A37-vendor.mk ke path output yang PERSIS SAMA. Yang menang
# adalah aturan PRODUCT_COPY_FILES alias blob — diverifikasi dari perintah
# ninja-nya: "cp vendor/oppo/A37/proprietary/vendor/lib/libmm-omxcore.so".
# Menghapus baris di bawah TIDAK menyelesaikan duplikat: libmm-omxcore tetap
# ter-install karena jadi dependensi modul libOmx* lain yang dibangun dari
# source (sudah diuji). Satu-satunya cara menghilangkan duplikat adalah
# membuang salinan prebuilt di A37-vendor.mk, dan itu MENGGANTI biner yang
# terpasang (blob -> hasil build source). Belum dilakukan karena kombinasi
# blob + libOmx* source itulah yang terbukti boot di 17.1.
PRODUCT_PACKAGES += \
    libmm-omxcore \
    libOmxAacEnc \
    libOmxAmrEnc \
    libOmxCore \
    libOmxEvrcEnc \
    libOmxQcelp13Enc \
    libOmxVdec \
    libOmxVenc \
    libOmxVidcCommon \
    libstagefrighthw

# Media config
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml

# Media
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/media_profiles_V1_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.telephony.cdma.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.cdma.xml \
    frameworks/native/data/etc/android.software.sip.voip.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.sip.voip.xml

# Power
# CATATAN: referensi msm8916-common 18.1 pakai AIDL power-service-qti.
# Sementara tetap power@1.0 HIDL (sudah proven di 17.1 dengan powerHint +
# setInteractive custom). Upgrade ke AIDL bisa menyusul setelah boot stabil.
PRODUCT_PACKAGES += \
    power.msm8916

PRODUCT_PACKAGES += \
    android.hardware.power@1.0-impl \
    android.hardware.power@1.0-service

# Thermal HAL
#
# Sebelum ini perangkat TIDAK punya HAL thermal sama sekali, sehingga seluruh
# API termal framework mati: PowerManager.getCurrentThermalStatus(), listener
# status termal, dan thermal headroom. Aplikasi tidak bisa tahu perangkat
# sedang panas dan menyesuaikan diri.
#
# Perlu ditegaskan supaya tidak salah paham: HAL ini TIDAK menambah proteksi
# panas. Mitigasi tetap sepenuhnya di kernel (msm_thermal), dan itu memang
# sudah bekerja -- diukur dengan beban penuh 4 core selama 100 detik, suhu
# naik 39->60 derajat C dan frekuensi tidak pernah diturunkan. Yang ditambah
# HAL ini murni PELAPORAN status ke framework.
#
# Diambil dari device tree a6010 (hidl/thermal + configs), yang memakai SoC
# yang sama persis. Kedelapan sensor yang dirujuk confignya ada semua di A37
# dan sudah dicocokkan satu per satu di perangkat:
#
#   tsens_tz_sensor0/1/4/5  CPU   thermal_zone0/1/3/4   multiplier 1
#   tsens_tz_sensor2        GPU   thermal_zone2         multiplier 1
#   battery                 BAT   thermal_zone6         multiplier 0.001
#   bms                     SKIN  thermal_zone7         multiplier 0.001
#   pm8916_tz               USB   thermal_zone5         multiplier 0.001
#
# Multiplier berbeda karena satuannya memang berbeda: tsens melaporkan derajat
# C bulat, sedangkan battery/bms/pm8916_tz melaporkan milli-derajat.
#
# Ambang HotThreshold CPU mulai 65 derajat, di atas qcom,limit-temp = 60 milik
# kernel. Itu disengaja dan tidak berbahaya: kernel sudah membatasi lebih dulu,
# status framework sifatnya informatif.
PRODUCT_PACKAGES += \
    android.hardware.thermal@2.0-service.msm8916

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/thermal_info_config.json:$(TARGET_COPY_OUT_VENDOR)/etc/thermal_info_config.json \
    $(LOCAL_PATH)/configs/thermal-engine.conf:$(TARGET_COPY_OUT_VENDOR)/etc/thermal-engine.conf

PRODUCT_PROPERTY_OVERRIDES += \
    vendor.thermal.config=thermal_info_config.json

# Gatekeeper — baru di 18.1, wajib (Sumber: msm8916-common lineage-18.1)
PRODUCT_PACKAGES += \
    android.hardware.gatekeeper@1.0-service.software

PRODUCT_PROPERTY_OVERRIDES += \
    ro.config.max_starting_bg=8

# Perf
PRODUCT_PROPERTY_OVERRIDES += \
    ro.vendor.extension_library=libqti-perfd-client.so

# IOP
PRODUCT_PROPERTY_OVERRIDES += \
    vendor.iop.enable_uxe=0 \
    vendor.iop.enable_prefetch_ofr=0

# IRSC
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/sec_config:$(TARGET_COPY_OUT_VENDOR)/etc/sec_config

# First api level, device has been commercially launched.
#
# Dinaikkan 19 -> 21 di 19.1. A37f dirilis dengan Android 5.1.1 — terbaca di
# fingerprint stok yang dipakai ROM referensi:
# OPPO/A37fw/A37f:5.1.1/LMY47V/1519717163. Nilai 19 (KitKat) yang diwarisi dari
# 18.1 memang keliru secara fakta.
#
# ⚠️ Perubahan ini INERT secara fungsi, jangan dikira memperbaiki sesuatu:
# seluruh gerbang first_api_level / PRODUCT_SHIPPING_API_LEVEL di tree 19.1 ada
# di ambang 26, 27, 28, 30, dan 31 (build/make/core/config.mk:628,683,708;
# system/core/init/ueventd.cpp:272) — tidak ada satu pun di antara 19 dan 21.
# Diubah demi kebenaran fakta dan paritas dengan ROM referensi, bukan efek.
#
# Baris ini sendiri akan dibuang post_process_props.py ("disallowed key") persis
# seperti di ROM referensi; nilai efektifnya datang dari PRODUCT_SHIPPING_API_LEVEL
# di lineage_A37.mk.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.product.first_api_level=21

# Gerbang W1/W2 (repopick 320591 system/bpf + 320592 system/netd).
# Kernel 3.10 tidak punya syscall bpf, dan A12 membuang gerbang versi kernel yang
# masih ada di A11. Kedua patch membaca properti ini dan default-nya `true`, jadi
# TANPA baris ini keduanya tidak berpengaruh apa pun dan bpfloader tetap
# menggagalkan boot. Terverifikasi di source hasil patch:
# system/bpf/bpfloader/BpfLoader.cpp:115 dan system/netd/server/Controllers.cpp:280.
# ROM referensi 19.1 A37 menyetelnya sama.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.kernel.ebpf.supported=false

# ⚠️⚠️ ro.vndk.version DIBUANG — INI PENYEBAB BOOT STUCK DI LOGO OPPO. ⚠️⚠️
#
# Sebelumnya disetel `current`, disalin dari ROM 19.1 kita dan ROM gt58wifi yang
# boot. Alasan itu benar untuk Android 12, TAPI DI ANDROID 14 MEMATIKAN.
#
# Rantai sebabnya, dibuktikan dari ramoops perangkat (report/1/):
#
#   1. ro.vndk.version=current disetel
#   2. linkerconfig mencari /apex/com.android.vndk.vcurrent
#      (generator/variableloader.cc:80 — path dibentuk dari nilai properti)
#   3. ROM ini punya NOL apex VNDK, jadi access() gagal:
#         "Unable to access VNDK APEX at path: /apex/com.android.vndk.vcurrent"
#      dan variableloader.cc:84 RETURN DINI — SANITIZER_DEFAULT_VENDOR,
#      VNDK_CORE_LIBRARIES_VENDOR, dan kawan-kawan tidak pernah didefinisikan.
#   4. Tapi penjaga pemakaiannya memakai has_value(), bukan isi APEX-nya:
#         modules/environment.cc:46
#           IsVendorVndkVersionDefined() = GetValue("ro.vndk.version").has_value()
#         contents/namespace/vendordefault.cc:55-57
#           if (IsVendorVndkVersionDefined())
#               .AddSharedLib(Var("SANITIZER_DEFAULT_VENDOR"));
#      Properti DISETEL, jadi penjaga LOLOS dan Var() dipanggil.
#   5. contents/context/context.cc:101
#         CHECK(!"undefined var") << name << " is not defined";
#      -> SIGABRT. Tombstone di pmsg-ramoops-0 mengonfirmasi:
#         signal 6 (SIGABRT), #05 BuildApexDefaultSection, #08 main
#   6. /linkerconfig/ld.config.txt TIDAK PERNAH dibuat
#   7. Setiap biner dinamis gagal exec:
#         init: cannot execv('/apex/com.android.sdkext/bin/derive_sdk'): ENOENT
#         init: cannot execv('/apex/com.android.sdkext/bin/derive_classpath'): ENOENT
#         art_boot exit 127 -> odsign exit 1, crash-loop tiap 5 detik
#   8. zygote tidak pernah start -> stuck di logo OPPO selamanya
#
# DENGAN PROPERTI DIBUANG, has_value() = false, seluruh blok VNDK dilewati, dan
# linkerconfig selesai normal. Itu persis yang komentar lama ini sendiri ramalkan
# ("kosong = namespace VNDK tidak dibangun") — nilainya saja yang salah dipilih.
#
# JANGAN menyetelnya kembali ke nilai apa pun kecuali ROM benar-benar mengirim
# /apex/com.android.vndk.v<nilai>. Menyetel angka versi tanpa APEX-nya
# menghasilkan crash yang sama persis.
#
# Bukan BOARD_VNDK_VERSION: itu ikut membangun vndk_package yang tidak dipakai
# non-treble 32-bit ini.

# Mode low-RAM. Perangkat 2 GB; ROM referensi 19.1 A37 yang terbukti boot
# menyetel ro.config.low_ram=true di build.prop.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.config.low_ram=true

# lmkd: kernel 3.10 tidak punya PSI (baru ada di 4.20+). Tanpa ini lmkd mencoba
# PSI dulu di init_monitors() (lmkd.cpp:3754) lalu baru jatuh ke vmpressure;
# menyetelnya eksplisit memangkas percobaan yang pasti gagal.
#
# PSI SEKARANG TERSEDIA -- 31 Agustus 2026, kernel branch `psi`
# (rigaz29/kernel_oppo_msm8939, commit 367e1f5c7d07). Backport PSI tanpa
# dukungan cgroup; /proc/pressure/{cpu,memory,io} tingkat sistem, yang memang
# satu-satunya yang dibaca lmkd.
#
# Peralihannya diverifikasi dari deskriptor berkas lmkd, bukan dari properti:
#
#                                       sebelum   sesudah
#   /dev/memcg/memory.pressure_level       3         0
#   /proc/pressure/memory                  0         2
#
# lmkd melepas jalur vmpressure sepenuhnya dan memasang dua trigger PSI.
# Thread [psimon] berjalan, dan tekanan memori bergerak dari nol ke
# total=2.830.372 di bawah beban nyata.
#
# ro.lmk.use_new_strategy tetap TIDAK DISETEL, dan sekarang alasannya berbeda
# dari sebelumnya. Dulu properti itu tidak pernah dievaluasi karena jalur PSI
# tidak pernah dimasuki. Sekarang ia dievaluasi, dan defaultnya sudah tepat:
# low_ram_device || !use_minfree_levels, dengan ro.config.low_ram=true di atas
# sehingga bernilai true. Menyetelnya eksplisit hanya menambah tuas yang bisa
# salah dipahami.
#
# ro.lmk.use_minfree_levels juga dibiarkan pada default (false).
#
# CATATAN TENTANG TAMBALAN YANG MASIH WAJIB. Beralih ke PSI hanya mengganti
# SUMBER SINYAL, bukan cara lmkd menghitung. update_zoneinfo_watermarks()
# (lmkd.cpp:2745) tetap memanggil zoneinfo_parse() dari jalur PSI, dan lmkd
# tetap memegang fd ke /proc/zoneinfo. Kernel 3.10 tidak punya bagian
# "per-node stats" (fitur Linux 4.8), jadi tambalan
# patches/system_memory_lmkd/0814-* MASIH DIBUTUHKAN. Tanpanya lmkd kembali
# gagal parse -- kali ini di jalur PSI.
#
# Pembanding jalur lama, untuk kalau suatu saat perlu dibandingkan: di bawah
# tekanan nyata jalur vmpressure membunuh 4-5 proses berurutan menurut
# oom_score_adj (975, 985, 995) tanpa menyentuh aplikasi foreground, dan kernel
# OOM killer tidak pernah ikut campur. Apakah PSI memutuskan LEBIH BAIK belum
# diukur -- yang terbukti baru bahwa ia memakai sinyal yang lebih akurat.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lmk.use_psi=true

# Properti baru 18.1 (Sumber: msm8916-common lineage-18.1 + a6000 ref)
PRODUCT_PROPERTY_OVERRIDES += \
    ro.charger.enable_suspend=true \
    ro.control_privapp_permissions=enforce \
    ro.oem_unlock_supported=0

# Properties
# persist.data.qmi.adb_logmask, persist.radio.apm_sim_not_pwdn dan
# ro.telephony.call_ring.multiple sudah diset di blok RIL di bawah; di sini
# tinggal yang unik saja supaya tidak ada dua sumber untuk nilai yang sama.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.radio.add_power_save=1

# HIDL
# 18.1: tambah libhidltransport/libhwbinder, VINTF override, RRO
# Sumber: msm8916-common lineage-18.1
#
# LOS 20: dummy android.hidl.base@1.0 / android.hidl.manager@1.0 (libhidl/)
# DIBUANG — LineageOS 20 menyediakannya sendiri di
# hardware/lineage/compat/Android.bp:228 dan :236, sehingga definisi milik
# kita jadi duplikat dan menghentikan kati:
#   base_rules.mk:338: MODULE.TARGET.SHARED_LIBRARIES.android.hidl.base@1.0
#   already defined by hardware/lineage/compat
#
# Varian libhidltransport.vendor / libhwbinder.vendor juga DIBUANG: bukan
# modul yang sah di LOS 20 (tertangkap pemeriksaan common.mk:104), dan di 19.1
# keduanya entri mati — hanya varian polos yang terpasang ke /system/lib
# (diverifikasi dari log build 19.1: Install .../system/lib/libhwbinder.so).
# a6010 lineage-20.0 dan common meghs lineage-20 memakai varian polos saja.
PRODUCT_PACKAGES += \
    libhidltransport \
    libhwbinder

PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE := true

# RRO (Runtime Resource Overlay) — wajib di Android 11
# Sumber: msm8916-common lineage-18.1
# CATATAN: WifiOverlay/TetheringConfigOverlay dihapus — tidak ada di
# base tree LOS 18.1 (diverifikasi dari source). Jika build gagal
# karena RRO, hapus juga PRODUCT_ENFORCE_RRO_TARGETS.
PRODUCT_ENFORCE_RRO_TARGETS := *

# Health
# 18.1: @2.0 → @2.1 (Sumber: msm8916-common lineage-18.1)
PRODUCT_PACKAGES += \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service \
    vendor.lineage.health-service.default

# Konfigurasi charging control HARUS lewat soong_config di 23.2.
#
# TARGET_HEALTH_CHARGING_CONTROL_* di BoardConfig.mk sudah TIDAK DIBACA SIAPA
# PUN -- diperiksa dengan grep ke seluruh pohon, nol kecocokan di luar device
# tree ini sendiri. Yang dibaca hanya
# hardware/lineage/interfaces/health/aidl/default/Android.bp:62 lewat
# soong_config_variable("lineage_health", ...).
#
# Akibat kalau dibiarkan kosong (terlihat di build sebelumnya:
# out/soong/soong.lineage_A37.variables -> VendorVars.lineage_health KOSONG):
#
#   - HEALTH_CHARGING_CONTROL_CHARGING_PATH tak terdefinisi, sehingga yang
#     terkompilasi adalah cabang #else di ChargingControl.cpp:73 -- loop
#     while(!mChargingEnabledNode) yang menyisir daftar node bawaan.
#   - HEALTH_CHARGING_CONTROL_SUPPORTS_BYPASS justru IKUT AKTIF, karena
#     default-nya di Android.bp:83 mendefinisikannya. Setelan `false` di
#     BoardConfig tidak berpengaruh sama sekali.
#
# Dan kalau IChargingControl tidak pernah register, main thread system_server
# menggantung di waitForDeclaredService (ChargingControlController.java:85)
# lalu Watchdog membunuhnya:
#   WATCHDOG KILLING SYSTEM PROCESS: Blocked in handler on main thread for 70s
#
# Jalur node diverifikasi di kernel kita: qpnp-linear-charger.c mengekspos
# POWER_SUPPLY_PROP_CHARGING_ENABLED, dipetakan power_supply_sysfs.c ke atribut
# "charging_enabled" pada psy bernama "battery". Node dibuat writable oleh
# chmod di init.qcom.rc (on fs).
$(call soong_config_set,lineage_health,charging_control_charging_path,/sys/class/power_supply/battery/charging_enabled)
$(call soong_config_set,lineage_health,charging_control_charging_enabled,1)
$(call soong_config_set,lineage_health,charging_control_charging_disabled,0)
$(call soong_config_set_bool,lineage_health,charging_control_supports_bypass,false)
$(call soong_config_set_bool,lineage_health,charging_control_supports_toggle,true)

# Varian vendor dari pustaka platform yang dibutuhkan blob.
#
# Blob msm8916 era 2016 menaut pustaka yang ada di /system/lib. Namespace vendor
# tidak menjangkau /system, dan hanya sebagian kecil pustaka tersedia lewat
# tautan LLNDK. Sisanya harus dipasang sebagai varian vendor di /vendor/lib --
# mekanisme resmi AOSP untuk modul ber-vendor_available.
#
# Daftar ini disusun dari pengukuran, bukan tebakan: setiap berkas di
# /system/vendor diperiksa DT_NEEDED-nya, lalu dikurangi isi
# namespace.default.link.system.shared_libs (25 pustaka LLNDK) yang terbaca di
# /linkerconfig/ld.config.txt perangkat. Sebelas pustaka tersisa; empat di
# antaranya punya varian vendor resmi dan dipasang di sini.
#
# Dua yang terbukti memblokir, terekam di perangkat:
#
#   rild: dlopen failed: library "libandroidicu.so" not found:
#         needed by /system/lib/libsqlite.so
#     -> libsqlite.vendor. Dibutuhkan libqti-iopd.so, libqti-iopd-client.so.
#
#   CANNOT LINK EXECUTABLE "/system/vendor/bin/mm-qcamera-daemon":
#     library "libstdc++.so" not found
#     -> libstdc++_vendor. Dibutuhkan 158 berkas vendor, termasuk
#        camera.vendor.msm8916.so.
#
# Pendekatan ini disalin dari acroreiser/ULH lenovo a6010 (lineage-23.2), yang
# memakai blob msm8916 yang sama dan menyelesaikannya persis begini --
# device.mk:446-481 di sana memasang libstdc++_vendor, libsqlite.vendor,
# libhwbinder.vendor, dan libnetutils.vendor. Mereka TIDAK menyentuh namespace
# linker sama sekali.
#
# CATATAN: percobaan sebelumnya menambahkan /system ke search path namespace
# vendor. Itu SALAH dan merusak lebih banyak daripada yang diperbaiki: search
# path membayangi tautan LLNDK libbinder_ndk.so, sehingga libbinder_ndk sistem
# berpasangan dengan libbinder vendor dan SEMUA HAL AIDL vendor gagal mendaftar
# (EX_TRANSACTION_FAILED). Wi-Fi, RIL, dan Bluetooth ikut mati. Sudah di-revert.
#
# Masih belum tertutup: libandroid, libandroid_runtime, libcamera_client,
# libmedia, libpowermanager, libstagefright -- keenamnya tidak punya
# vendor_available di pohon ini. a6010 juga tidak memasangnya.
# libhwbinder.vendor dan libnetutils.vendor semula dilewati karena belum
# terbukti memblokir. Setelah flash, keduanya TERBUKTI:
#
#   CANNOT LINK EXECUTABLE "/vendor/bin/hw/vendor.qti.hardware.perf@1.0-service":
#     library "libhwbinder.so" not found
#   CANNOT LINK EXECUTABLE "/system/vendor/bin/netmgrd":
#     library "libnetutils.so" not found
#
# Keduanya persis yang dipasang a6010, jadi daftarnya kini sama dengan mereka.
# Catatan lama di bagian HIDL (sekitar baris 821) menyebut libhwbinder.vendor
# pernah dibuang karena bukan modul sah di LOS 20; di 23.2 ia sah kembali --
# system/libhwbinder/Android.bp menyatakan vendor_available: true.
#
# libandroid dan libmedia tidak punya varian vendor resmi, jadi disediakan
# sendiri di libshims/: libandroid sebagai shim 13 simbol, libmedia sebagai stub
# tiga simbol AudioSystem lama. Lihat komentar di Android.mk sana.
#
# CATATAN: keterangan lama "libmedia stub kosong, blob RIL memakai NOL simbolnya"
# KELIRU dan sudah diperbaiki. Pengukuran yang menghasilkannya mengiris simbol
# UND blob dengan simbol yang MASIH ADA di libmedia sekarang -- padahal yang
# dibutuhkan blob justru simbol yang sudah DICABUT dari libmedia modern,
# sehingga tidak pernah muncul di irisan itu. Yang benar tiga:
# setParameters, getParameters, dan setErrorCallback.
#
# libgui memakai varian vendor RESMI dari AOSP (libgui_vendor,
# frameworks/native/libs/gui/Android.bp:581), bukan shim buatan sendiri --
# sama seperti acroreiser/ULH a6010 (camera/hal3on1/Android.mk:22) dan
# Mi-Thorium (libshim/Android.bp:58). Tanpa ini daemon kamera tidak pernah jalan:
#   CANNOT LINK EXECUTABLE "/system/vendor/bin/mm-qcamera-daemon":
#   library "libgui.so" not found:
#   needed by /system/vendor/lib/libmmcamera2_stats_modules.so
# dan cameraserver ikut SIGABRT di CameraModule::init().
PRODUCT_PACKAGES += \
    libsqlite.vendor \
    libstdc++_vendor \
    libstdc++_vendor_symlink \
    libhwbinder.vendor \
    libnetutils.vendor \
    libandroid_a37_vendor \
    libandroid_a37_vendor_symlink \
    libandroid_a37_vendor64 \
    libandroid_a37_vendor64_symlink \
    libmedia_a37_vendor \
    libmedia_a37_vendor_symlink \
    libmedia_a37_vendor64 \
    libmedia_a37_vendor64_symlink \
    libgui_vendor \
    libgui_vendor_symlink \
    libcamera_client_a37_vendor \
    libcamera_client_a37_vendor_symlink

# Deklarasikan memcg sebagai cgroup v1, bukan v2.
#
# profil dasar (system/core/libprocessgroup/profiles/cgroups.json) menaruh
# controller "memory" DI DALAM blok Cgroups2 pada /sys/fs/cgroup. Kernel 3.10
# tidak punya cgroup v2 sama sekali; memcg yang nyata ter-mount sebagai v1 di
# /dev/memcg (terbaca di /proc/mounts perangkat).
#
# Akibatnya lmkd salah menyimpulkan versi hierarki. statslog.cpp:39-49
# membandingkan dua jalur:
#     CgroupGetControllerPath("memory")  -> /sys/fs/cgroup
#     CgroupGetControllerPath(cgroup2)   -> /sys/fs/cgroup
# keduanya sama, jadi memcg_version() mengembalikan kV2, dan lmkd.cpp:3619
# menolak jalan lalu KELUAR:
#
#   lowmemorykiller: init_mp_common: global monitoring is only available for
#                    the v1 cgroup hierarchy
#   lowmemorykiller: Kernel does not support memory pressure events or
#                    in-kernel low memory killer
#   lowmemorykiller: exiting
#
# init menghidupkannya lagi, keluar lagi -- init.svc.lmkd = restarting selamanya,
# /dev/socket/lmkd tidak pernah ada. Setiap updateOomAdj di ActivityManager lalu
# menunggu lmkd sambil MEMEGANG kunci AMS, menghasilkan stall ~3 detik berulang:
#
#   Slow operation: 3028ms so far, now at attachApplicationLocked: after updateOomAdjLocked
#   Long monitor contention with owner binder:1170_7 at ActivityManagerService.attachAp...
#
# dan itu membuat setiap proses yang baru lahir gagal menyelesaikan startup:
# SystemUI, com.android.phone, providers.media.module, android.process.acore
# semuanya ANR dengan alasan "failed to complete startup".
#
# Perangkat sebenarnya PUNYA yang dibutuhkan lmkd -- /dev/memcg/memory.pressure_level
# ada. Yang salah hanya deklarasinya.
#
# util.cpp:108-110 menimpa entri berdasarkan nama controller, jadi deklarasi v1
# di berkas vendor ini menggantikan entri v2 dari profil dasar. Nilai Mode/UID/GID
# mengikuti definisi memcg legacy AOSP sebelum migrasi ke v2.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/cgroups.json:$(TARGET_COPY_OUT_VENDOR)/etc/cgroups.json

# Catatan penyelidikan vendor.lineage.health-service.default (SELESAI).
#
# Servis ini pernah dinonaktifkan karena tidak pernah mendaftarkan
# IChargingControl: main thread system_server menggantung di
# waitForDeclaredService lalu dibunuh Watchdog.
#
#   WATCHDOG KILLING SYSTEM PROCESS: Blocked in handler on main thread for 70s
#     at ChargingControlController.<init>(ChargingControlController.java:85)
#   159x "Waited one second for vendor.lineage.health.IChargingControl/default"
#
# Penyebabnya loop tak berujung di konstruktor ChargingControl. Kalau
# HEALTH_CHARGING_CONTROL_CHARGING_PATH tidak terdefinisi, konstruktor masuk
# cabang "while (!mChargingEnabledNode)" yang memindai kandidat node selamanya
# (ChargingControl.cpp:73-87) -- sebelum AServiceManager_addService sempat
# dipanggil di service.cpp, sehingga servis hidup tapi tidak pernah terdaftar.
#
# Setelan soong_config di atas MEMANG sudah memperbaikinya, tapi dulu tidak
# pernah terverifikasi karena perangkat belum bisa boot untuk diuji.
# Diverifikasi 28 Agu 2026 dengan menjalankan binernya langsung di perangkat:
#
#   makro terkompilasi : -DHEALTH_CHARGING_CONTROL_CHARGING_PATH=
#                        "/sys/class/power_supply/battery/charging_enabled"
#                        -DHEALTH_CHARGING_CONTROL_SUPPORTS_TOGGLE
#   service check      : IChargingControl/default -> found
#                        IFastCharge/default      -> found
#   dumpsys            : node terpilih /sys/class/power_supply/battery/charging_enabled
#                        Charging enabled: true, supported mode: 1
#   WATCHDOG KILLING   : 0
#   "Waited one second" : 0
#   boot               : normal, ~60 detik
#
# supports_deadline dan supports_limit sengaja TIDAK diset: keduanya default
# kosong di Android.bp hulu, sehingga blok berloop serupa untuk deadline
# (ChargingControl.cpp:95-109) dan limit (:116-131) tidak ikut terkompilasi.
# Menyetel salah satunya tanpa path yang menyertai akan menghidupkan kembali
# bug yang sama.
#
# sepolicy tidak perlu ditambah: label hal_lineage_health_default_exec sudah
# ada di device/lineage/sepolicy/common/vendor/file_contexts:10 dan diterapkan
# otomatis lewat PRODUCT_PACKAGES.

# Touchscreen
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml

# Vibrator
#
# HIDL vibrator 1.0 sudah dihapus hulu di 23.2 -- hardware/interfaces/vibrator/
# hanya menyisakan aidl/. Karena itu jalur passthrough lama tidak bisa dipakai
# lagi dan sempat dinonaktifkan di commit 0231000 (getaran mati).
#
# Penggantinya HAL AIDL yang menulis langsung ke sysfs, disalin dari
# acroreiser/ULH lenovo a6010 (aidl/vibrator/, device.mk:469) -- sama-sama
# msm8916 dan sama-sama lineage-23.2.
#
# Node yang dipakainya diverifikasi ADA di perangkat ini, bukan diasumsikan:
#   /sys/class/timed_output/vibrator/enable       (durasi, ms)
#   /sys/class/timed_output/vibrator/vtg_level    (amplitudo)
#   vtg_default, vtg_max, vtg_min
# dan menulis 800 ke node enable lewat adb benar-benar menggerakkan motornya.
PRODUCT_PACKAGES += \
    android.hardware.vibrator-service.msm8916

# RIL
# libcnefeatureconfig dibuang 7 Agu 2026 (M4): modulnya hanya disediakan repo
# external/connectivity fork UL yang TIDAK ADA di manifest official
# (PLAN-OFFICIAL §1.2C/§1.5). Diverifikasi tak ada konsumen: nol blob vendor
# menautkannya, dan zip baseline UL yang jalan tidak mengirim file-nya.
PRODUCT_PACKAGES += \
    librmnetctl \
    libxml2 \
    libril_shim

# Pembungkus HIDL radio 1.4, WAJIB agar seluler berfungsi di Android 16.
#
# RIL.java hanya mencoba TIGA versi HIDL, berurutan V1_6 -> V1_5 -> V1_4, lalu
# menyerah dengan "IRadio <1.4 is no longer supported." (RIL.java:702-728).
# Blob A37 era 2016 hanya menyediakan @1.0/@1.1 lewat rild, jadi ketiganya
# gagal, mRadioProxy ditandai disabled, dan keempat sub-servis AIDL (DATA,
# MODEM, NETWORK, VOICE) ikut disabled. Akibatnya framework tidak pernah bisa
# bicara ke modem: gsm.sim.state KOSONG (bukan bahkan ABSENT) dan
# mServiceState OUT_OF_SERVICE meski SIM terpasang.
#
# Terukur di perangkat 27 Agu 2026, langsung dari log:
#   E RILJ: IRadio <1.4 is no longer supported. [PHONE0]
#   E RILJ: getRadioProxy: set mRadioProxy for slot1 as disabled
#
# Wrapper ini TIDAK bicara ke modem. Ia mengambil IRadio@1.0 yang sudah
# didaftarkan rild lewat getService("slotN"), membungkusnya, lalu
# mendaftarkannya kembali dengan nama yang sama sebagai servis 1.4
# (hidl/radio/service.cpp:42-56). Dependensinya hanya pustaka antarmuka HIDL --
# tanpa libril, tanpa socket -- sehingga murni penerjemah 1.0 <-> 1.4.
#
# Sumbernya disalin apa adanya dari acroreiser/ULH a6010
# (android_device_lenovo_a6010, hidl/radio, commit 84be99c "msm8916: radio:
# 1.4: legacy: Initial wrapper" dan 96ff176 "switch to our in-tree radio 1.4
# wrapper"). Nol kode khas a6010: satu-satunya penyebutan perangkat adalah
# nama modul yang memuat msm8916, dan itu chip yang sama.
#
# manifest.xml WAJIB ikut dinaikkan ke <version>1.4</version>. Karena
# getHidlTransport() mencocokkan dengan minorAtLeast(), deklarasi 1.4 tetap
# memenuhi pendaftaran @1.1 milik rild, jadi keduanya bisa hidup berdampingan.
PRODUCT_PACKAGES += \
    android.hardware.radio@1.5-service.msm8916

# IRadioConfig 1.1, pelengkap pembungkus radio di atas.
#
# Tanpa modul ini com.android.phone mengulang tiga error tiap kali menyentuh
# telephony, terukur 12 kali pada build 20260827_161656:
#   E RadioConfig: getHidlRadioConfigProxy1_3: getService: NoSuchElementException
#   E RadioConfig: getHidlRadioConfigProxy1_1: getService | linkToDeath: ...
#   E RadioConfig: getRadioConfigProxy: mRadioConfigProxy == null
#
# Modem A37 tidak punya jalur QMI untuk permintaan RadioConfig, jadi servis ini
# menjawab REQUEST_NOT_SUPPORTED. Itu jalur yang memang ditangani framework:
# UiccController.onGetSlotStatusDone() menyetel mIsSlotStatusSupported = false
# lalu kembali ke getIccCardStatus per telepon. Hasilnya jalur slot mati dengan
# rapi, bukan lewat exception berulang.
#
# Disalin dari a6010 (hidl/radio_config) dengan satu penyimpangan yang disengaja:
# RadioResponseInfo diisi serial, type, dan error. Sumber aslinya memakai struct
# tanpa inisialisasi, padahal RadioConfig.processResponse() mencocokkan respons
# lewat findAndRemoveRequestFromList(serial) -- serial yang tidak digemakan
# membuat setiap RILRequest menggantung.
PRODUCT_PACKAGES += \
    android.hardware.radio.config@1.1-service.msm8916
# libcutils_shim sebelumnya ada di daftar ini, padahal modulnya tidak pernah
# terdefinisi di tree — jadi baris itu tidak menghasilkan apa pun sementara
# pemetaan TARGET_LD_SHIM_LIBS-nya menyuntikkan DT_NEEDED ke blob RIL dan
# membuat rild gagal dlopen. Diganti libril_shim, yang benar-benar dibangun
# dari device/oppo/A37/libshims dan menyediakan simbol yang sungguh hilang
# (android::AudioSystem::setErrorCallback). Lihat catatan di BoardConfig.mk.

# Baseband Fix
PRODUCT_PACKAGES += \
    set_baseband.sh

# Lights
PRODUCT_PACKAGES += \
    android.hardware.light@2.0-service.oppo_msm8916

# Properties
# ccodec=0 mematikan SELURUH Codec 2.0 (Codec2InfoBuilder.cpp:407:
#   "0 - No Codec 2.0 components are available.").
# Warisan device tree msm8916 era LOS 14.1, saat CCodec masih baru. Dulu aman
# karena decoder audio software datang dari OMX.google.*; komponen itu dihapus
# di Android 12, jadi di 22.2 setelan ini menyisakan NOL decoder audio -- store
# OMX vendor hanya punya komponen video QCOM. Akibatnya audio mati di semua
# aplikasi yang memakai MediaCodec (NewPipe bisu, SoundPool gagal muat .ogg).
# Browser tidak terdampak karena Chromium mendekode audio di prosesnya sendiri.
# 4 = semua komponen tersedia dengan rank normal; omx_default_rank=0 di bawah
# menjaga decoder video QCOM tetap diutamakan di atas software.
PRODUCT_PROPERTY_OVERRIDES += \
    drm.service.enabled=1 \
    debug.stagefright.ccodec=4 \
    debug.stagefright.omx_default_rank.sw-audio=1 \
    debug.stagefright.omx_default_rank=0 \
    vendor.mediacodec.binder.size=6 \
    vidc.enc.narrow.searchrange=1

# Keylayout
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/gpio-keys.kl:system/usr/keylayout/gpio-keys.kl \
    $(LOCAL_PATH)/keylayout/ft5x06_ts.kl:system/usr/keylayout/ft5x06_ts.kl \
    $(LOCAL_PATH)/keylayout/synaptics-s3203.kl:system/usr/keylayout/synaptics-s3203.kl \
    $(LOCAL_PATH)/keylayout/qpnp_pon.kl:system/usr/keylayout/qpnp_pon.kl

# Storage — penyesuaian Android 12.
#
# A12 menyalakan casefold pada penyimpanan teremulasi secara default lewat
# build/make/target/product/emulated_storage.mk. ext4 di kernel 3.10 TIDAK punya
# dukungan casefold sama sekali, jadi default itu harus dibatalkan di sini.
# Pola diambil dari acroreiser/android_device_lenovo_a6010 lineage-19.1 (msm8916,
# kernel 3.10 yang sama) dan cocok dengan ROM referensi 19.1 A37 yang terbukti
# boot: external_storage.casefold.enabled=0 dan sdcardfs.enabled=0 di build.prop.
#
# ro.sys.sdcardfs=true era 18.1 dibuang: di A12 sakelarnya
# external_storage.sdcardfs.enabled, dan ROM referensi menyetelnya 0 (pakai FUSE).
PRODUCT_QUOTA_PROJID := 1
PRODUCT_FS_CASEFOLD := 0

PRODUCT_PROPERTY_OVERRIDES += \
    external_storage.projid.enabled=1 \
    external_storage.casefold.enabled=0 \
    external_storage.sdcardfs.enabled=0

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml

# Properties
PRODUCT_PROPERTY_OVERRIDES += \
    wifi.interface=wlan0

# WiFi HAL
# .legacy → regular (Sumber: msm8916-common lineage-18.1)
#
# LOS 21: HIDL wifi DICABUT — hardware/interfaces/wifi/ tidak punya 1.*/default
# lagi, hanya aidl/default. Penggantinya android.hardware.wifi-service
# (hardware/interfaces/wifi/aidl/default/Android.bp:116).
#
# Ini pertukaran yang aman untuk perangkat ini: layanan AIDL tetap memakai
# libwifi-hal + libwifi-system-iface yang sama persis dengan layanan HIDL lama,
# jadi HAL vendor di bawahnya (libwifi-hal-qcom) tidak berubah. Ia juga membawa
# vintf_fragment sendiri, konsisten dengan manifest.xml kita yang memang sudah
# TIDAK mendeklarasikan wifi ("wifi/hostapd/supplicant: dihapus — paket service
# bawa VINTF fragment").
#
# ⚠️ Wi-Fi BERFUNGSI di ROM proyek 20; ini satu-satunya perubahan yang
# menyentuhnya. Kalau Wi-Fi mati setelah boot pertama, curigai baris ini lebih
# dulu, bukan kernel atau blob.
PRODUCT_PACKAGES += \
    android.hardware.wifi-service

# Wifi
PRODUCT_PACKAGES += \
    libwcnss_qmi \
    wcnss_service

# libwpa_client dibutuhkan oleh prebuilt vendor/bin/imsdatadaemon (DT_NEEDED),
# tapi tidak ikut terpasang sehingga daemon-nya gagal dlopen dan tidak pernah
# jalan. init.target.rc menyalakannya saat sys.ims.QMI_DAEMON_STATUS=1 dan
# device ini memang mengaktifkan VoLTE (persist.dbg.ims_volte_enable=1,
# persist.dbg.volte_avail_ovr=1), jadi tanpa ini VoLTE tidak mungkin bekerja.
# Modulnya ada di external/wpa_supplicant_8 dan sudah LOCAL_PROPRIETARY_MODULE,
# jadi terpasang ke /vendor/lib tempat biner vendor bisa melihatnya.
PRODUCT_PACKAGES += \
    libwpa_client

# WireGuard
# Modul kernelnya built-in (CONFIG_WIREGUARD=y, 1.0.20220627) tapi tidak bisa
# dipakai dari shell tanpa alat userspace ini -- interface, kunci, dan peer
# semuanya lewat netlink WireGuard. Sumbernya di wireguard-tools/ pada device
# tree ini; lihat komentar Android.bp di sana soal kenapa tidak lagi di
# external/. Aplikasi WireGuard Android membawa alatnya sendiri dan tidak
# bergantung pada ini.
PRODUCT_PACKAGES += \
    wg

PRODUCT_PACKAGES += \
    hostapd \
    wpa_supplicant \
    wpa_supplicant.conf

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/p2p_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/p2p_supplicant_overlay.conf \
    $(LOCAL_PATH)/configs/wpa_supplicant_overlay.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant_overlay.conf \
    $(LOCAL_PATH)/configs/WCNSS_qcom_cfg.ini:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/WCNSS_qcom_cfg.ini

# Wifi
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/wifi/WCNSS_cfg.dat:$(TARGET_COPY_OUT_VENDOR)/firmware/wlan/prima/WCNSS_cfg.dat \
    $(LOCAL_PATH)/wifi/WCNSS_qcom_wlan_nv.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin \
    $(LOCAL_PATH)/wifi/WCNSS_wlan_dictionary.dat:$(TARGET_COPY_OUT_VENDOR)/firmware/wlan/prima/WCNSS_wlan_dictionary.dat

# USB HAL
PRODUCT_PACKAGES += \
    android.hardware.usb@1.0-service.cyanogen_8916

# Driver prima membaca konfigurasinya lewat request_firmware, jadi file yang
# sama harus ada juga di bawah firmware/wlan/prima. Ini satu-satunya aturan yang
# meng-install file tersebut — aturan symlink kembar di Android.mk sudah dibuang.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/WCNSS_qcom_cfg.ini:$(TARGET_COPY_OUT_VENDOR)/firmware/wlan/prima/WCNSS_qcom_cfg.ini

# Optimize
PRODUCT_SYSTEM_SERVER_COMPILER_FILTER := speed-profile
PRODUCT_ALWAYS_PREOPT_EXTRACTED_APK := true
PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE := true

# AOT penuh untuk aplikasi berat yang sering dibuka.
# Terukur 27 Agu 2026: dexpreopt default menghasilkan filter verify untuk 60 dari
# 156 artefak di image ini -- termasuk Settings. Yang membedakan BUKAN ada atau
# tidaknya .odex (odex selalu dibuat), melainkan rasio odex/vdex: yang benar-benar
# terkompilasi 58-430x, yang verify justru di bawah 1x. Settings: odex 229.856
# vs vdex 591.876 = 0,39x, sedangkan SystemUI 58x.
#
# Dampaknya diukur A/B di perangkat, pola dua putaran identik, am start -W ke
# sub-halaman Settings dalam keadaan warm:
#   Display  674 -> 604 ms      Sound    818 -> 682 ms
#   Storage  497 -> 335 ms      Apps     613 -> 559 ms
# Rata-rata sekitar 15%. Nyata tapi bukan perubahan besar, dan itu memang sesuai
# dengan sisa profilnya: membuka menu Settings didominasi kerja SERIAL di UI
# thread -- 490 ms CPU satu thread dari 780 ms waktu dinding, sementara sistem
# 56% menganggur dan CPU sudah 61% waktu di frekuensi puncak 1209,6 MHz.
# Tidak ada headroom lain yang bisa diambil.
#
# INI BUKAN pm.dexopt.first-boot=speed. PRODUCT_DEXPREOPT_SPEED_APPS bekerja saat
# BUILD; tidak ada dex2oat yang berjalan di perangkat, jadi tidak ada kaitannya
# dengan bootloop yang pernah terjadi. Lihat blok pm.dexopt di atas.
#
# Ongkos ruang sekitar 2,5x ukuran dex, terukur langsung dari Settings
# (dex 21,7 MB -> odex speed 52,4 MB). Perkiraan tambahan total ~180 MB;
# partisi system punya 948 MB kosong dari 2,6 GB.
#
# SENGAJA TIDAK DIMASUKKAN, ongkosnya besar tapi jarang dibuka:
#   ThemePicker         dex 44,9 MB -> ~112 MB  (hanya saat ganti wallpaper/tema)
#   Seedvault           dex 19,8 MB -> ~50 MB   (aplikasi backup)
#   LineageSetupWizard                          (hanya sekali saat boot pertama)
PRODUCT_DEXPREOPT_SPEED_APPS += \
    SystemUI \
    Settings \
    TeleService \
    Dialer \
    Contacts \
    messaging \
    DocumentsUI \
    CredentialManager \
    Aperture \
    Glimpse \
    Twelve \
    Etar \
    Updater \
    StorageManager

# Strip debug
PRODUCT_MINIMIZE_JAVA_DEBUG_INFO := true
PRODUCT_ART_TARGET_INCLUDE_DEBUG_BUILD := false

# CATATAN dalvik: nilai di bawah inilah yang BENAR-BENAR berjalan. Ia masuk ke
# build.prop dan tidak ada yang menimpanya.
#
# Komentar sebelumnya di sini menyatakan sebaliknya -- bahwa yang berlaku adalah
# init/init_msm8916.cpp (set_device_dalvik_properties) dan empat dari enam nilai
# di bawah tidak pernah dipakai. Itu benar untuk pohon 22.2 dan SUDAH TIDAK
# BENAR sejak pindah ke 23.2.
#
# Sebabnya: LineageOS 23.2 menautkan lib init vendor lewat
# system/core/init/Android.bp:241, select(soong_config_variable("libinit",
# "vendor_init_lib")). BoardConfig kita memakai TARGET_INIT_VENDOR_LIB, yang
# sudah tidak dibaca siapa pun -- grep -rn pada build/make nol hasil. Jadi
# libinit_msm8916 tidak pernah tertaut ke init, dan vendor_load_properties()
# tidak pernah berjalan.
#
# Dibuktikan di perangkat pada build 20260901_232342: getprop memberi
# heapgrowthlimit=192m dan heapsize=384m -- nilai dari blok ini, bukan 256m/512m
# milik init_msm8916.cpp -- sedangkan ro.alarm_boot dan
# ro.vendor.qti.sys.fw.bg_apps_limit tidak ada sama sekali.
#
# Wiring init vendor sengaja tidak dihidupkan kembali; alasannya di
# BoardConfig.mk.
#
# 192m/384m DIPERTAHANKAN, dan itu keputusan berdasar ukuran, bukan kebiasaan.
# 2 September 2026 keduanya dibandingkan langsung di perangkat: A-B-A-B, tiap
# fase restart framework lalu 3 putaran x 10 aplikasi (30 peluncuran), dengan
# setprop dalvik.vm.heap* + `stop; start` sehingga tidak perlu flash ulang.
#
#   metrik                 192m/384m        256m/512m
#   5 app awal bertahan    4/5, 4/5         4/5, 4/5
#   lmkd kill              0, 0             0, 0
#   peluncuran COLD        7 dari 60        6 dari 60
#   rata-rata peluncuran   507, 420 ms      457, 419 ms
#   GC                     2x382ms, 1x197ms 2x530ms, 3x481ms
#   RAM bebas di akhir     26, 26 MB        40, 42 MB
#
# TIDAK TERBUKTI BERBEDA, dan alasannya yang penting: nol lmkd kill di keempat
# fase berarti ujiannya tidak pernah masuk wilayah tempat growth limit bekerja.
# Aplikasi sistem LineageOS berheap jauh di bawah 192 MB, jadi kedua batas
# sama-sama tidak pernah mengikat. Selisih waktu peluncuran 26 ms pun lebih
# kecil daripada sebaran dalam satu setelan (507 lawan 420 ms), jadi derau.
#
# Dua hal konsisten di kedua ulangan tapi lemah (n=2): GC total lebih lama
# dengan 256m -- masuk akal, heap lebih besar berarti lebih banyak dipindai --
# dan RAM bebas justru lebih banyak dengan 256m.
#
# Kalau suatu saat mau diuji ulang, ujinya HARUS memakai aplikasi yang benar
# benar mendorong heap sampai batas (browser dengan banyak tab, galeri foto
# besar), bukan aplikasi sistem. Tanpa itu hasilnya akan nol lagi.
# JANGAN taruh komentar tepat sesudah baris "+= \" di bawah. Backslash itu
# menyambung baris, jadi komentar ikut tersambung ke pernyataan penugasan dan
# make membuang SISA daftar tanpa galat sedikit pun. Terjadi 31 Agustus 2026
# (347a180f) dan menghapus ke-13 properti di bawah dari build.prop.
# dalvik.vm.dex2oat-threads DICABUT 31 Agustus 2026 (semula =2).
#
# Tidak ada default AOSP maupun LineageOS untuk properti ini -- kalau tidak
# diset, ART memilih sendiri berdasarkan jumlah inti. Baris itu SEBELUMNYA
# TANPA KOMENTAR, berbeda dari tetangganya, dan tidak ada alasan tercatat
# kenapa perangkat 4 inti dibatasi 2 thread.
#
# Diukur di perangkat, dex2oat speed pada messaging.apk:
#     -j2   13 dtk
#     -j4    8 dtk      -> 38% lebih cepat
#
# boot-dex2oat-threads=4 di bawah tetap dipertahankan: itu jalur boot, dan
# memang sudah memakai seluruh inti.
# BUILD 64-BIT: heapstartsize dan heapminfree diturunkan ke profil resmi AOSP
# untuk perangkat 2048 MB (frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk).
#
# Rujukan: Mi-Thorium menjalankan userspace 64-bit pada perangkat 1-2 GB dengan
# profil itu, memakai core_64_bit.mk tanpa ZYGOTE_FORCE_64 -- jadi dua zygote di
# RAM 2 GB memang bisa. Yang membedakan bukan arsitekturnya melainkan ongkos
# heap per proses.
#
# Pengujian A-B-A-B 2 September 2026 yang membenarkan 192m/384m hanya
# membandingkan heapgrowthlimit dan heapsize; heapstartsize dan heapminfree
# tidak pernah ikut diuji. Keduanya justru yang paling boros di sini:
#   heapstartsize 16m vs 8m   -> setiap proses mulai dengan heap 2x lebih besar
#   heapminfree   4m  vs 512k -> GC menyisakan 8x lebih banyak per heap
# Dengan zygote64_32 ongkos itu berlipat karena ada dua zygote.
#
# heapgrowthlimit dan heapsize DIPERTAHANKAN pada nilai yang sudah teruji.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=192m \
    dalvik.vm.heapsize=384m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m \
    dalvik.vm.zygotemaxfailedboots=5 \
    dalvik.vm.foreground-heap-growth-multiplier=2.0 \
    dalvik.vm.dex2oat-flags=--no-watch-dog \
    dalvik.vm.dex2oat-swap=true \
    dalvik.vm.boot-dex2oat-threads=4 \
    ro.vendor.qti.am.reschedule_service=true \
    sys.use_fifo_ui=1

# TextClassifier
# textclassifier.bundle1 DIBUANG DI 20: modulnya tidak ada di tree LOS 20
# (dulu pun entri mati — tidak pernah dibangun di 19.1). Model teks tetap
# tersedia lewat external/libtextclassifier sebagai berkas.

# Properties
# PENTING (M5-RIL, 7 Agu 2026): rild Android 13 membaca vendor.rild.libpath
# (hardware/ril/rild/rild.c:39), BUKAN rild.libpath legacy. Tanpa prop
# vendor.* ini rild masuk jalur "no-ril" (goto done): blob CAF
# libril-qc-qmi-1.so tak pernah dimuat, IRadio HIDL tak terdaftar, dan
# com.android.phone loop menunggu selamanya. Dites runtime: IRadio
# slot1/slot2+ISap terdaftar, SIM LOADED, LTE HOME by.U (51010),
# telepon/SMS/data jalan. 16 patch T-RIL UL ternyata TIDAK diperlukan.
PRODUCT_PROPERTY_OVERRIDES += \
    persist.data.qmi.adb_logmask=0 \
    persist.data.target=dpm3 \
    persist.radio.apm_sim_not_pwdn=1 \
    ro.telephony.call_ring.multiple=false \
    ro.use_data_netmgrd=true \
    persist.radio.multisim.config=dsds \
    persist.radio.custom_ecc=1 \
    persist.radio.ecc_hard_1=112,911,110,122,119,120,000,118 \
    persist.radio.ecc_hard_count=1 \
    rild.libpath=/system/vendor/lib/libril-qc-qmi-1.so \
    vendor.rild.libpath=/system/vendor/lib/libril-qc-qmi-1.so \
    ril.subscription.types=NV,RUIM \
    ro.telephony.default_network=9,1 \
    persist.data.netmgrd.qos.enable=false

# RIL
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/data/netmgr_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/data/netmgr_config.xml \
    $(LOCAL_PATH)/configs/data/qmi_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/data/qmi_config.xml \
    $(LOCAL_PATH)/configs/data/dsi_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/data/dsi_config.xml

# Seccomp
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp/mediacodec-seccomp.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# Sensors
# accelcal / AccCalibration / sensord DIBUANG DI 20: tidak ada sebagai modul
# di tree LOS 20, dan di 19.1 pun ketiganya entri mati — tidak pernah dibangun
# (diverifikasi dari log build 19.1). A37 tidak memakai SSP/Sensor Hub, jadi
# sensord (daemon QTI untuk itu) memang tidak dibutuhkan.
PRODUCT_PACKAGES += \
    android.hardware.sensors@1.0-impl \
    calmodule.cfg \
    sensors.msm8916

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/handheld_core_hardware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/handheld_core_hardware.xml \
    $(LOCAL_PATH)/configs/sensors/_hals.conf:$(TARGET_COPY_OUT_VENDOR)/etc/sensors/_hals.conf

# USB ID
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.usb.id.midi=90BA \
    ro.usb.id.midi_adb=90BB \
    ro.usb.id.mtp=2281 \
    ro.usb.id.mtp_adb=2282 \
    ro.usb.id.ptp=2284 \
    ro.usb.id.ptp_adb=2283 \
    ro.usb.id.ums=2286 \
    ro.usb.id.ums_adb=2285 \
    ro.usb.vid=2970

# TimeKeep
PRODUCT_PACKAGES += \
    timekeep \
    TimeKeep    

# LiveDisplay
# -service-legacymm DICABUT di 19.1. Ia butuh libmm-disp-apis.so yang menyambung
# ke socket pps milik mm-pp-daemon, dan daemon itu tidak bisa di-link di Android
# 12 (libmm-abl.so mencari android::IPowerManager::asInterface, simbol C++ yang
# hilang saat IPowerManager jadi AIDL-generated). Servis yang tidak pernah
# register + interface-nya terdeklarasi di manifest = getService(true)
# menggantung selamanya dan Watchdog membunuh system_server. Lihat manifest.xml.
#
# FASE 6 (27 Agu 2026): DIAKTIFKAN sebagai -service.sysfs (AIDL).
# Ini BUKAN sekadar merapikan. Tanpa HAL ini LiveDisplay memakai jalur legacy
# LineageHardwareService.LegacyLineageHardware, yang melaksanakan
# setDisplayColorCalibration() lewat DisplayTransformManager.setColorMatrix()
# (LineageHardwareService.java:152). Matriks warna non-identitas di
# SurfaceFlinger membuat HWC2On1Adapter memasang HWC_SKIP_LAYER pada SEMUA
# layer (HWC2On1Adapter.cpp:2192, lewat mHasColorTransform di baris 889), lalu
# MDPComp menolak setiap layer ber-skip (isSupportedForMDPComp) sehingga GPU
# mengomposisi tiap frame di atas beban menggambar aplikasi.
# Terukur di perangkat: mode AUTO + malam (4800K) -> janky frames 97,7%,
# p50 77 ms. Dengan suhu netral -> 48,7%, p50 65 ms, dan flag layer berubah
# dari Framebuffer+SkipLayer menjadi Overlay (usesDeviceComposition true).
#
# LineageHardwareManager mendahulukan AIDL dan baru jatuh ke legacy kalau HAL
# tidak ada (LineageHardwareManager.java:516-537, 555-570), jadi memasang HAL
# ini mematikan jalur matriks SF sekaligus membetulkan skalanya: getMaxValue()
# HAL = 32768 (sesuai kernel), sedangkan legacy memakai MAX = 255.
#
# Diverifikasi di perangkat SEBELUM diaktifkan, karena PathManager melakukan
# LOG(FATAL) kalau tidak ada path yang R_OK|W_OK (DualStateMode.h:41-45) dan
# servis yang mati sementara VINTF-nya terdeklarasi akan menggantung
# waitForDeclaredService:
#   - /sys/class/graphics/fb0/rgb ADA, mode 0664, bisa di-chown ke system,
#     jadi .rc bawaan paket (yang meng-chown node itu) sudah cukup.
#   - mdss_livedisplay.c membuat atribut rgb tanpa syarat dan menerjemahkannya
#     jadi PCC di DSPP; r=g=b=32768 berarti MDP_PP_OPS_DISABLE (baris 154-155).
#   - Uji tulis "32768 29135 25711": warna menghangat, matriks SF TETAP
#     identitas, dan usesDeviceComposition TETAP true saat scroll.
# Fragmen VINTF dibawa paketnya sendiri (sysfs-dcc.xml), jadi tidak perlu
# deklarasi manual di manifest.xml -- blok HIDL 2.0 yang lama dicabut.
PRODUCT_PACKAGES += \
    vendor.lineage.livedisplay-service.sysfs

$(call soong_config_set_bool,livedisplay_sysfs,enable_dcc,true)

$(call inherit-product, vendor/oppo/A37/A37-vendor.mk)

# adb lewat USB: PAKSA jalur FunctionFS non-AIO (blocking).
#
# Kernel 3.10 perangkat ini tidak punya AIO pada endpoint FunctionFS sama sekali
# -- drivers/usb/gadget/f_fs.c nol kemunculan aio, dan FFS disediakan lewat
# gadget android lama (android.c:39 #include "f_fs.c"), bukan CONFIG_USB_FUNCTIONFS.
# adbd Android 15 memakai io_submit tanpa syarat, sehingga endpoint terbentuk
# tapi data tidak pernah mengalir: host melihat perangkat "offline" selamanya.
#
# init.qcom.usb.rc sudah menyetel keduanya di `on fs`, tapi diulang di sini supaya
# tersedia dari build.prop -- yaitu sebelum aksi init mana pun sempat berjalan,
# sehingga tidak ada lagi ketergantungan urutan.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.adb.nonblocking_ffs=false \
    persist.adb.nonblocking_ffs=false
