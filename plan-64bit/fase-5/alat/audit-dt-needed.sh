#!/bin/bash
# Audit dependensi ELF pada pohon ROM terbangun: cari DT_NEEDED yang tidak
# terselesaikan di namespace yang benar (arch + vendor/system).
P=/root/los23/out/target/product/A37/system
declare -A HAVE   # "arch|ruang|nama" -> 1

index() { # $1=dir $2=arch $3=ruang
  [ -d "$1" ] || return
  for f in "$1"/*.so; do [ -e "$f" ] && HAVE["$2|$3|$(basename "$f")"]=1; done
}
for a in 32:lib 64:lib64; do
  ar=${a%%:*}; d=${a##*:}
  index "$P/$d"            "$ar" sys
  index "$P/vendor/$d"     "$ar" ven
  index "$P/vendor/$d/hw"  "$ar" ven
  index "$P/vendor/$d/egl" "$ar" ven
done
# LLNDK/bionic: selalu tersedia di namespace vendor Android 16
LLNDK="libc.so libm.so libdl.so libdl_android.so libc++.so liblog.so libz.so
libnativewindow.so libsync.so libvndksupport.so libbinder_ndk.so libneuralnetworks.so
libcgrouprtl.so ld-android.so libEGL.so libGLESv1_CM.so libGLESv2.so libGLESv3.so
libmediandk.so libandroid_net.so libselinux.so libcrypto.so libhardware.so"
is_llndk() { case " $LLNDK " in *" $1 "*) return 0;; esac; return 1; }

scan() { # $1=root-relatif ruang, $2=ruang
  find "$1" -type f 2>/dev/null | while read -r f; do
    h=$(readelf -h "$f" 2>/dev/null) || continue
    case "$h" in *ELF32*) ar=32;; *ELF64*) ar=64;; *) continue;; esac
    readelf -d "$f" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\].*/\1/p' | while read -r n; do
      is_llndk "$n" && continue
      v=${HAVE["$ar|ven|$n"]}; s=${HAVE["$ar|sys|$n"]}
      if [ -z "$v" ] && [ -z "$s" ]; then
        echo "HILANG|$n|$ar|${f#$P/}"
      elif [ "$2" = ven ] && [ -z "$v" ]; then
        echo "SYSONLY|$n|$ar|${f#$P/}"
      fi
    done
  done
}
{ scan "$P/vendor" ven; scan "$P/bin" sys; scan "$P/lib" sys; scan "$P/lib64" sys; } | sort -u
