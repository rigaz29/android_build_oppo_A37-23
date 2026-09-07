#
# Copyright (C) 2018 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_SRC_FILES := \
    atomic.cpp \
    android/sensor.cpp \
    gui/SensorManager.cpp \
    ui/GraphicBuffer.cpp \
    MediaCodec.cpp \
    AudioSource.cpp \
    MetaData.cpp \
    camera_parameters/CameraParameters.cpp \
    justshoot_shim.cpp

LOCAL_C_INCLUDES := gui
LOCAL_SHARED_LIBRARIES := libsensor libutils liblog libbinder \
                          libandroid libui libstagefright libmedia

LOCAL_MODULE := libshim_camera
LOCAL_MODULE_CLASS := SHARED_LIBRARIES

# BUKAN modul vendor di Android 14 — LOCAL_VENDOR_MODULE dihapus di sini.
#
# build/make/core/binary.mk:1328 hanya mengizinkan modul vendor menaut
# native:vendor, native:vndk, atau native:platform_vndk. Shim ini menaut
# libsensor, libandroid, libstagefright, libmedia, dan libgui — semuanya
# native:platform, jadi sebagai modul vendor ia ditolak build.
#
# Memindahkannya ke /system aman, dan itu dibuktikan dari perangkat yang
# menjalankan ROM LOS 20 kita plus dari artefak build kita sendiri, bukan dari
# dokumentasi:
#
#   /linkerconfig/ld.config.txt   namespace.default.isolated = false
#                                 search.paths = /system/${LIB} … /vendor/${LIB}
#
#   readelf -d out/…/system/lib/libshim_camera.so   (12 DT_NEEDED terbaca)
#     DELAPAN di antaranya ada di /system/lib dan TIDAK ADA di
#     /system/vendor/lib: libsensor, libutils, liblog, libbinder, libandroid,
#     libui, libstagefright, libmedia.
#     Empat sisanya libc++/libc/libm/libdl (tersedia di kedua namespace).
#
#   Modul ini juga terbukti terpasang ke /system/lib, bukan /system/vendor/lib —
#   itu hasil langsung dari membuang LOCAL_VENDOR_MODULE di bawah.
#
# ⚠️ Pengukuran ini diulang 10 Agustus 2026. Versi pertama komentar ini menyebut
# `llvm-readelf`, yang TIDAK ADA di mesin build ini; perintahnya gagal dan
# hasilnya nol yang menyesatkan. Pakai readelf/nm GNU, dan selalu sertakan uji
# kontrol (`readelf -d <berkas> | grep -c NEEDED` harus > 0).
#
# Blob tetap menemukan shim: TARGET_LD_SHIM_LIBS bukan injeksi DT_NEEDED saat
# build, melainkan cppflag LD_SHIM_LIBS ke linker, dan
# bionic/linker/linker.cpp:1368 memuatnya BY NAME ke namespace yang sama
# dengan blob pemanggilnya.

include $(BUILD_SHARED_LIBRARY)

# ---------------------------------------------------------------------------
# libshim_camera_sensor -- shim ramping khusus mm-qcamera-daemon.
#
# Daemon hanya membutuhkan SEMBILAN simbol dari shim. Diukur langsung, bukan
# ditebak: irisan antara simbol UND milik libmmcamera2_stats_modules.so dan
# simbol yang didefinisikan libshim_camera.so:
#
#   ASensorEventQueue_disableSensor   ASensorManager_createEventQueue
#   ASensorEventQueue_enableSensor    ASensorManager_destroyEventQueue
#   ASensorEventQueue_getEvents       ASensorManager_getDefaultSensor
#   ASensorEventQueue_setEventRate    ASensor_getMinDelay
#   _ZN7android13SensorManagerC1Ev
#
# Delapan pertama dari android/sensor.cpp, yang terakhir dari
# gui/SensorManager.cpp. Nol dari MediaCodec/AudioSource/MetaData/
# GraphicBuffer/CameraParameters.
#
# Kenapa dipisah: libshim_camera menaut libmedia, dan libmedia menaut
# libandroidicu.so yang hanya ada di /apex/com.android.i18n/lib. Namespace
# vendor tidak punya tautan ke APEX itu, jadi daemon gagal link:
#
#   CANNOT LINK EXECUTABLE "/system/vendor/bin/mm-qcamera-daemon":
#   library "libandroidicu.so" not found: needed by /system/lib/libmedia.so
#
# Pustaka yang ditaut modul ramping ini -- libsensor, libutils, liblog,
# libbinder, libandroid -- sudah diperiksa: DT_NEEDED-nya hanya libc/libm/libdl
# di luar /system/lib, jadi tidak ada rantai APEX sama sekali.
#
# libshim_camera yang gemuk TETAP dipakai lewat TARGET_LD_SHIM_LIBS untuk blob
# yang berjalan di dalam cameraserver, dan di sana libmedia memang tersedia.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := \
    android/sensor.cpp \
    gui/SensorManager.cpp
LOCAL_C_INCLUDES := gui
LOCAL_SHARED_LIBRARIES := libsensor libutils liblog libbinder libandroid
LOCAL_MODULE := libshim_camera_sensor
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# ---------------------------------------------------------------------------
# libandroid versi A37, dipasang ke /vendor/lib.
#
# Blob vendor menaut libandroid lewat DT_NEEDED, dan namespace vendor tidak
# menjangkau /system/lib:
#
#   CANNOT LINK EXECUTABLE "/vendor/bin/mm-qcamera-daemon":
#   library "libandroid.so" not found:
#   needed by /system/vendor/lib/libmmcamera2_stats_modules.so
#
# Hanya 13 simbol yang dibutuhkan -- diukur dengan mengiris simbol UND blob
# terhadap simbol yang didefinisikan libandroid platform:
#
#   ALooper_forThread  ALooper_pollOnce  ALooper_prepare  ALooper_wake
#   ASensorManager_getInstance  ASensorManager_getDefaultSensor
#   ASensorManager_createEventQueue  ASensorManager_destroyEventQueue
#   ASensorEventQueue_enableSensor  ASensorEventQueue_disableSensor
#   ASensorEventQueue_setEventRate  ASensorEventQueue_getEvents
#   ASensor_getMinDelay
#
# gui/SensorManager.cpp ikut disertakan karena libmmcamera2_stats_modules.so
# juga menuntut android::SensorManager::SensorManager() -- konstruktor tanpa
# argumen yang sudah lama dicabut dari Android. Dengan itu di sini, LD_PRELOAD
# libshim_camera_sensor.so TIDAK diperlukan lagi untuk daemon.
#
# Closure dependensinya sudah diperiksa: libsensor/libutils/liblog/libbinder
# menghasilkan 18 pustaka, TANPA libicu maupun libharfbuzz_ng, jadi tidak ada
# rantai APEX yang tak terjangkau.
#
# Dipasang lewat LOCAL_MODULE_PATH, bukan LOCAL_VENDOR_MODULE: sebagai modul
# vendor ia ditolak build karena menaut pustaka native:platform -- alasan yang
# sama dengan libshim_camera di atas.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := stub/libandroid_stub.cpp
LOCAL_SHARED_LIBRARIES := liblog
# LOCAL_MODULE_STEM TIDAK bisa dipakai di sini: shared_library_internal.mk:17
# menolaknya untuk pustaka ("Cannot set module stem for a library").
# Berkasnya tetap bernama libandroid_a37_vendor.so, dan libandroid.so disediakan
# sebagai symlink lewat install_symlink di device/oppo/A37/Android.bp --
# pola yang sama dengan libstdc++ di sana.
LOCAL_MODULE := libandroid_a37_vendor
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib
# BUILD 64-BIT: LOCAL_MULTILIB wajib eksplisit. shared_library.mk:14-16 menolak
# LOCAL_MODULE_PATH untuk pustaka bila multilib "both" DAN TARGET_2ND_ARCH ada,
# karena path-nya jadi ambigu antara lib dan lib64.
LOCAL_MULTILIB := 32
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# Varian 64-bit dari stub yang sama.
# Konsumennya vendor/lib64/libmm-als.so, sedangkan yang 32-bit di atas melayani
# vendor/lib/libmmcamera2_stats_modules.so. Keduanya dibutuhkan.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := stub/libandroid_stub.cpp
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_MODULE := libandroid_a37_vendor64
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib64
LOCAL_MULTILIB := 64
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# ---------------------------------------------------------------------------
# libmedia kosong untuk /vendor/lib.
#
# libril-qc-qmi-1.so mencantumkan libmedia.so di DT_NEEDED tapi memakai NOL
# simbolnya (diukur: irisan simbol UND-nya dengan simbol libmedia = kosong).
# Tanpa berkas ber-soname itu di namespace vendor, rild gagal:
#
#   RILD: dlopen failed: library "libmedia.so" not found:
#         needed by /system/vendor/lib/libril-qc-qmi-1.so
include $(CLEAR_VARS)
LOCAL_SRC_FILES := stub/libmedia_stub.cpp
LOCAL_SHARED_LIBRARIES := libutils liblog
# LOCAL_MODULE_STEM TIDAK bisa dipakai di sini: shared_library_internal.mk:17
# menolaknya untuk pustaka ("Cannot set module stem for a library").
# Berkasnya tetap bernama libmedia_a37_vendor.so, dan libmedia.so disediakan
# sebagai symlink lewat install_symlink di device/oppo/A37/Android.bp --
# pola yang sama dengan libstdc++ di sana.
LOCAL_MODULE := libmedia_a37_vendor
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
# Varian 32-bit, untuk vendor/lib/libril-qc-qmi-1.so. Konsumen ini SEMPAT HILANG
# dari catatan ketika RIL masih 64-bit, lalu muncul kembali saat rild dan radio
# HAL dipaksa 32-bit -- lihat uraian panjangnya di device/oppo/A37/Android.bp.
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib
LOCAL_MULTILIB := 32
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

# Varian 64-bit dari stub libmedia yang sama.
# Konsumennya vendor/lib64: lib-dplmedia.so, lib-imscamera.so, lib-imsvt.so,
# dan libril-qc-qmi-1.so.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := stub/libmedia_stub.cpp
LOCAL_SHARED_LIBRARIES := libutils liblog
LOCAL_MODULE := libmedia_a37_vendor64
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_PATH := $(TARGET_OUT_VENDOR)/lib64
LOCAL_MULTILIB := 64
LOCAL_MODULE_TAGS := optional
include $(BUILD_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_SRC_FILES := camera_shim.c
LOCAL_SHARED_LIBRARIES := libutils libgui liblog
LOCAL_MODULE := libcamera_shim
LOCAL_MODULE_TAGS := optional
# LOCAL_VENDOR_MODULE dihapus — alasan sama dengan libshim_camera di atas.
# hardware/*.h tidak lagi implisit di Android 14, jadi diminta eksplisit.
LOCAL_HEADER_LIBRARIES := libhardware_headers
include $(BUILD_SHARED_LIBRARY)

# Shim untuk libril-qc-qmi-1.so. Menyediakan
# android::AudioSystem::setErrorCallback(void(*)(int)) yang dihapus dari
# libaudioclient di Android 11. Lihat AudioSystem_ril.cpp untuk rinciannya.
#
# ⚠️ JANGAN samakan dengan dua shim di atas. libril_shim TETAP modul vendor.
#
# Ia hanya menaut libaudioclient/libutils/liblog, jadi tidak kena batasan
# link-type — dan RIL adalah satu-satunya subsistem A37 yang terbukti berfungsi
# di perangkat. Mengubahnya "demi konsistensi" adalah risiko tanpa keuntungan.
#
include $(CLEAR_VARS)
LOCAL_SRC_FILES := AudioSystem_ril.cpp
LOCAL_MODULE := libril_shim
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_TAGS := optional
LOCAL_VENDOR_MODULE := true
include $(BUILD_SHARED_LIBRARY)

# /vendor/lib/libcamera_client.so untuk blob HAL1 kamera.
#
# camera.vendor.msm8916.so menautnya lewat DT_NEEDED dan tanpa berkas ber-soname
# itu di namespace sphal, CameraWrapper tidak pernah bisa membuka backend-nya:
#
#   E vndksupport: Could not load /vendor/lib/hw/camera.vendor.msm8916.so from
#     sphal namespace: dlopen failed: library "libcamera_client.so" not found
#   E CameraWrapper: failed to open vendor camera module
#   I CameraProviderManager: Camera provider legacy/0 ready with 0 camera devices
#
# libcamera_client platform (frameworks/av/camera/Android.bp:77) TIDAK
# vendor_available, jadi tidak bisa dipasang ke /vendor.
#
# Diukur: dari 372 simbol UND blob, 137 diambil dari libcamera_client dan
# KESELURUHAN 137 itu CameraParameters -- nol simbol lain. Karena itu yang
# dibangun di sini hanya CameraParameters.cpp hulu, bukan libcamera_client utuh.
# Berkasnya dirujuk langsung dari pohon hulu, tidak disalin.
#
# DITAMBAH 5 KONSTANTA EKSTENSI OPPO/QCOM.
#
# CameraParameters.cpp hulu saja TIDAK cukup. Blob juga merujuk lima konstanta
# yang tidak pernah ada di AOSP:
#
#   android::CameraParameters::KEY_TRACK_ENABLE
#   android::CameraParameters::KEY_TRACK_AREAS
#   android::CameraParameters::KEY_APP_MASK
#   android::CameraParameters::FOCUS_MODE_MANUAL_POSITION
#   android::CameraParameters::WHITE_BALANCE_MANUAL_CCT
#
#   E vndksupport: dlopen failed: cannot locate symbol
#     "_ZN7android16CameraParameters16KEY_TRACK_ENABLEE"
#
# Kelimanya sudah lama ada di camera_parameters/CameraParameters.cpp milik pohon
# ini, tapi selama ini hanya dibangun ke dalam libshim_camera -- modul system,
# jadi mendarat di /system/lib dan tak pernah terjangkau namespace sphal.
#
# CATATAN METODE: kelima simbol ini SEMPAT LUPUT karena pengukuran pertama
# mengiris "simbol UND blob" dengan "simbol yang diekspor libcamera_client".
# Simbol yang memang tidak pernah ada di AOSP mustahil muncul di irisan seperti
# itu. Yang benar: simbol UND blob DIKURANGI seluruh simbol yang tersedia di
# /vendor/lib dan /vendor/lib/hw. Kekeliruan yang sama pernah terjadi pada stub
# libmedia; lihat catatannya di stub/libmedia_stub.cpp.
#
# Nama berkasnya libcamera_client_a37_vendor.so; libcamera_client.so disediakan
# sebagai symlink lewat install_symlink di device/oppo/A37/Android.bp, pola yang
# sama dengan libmedia, libandroid, libgui, dan libstdc++ di sana.
include $(CLEAR_VARS)
LOCAL_SRC_FILES := \
    ../../../../frameworks/av/camera/CameraParameters.cpp \
    camera_parameters/CameraParameters.cpp
LOCAL_C_INCLUDES := \
    frameworks/av/camera/include \
    system/media/camera/include
LOCAL_SHARED_LIBRARIES := libutils liblog
LOCAL_MODULE := libcamera_client_a37_vendor
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_VENDOR_MODULE := true
LOCAL_MODULE_TAGS := optional
LOCAL_32_BIT_ONLY := true
include $(BUILD_SHARED_LIBRARY)
