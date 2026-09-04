#!/usr/bin/env bash
# build.sh - membangun ROM, dengan penjaga untuk empat jebakan yang sudah
# terbukti memakan waktu berjam-jam di mesin ini.
#
# 1. OOM saat build penuh. Pergantian varian memaksa SETIAP aplikasi men-dex
#    ulang, tiap R8 diluncurkan -JXmx4096M, dan OOM killer menghabisi ninja.
#    Gejalanya menyamar: belasan "FAILED:" pada target Java yang tampak seperti
#    galat kompilasi. Pembedanya "error: action cancelled when ninja exited".
#    Skrip ini mendeteksi pergantian varian dan menurunkan -j sendiri.
#
# 2. Kunci penandatanganan tidak lengkap. keys.conf meng-hardcode
#    testkey.x509.pem untuk tag @RELEASE, nama yang tidak dibuat panduan
#    LineageOS mana pun. Ketahuan setelah 1 jam 41 menit build. Diperiksa di
#    depan sekarang.
#
# 3. Ruang disk. Pengemasan OTA butuh ~10 GB transien; pesan gagalnya huruf
#    kecil semua ("no space left on device").
#
# 4. Pembungkus shell. Kalau `grep` atau `find` adalah fungsi shell (mis. di
#    dalam sesi agen), envsetup.sh salah mengurai dan lunch gagal dengan
#    "No release config set for target". Skrip ini membuangnya lebih dulu.
#
# Urutan kerja yang benar:  sync.sh  ->  patches.sh --apply  ->  build.sh
#
# Pemakaian:
#   build.sh                       userdebug, incremental
#   build.sh --variant user        varian user (CATATAN: SELinux dipaksa
#                                  enforcing; sepolicy A37 belum siap)
#   build.sh --jobs N              paksa -j
#   build.sh --target TARGET       default: bacon
#   build.sh --foreground          jangan lepas ke latar
#   build.sh --check-only          hanya periksa kesiapan, jangan bangun
#   build.sh --skip-checks         lewati pemeriksaan pra-build

set -uo pipefail
unset -f grep find 2>/dev/null || true          # jebakan 4

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=/root/los23
DEVICE=A37
RELEASE=bp4a
VARIANT=userdebug
TARGET=bacon
JOBS=
LOG=
FOREGROUND=0
CHECKS=1
CHECKONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)        TREE=$2; shift ;;
    --variant)     VARIANT=$2; shift ;;
    --release)     RELEASE=$2; shift ;;
    --device)      DEVICE=$2; shift ;;
    --target)      TARGET=$2; shift ;;
    --jobs|-j)     JOBS=$2; shift ;;
    --log)         LOG=$2; shift ;;
    --foreground)  FOREGROUND=1 ;;
    --check-only)  CHECKONLY=1 ;;
    --skip-checks) CHECKS=0 ;;
    -h|--help)     sed -n '2,36p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "argumen tak dikenal: $1" >&2; exit 2 ;;
  esac
  shift
done

TREE=$(cd "$TREE" 2>/dev/null && pwd) || { echo "pohon tidak ada: $TREE" >&2; exit 2; }
COMBO="lineage_${DEVICE}-${RELEASE}-${VARIANT}"
: "${LOG:=$TREE/build-${VARIANT}-$(date +%Y%m%d-%H%M%S).log}"
STATE=$TREE/.build-last-variant

cd "$TREE"
echo "  pohon    : $TREE"
echo "  lunch    : $COMBO"
echo "  target   : $TARGET"

# --- jebakan 1: pilih -j berdasarkan apakah ini build penuh --------------
LAST=$(cat "$STATE" 2>/dev/null || echo "")
FULL=0
[ "$LAST" != "$COMBO" ] && FULL=1
RAM_GB=$(awk '/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 8)
if [ -z "$JOBS" ]; then
  if [ $FULL -eq 1 ]; then
    # R8 boleh menuntut 4 GB per proses. Sisakan ~3 GB untuk sisanya.
    JOBS=$(( (RAM_GB - 3) / 2 )); [ "$JOBS" -lt 2 ] && JOBS=2
    n=$(nproc 2>/dev/null || echo 4); [ "$JOBS" -gt "$n" ] && JOBS=$n
    echo "  -j       : $JOBS  (build PENUH: varian berubah dari '${LAST:-tidak ada}')"
    echo "             RAM ${RAM_GB} GB; tiap R8 boleh minta 4 GB, jadi -j dibatasi."
  else
    JOBS=$(( $(nproc 2>/dev/null || echo 4) + 2 ))
    echo "  -j       : $JOBS  (incremental)"
  fi
else
  echo "  -j       : $JOBS  (dipaksa lewat --jobs)"
fi

# --- pemeriksaan pra-build -----------------------------------------------
if [ $CHECKS -eq 1 ]; then
  fail=0

  # jebakan 3: ruang disk
  avail=$(df -BG --output=avail "$TREE" 2>/dev/null | tail -1 | tr -dc 0-9)
  echo "  disk     : ${avail:-?} GB bebas"
  if [ -n "$avail" ] && [ "$avail" -lt 12 ]; then
    echo "             ⚠ pengemasan OTA butuh ~10 GB transien."
    echo "               Lever termurah: ccache -M 6G && ccache -c"
    [ "$avail" -lt 6 ] && fail=1
  fi

  # jebakan 2: kelengkapan kunci penandatanganan
  KEYS=$TREE/vendor/lineage-priv/keys
  if [ -f "$KEYS/keys.mk" ]; then
    miss=()
    for k in releasekey testkey platform shared media networkstack sdk_sandbox nfc; do
      [ -f "$KEYS/$k.x509.pem" ] || miss+=("$k")
    done
    if [ ${#miss[@]} -gt 0 ]; then
      echo "  kunci    : ⚠ HILANG: ${miss[*]}"
      echo "             keys.conf meng-hardcode testkey.x509.pem untuk tag"
      echo "             @RELEASE. Salin dari releasekey kalau itu yang kurang:"
      echo "               cp $KEYS/releasekey.x509.pem $KEYS/testkey.x509.pem"
      echo "               cp $KEYS/releasekey.pk8      $KEYS/testkey.pk8"
      fail=1
    else
      echo "  kunci    : lengkap (8), build akan release-keys"
    fi
  else
    echo "  kunci    : tidak ada keys.mk -- build akan test-keys"
  fi

  # patches terpasang?
  if [ -x "$SELF_DIR/patches.sh" ]; then
    out=$("$SELF_DIR/patches.sh" --tree "$TREE" 2>/dev/null | tail -6)
    ada=$(printf '%s' "$out" | awk '/BELUM terpasang/{print $NF}')
    echo "  patches  : ${ada:-?} belum terpasang"
    if [ -n "$ada" ] && [ "$ada" != "0" ]; then
      echo "             Jalankan dulu: $SELF_DIR/patches.sh --apply"
      fail=1
    fi
  fi

  # varian user: peringatan yang sudah terbukti
  if [ "$VARIANT" = "user" ]; then
    echo
    echo "  ⚠ Varian 'user' MEMAKSA SELinux enforcing -- androidboot.selinux="
    echo "    permissive di cmdline DIABAIKAN (system/core/init/selinux.cpp:113)."
    echo "    Percobaan 3 September 2026 tidak bisa boot: surfaceflinger,"
    echo "    audioserver dan perf HAL diblokir. Lihat RILIS.md §3."
  fi

  [ $fail -ne 0 ] && { echo; echo "  Ada yang harus dibereskan dulu. --skip-checks untuk memaksa."; exit 1; }
fi

if [ $CHECKONLY -eq 1 ]; then
  echo
  echo "  --check-only: siap dibangun, tidak ada build yang dijalankan."
  exit 0
fi

# --- jalankan -------------------------------------------------------------
echo
echo "  log      : $LOG"
RUN="export BUILD_USERNAME=\${BUILD_USERNAME:-\$(id -un)} \
BUILD_HOSTNAME=\${BUILD_HOSTNAME:-\$(hostname)} \
USE_CCACHE=1 CCACHE_EXEC=\$(command -v ccache) CCACHE_DIR=\${CCACHE_DIR:-\$HOME/.ccache}; \
cd '$TREE'; source build/envsetup.sh >/dev/null 2>&1; \
lunch '$COMBO' >/dev/null 2>&1 || { echo 'lunch GAGAL: $COMBO'; exit 2; }; \
mka '$TARGET' -j$JOBS; rc=\$?; echo \"EXIT=\$rc\"; \
[ \$rc -eq 0 ] && echo '$COMBO' > '$STATE'; exit \$rc"

if [ $FOREGROUND -eq 1 ]; then
  bash -c "$RUN" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

setsid nohup bash -c "$RUN > '$LOG' 2>&1" >/dev/null 2>&1 </dev/null &
disown
echo "  dilepas ke latar (setsid), tahan terhadap sesi yang tertutup."
echo
echo "  Pantau  : tail -f $LOG"
echo "  Selesai : grep -a '^EXIT=' $LOG"
echo "  Gagal?  : grep -aiE 'no space left|action cancelled when ninja exited' $LOG"
echo "            baris kedua berarti build DIBUNUH (OOM), bukan gagal kompilasi."
exit 0
