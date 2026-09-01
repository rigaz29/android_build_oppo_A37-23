#!/usr/bin/env bash
# patches.sh - periksa dan terapkan patches/ ke pohon LineageOS.
#
# Alasan skrip ini ada: `repo sync` mengembalikan setiap proyek ke revisi
# manifest dan MEMBUANG commit lokal tanpa peringatan. Pada 1 September 2026
# hal itu menghapus 47 dari 61 patch A37, dan kerusakannya baru ketahuan lewat
# lima kegagalan build berturut-turut yang seluruhnya salah didiagnosis.
#
# Urutan kerja yang benar:  repo sync  ->  patches.sh --apply  ->  build
#
# Pemakaian:
#   patches.sh                 periksa saja (default), keluar !=0 bila ada yang hilang
#   patches.sh --apply         terapkan yang belum terpasang
#   patches.sh --tree PATH     akar pohon (default: /root/los23)
#   patches.sh --patches PATH  direktori patch (default: letak skrip ini/../patches)
#   patches.sh --verbose       tampilkan tiap patch, bukan hanya ringkasan

set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=/root/los23
PATCHDIR=$SELF_DIR/../patches
MODE=check
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply|-a)   MODE=apply ;;
    --check|-c)   MODE=check ;;
    --tree)       TREE=$2; shift ;;
    --patches)    PATCHDIR=$2; shift ;;
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "argumen tak dikenal: $1" >&2; exit 2 ;;
  esac
  shift
done

TREE=$(cd "$TREE" 2>/dev/null && pwd) || { echo "pohon tidak ada: $TREE" >&2; exit 2; }
PATCHDIR=$(cd "$PATCHDIR" 2>/dev/null && pwd) || { echo "direktori patch tidak ada" >&2; exit 2; }

# --- peta direktori patch -> path proyek ---------------------------------
# Nama direktori patch memakai '_' sebagai pemisah, tetapi path proyek bisa
# memuat '-' (device/qcom/sepolicy-legacy, hardware/qcom-caf/bt). Jadi jangan
# tebak: bangun indeks dari proyek yang benar-benar ada, lalu cocokkan bentuk
# ternormalisasi ('/' dan '-' -> '_').
declare -A PROJ_OF
while IFS= read -r d; do
  p=${d#"$TREE"/}; p=${p%/.git}
  key=${p//\//_}; key=${key//-/_}
  PROJ_OF[$key]=$p
done < <(find "$TREE" -maxdepth 5 -name .git -not -path "$TREE/out/*" -not -path "$TREE/.repo/*" 2>/dev/null)

resolve() {                      # $1 = nama direktori patch
  local key=${1//-/_}
  [ -n "${PROJ_OF[$key]:-}" ] && { echo "${PROJ_OF[$key]}"; return 0; }
  return 1
}

# Patch yang diterapkan lewat merge 3-arah tidak lagi cocok untuk
# `apply --reverse --check` karena konteksnya berubah. Sinyal kedua: apakah
# subjek patch muncul sebagai commit di riwayat proyek.
subject_in_log() {               # $1 = repo, $2 = berkas patch
  local subj
  # Subjek panjang dilipat git format-patch ke baris lanjutan yang diawali
  # spasi (RFC 2822). Baca baris Subject BESERTA lanjutannya, lalu gabungkan.
  subj=$(awk '/^Subject:/ {
                sub(/^Subject:[ \t]*/, "")
                s = $0
                while ((getline line) > 0) {
                  if (line ~ /^[ \t]/) { sub(/^[ \t]+/, " ", line); s = s line }
                  else break
                }
                print s; exit
              }' "$2" 2>/dev/null | sed 's/^\[PATCH[^]]*\][ ]*//')
  [ -z "$subj" ] && return 1
  local log
  log=$(git -C "$1" log --format='%s' -400 2>/dev/null)
  # Here-string, bukan pipeline: dengan `set -o pipefail`, `grep -q` yang
  # keluar lebih awal membuat `git log` kena SIGPIPE, dan pipeline dianggap
  # gagal justru ketika kecocokan DITEMUKAN.
  grep -Fxq "$subj" <<< "$log"
}

# --- pemeriksaan ---------------------------------------------------------
n_ok=0 n_miss=0 n_drift=0 n_noproj=0 n_fail=0
miss_list=() drift_list=()

for dir in "$PATCHDIR"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  proj=$(resolve "$name") || { 
    shopt -s nullglob; cnt=("$dir"*.patch); shopt -u nullglob
    [ ${#cnt[@]} -gt 0 ] && { n_noproj=$((n_noproj+${#cnt[@]}))
      [ $VERBOSE -eq 1 ] && printf "  ?  proyek tak ditemukan untuk %s (%d patch)\n" "$name" "${#cnt[@]}"; }
    continue; }
  R=$TREE/$proj
  for p in "$dir"*.patch; do
    [ -e "$p" ] || continue
    base=$(basename "$p")
    if git -C "$R" apply --reverse --check "$p" >/dev/null 2>&1; then
      n_ok=$((n_ok+1))
      [ $VERBOSE -eq 1 ] && printf "  ok %-26s %s\n" "$proj" "${base:0:52}"
    elif git -C "$R" apply --check "$p" >/dev/null 2>&1; then
      # Patch terpasang bersih = isinya TIDAK ada di pohon. Ini diuji sebelum
      # riwayat: kalau patch pernah diterapkan lalu dibalik, subjeknya tetap
      # ada di log, dan memeriksa riwayat lebih dulu akan menutupi kenyataan.
      n_miss=$((n_miss+1)); miss_list+=("$proj|$p")
      [ $VERBOSE -eq 1 ] && printf "  -- %-26s %s\n" "$proj" "${base:0:52}"
    elif subject_in_log "$R" "$p"; then
      # Isi tidak bisa dipastikan lewat apply mana pun (konteks bergeser),
      # tetapi subjeknya ada di riwayat: dianggap terpasang lewat merge 3-arah.
      n_ok=$((n_ok+1))
      [ $VERBOSE -eq 1 ] && printf "  ok %-26s %s  (via riwayat)\n" "$proj" "${base:0:52}"
    else
      n_drift=$((n_drift+1)); drift_list+=("$proj|$p")
      [ $VERBOSE -eq 1 ] && printf "  ~~ %-26s %s\n" "$proj" "${base:0:52}"
    fi
  done
done

echo
echo "  pohon   : $TREE"
echo "  patch   : $PATCHDIR"
echo "  terpasang        : $n_ok"
echo "  BELUM terpasang  : $n_miss"
echo "  konteks bergeser : $n_drift   (sudah terpasang sebagian, atau perlu merge 3-arah)"
[ $n_noproj -gt 0 ] && echo "  proyek tak ada   : $n_noproj"

if [ "$MODE" = check ]; then
  if [ $n_miss -gt 0 ]; then
    echo
    echo "  Jalankan '$0 --apply' untuk memasangnya."
    exit 1
  fi
  [ $n_drift -gt 0 ] && exit 3
  exit 0
fi

# --- penerapan -----------------------------------------------------------
[ $n_miss -eq 0 ] && [ $n_drift -eq 0 ] && { echo; echo "  tidak ada yang perlu diterapkan."; exit 0; }

echo
echo "  === menerapkan ==="
applied=0
for item in "${miss_list[@]}" "${drift_list[@]}"; do
  proj=${item%%|*}; p=${item#*|}
  R=$TREE/$proj; base=$(basename "$p")
  # sudah terpasang di putaran ini (patch berurutan saling bergantung)?
  if git -C "$R" apply --reverse --check "$p" >/dev/null 2>&1; then
    printf "  ok(sudah) %-24s %s\n" "$proj" "${base:0:48}"; continue
  fi
  if git -C "$R" am --keep-non-patch "$p" >/dev/null 2>&1; then
    printf "  OK        %-24s %s\n" "$proj" "${base:0:48}"; applied=$((applied+1))
  else
    git -C "$R" am --abort >/dev/null 2>&1
    if git -C "$R" apply -3 "$p" >/dev/null 2>&1 && ! git -C "$R" diff --check >/dev/null 2>&1 || \
       git -C "$R" apply -3 "$p" >/dev/null 2>&1; then
      subj=$(grep -m1 '^Subject:' "$p" | sed 's/^Subject: \[PATCH[^]]*\] //')
      [ -z "$subj" ] && subj="terapkan $base"
      git -C "$R" add -A >/dev/null 2>&1
      git -C "$R" commit -q -m "$subj

Diterapkan dengan merge 3-arah oleh tools/patches.sh; konteks hulu bergeser.
Sumber: ${p#"$PATCHDIR"/}" >/dev/null 2>&1
      printf "  OK(3way)  %-24s %s\n" "$proj" "${base:0:48}"; applied=$((applied+1))
    else
      git -C "$R" checkout -- . >/dev/null 2>&1
      printf "  GAGAL     %-24s %s\n" "$proj" "${base:0:48}"; n_fail=$((n_fail+1))
    fi
  fi
done

echo
echo "  diterapkan: $applied    gagal: $n_fail"
[ $n_fail -gt 0 ] && { echo "  Yang gagal butuh penanganan tangan."; exit 1; }
exit 0
