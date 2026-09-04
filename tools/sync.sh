#!/usr/bin/env bash
# sync.sh - repo sync yang tidak diam-diam menghapus pekerjaan lokal.
#
# Alasan skrip ini ada: `repo sync --force-sync` mengembalikan setiap proyek ke
# revisi manifest dan MEMBUANG commit lokal tanpa peringatan. Pada 2 September
# 2026 hal itu menghapus commit kernel a03fd3c0 (f2fs F2FS_MAXQUOTAS) yang
# hanya ada di lokal, dan kehilangannya baru ketahuan berjam-jam kemudian --
# padahal tanpa commit itu /data gagal ter-mount dan ROM berhenti di
# bootanimation.
#
# patches/ melindungi apa yang ada di dalamnya. Skrip ini melindungi sisanya:
# ia mencadangkan SETIAP commit yang tidak ada di remote mana pun sebelum
# menyentuh apa pun, lalu melaporkan mana yang tidak tercakup patches/.
#
# Urutan kerja yang benar:  sync.sh  ->  patches.sh --apply  ->  build.sh
#
# Pemakaian:
#   sync.sh                    cadangkan, sync, lapor
#   sync.sh --dry-run          hanya laporkan apa yang akan hilang, jangan sync
#   sync.sh --tree PATH        akar pohon (default: /root/los23)
#   sync.sh --jobs N           paralelisme repo (default: nproc)
#   sync.sh --backup-dir PATH  tujuan cadangan (default: <tree>/.sync-backup)

set -uo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=/root/los23
PATCHDIR=$SELF_DIR/../patches
JOBS=$(nproc 2>/dev/null || echo 4)
BACKUP=
DRYRUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n)  DRYRUN=1 ;;
    --tree)        TREE=$2; shift ;;
    --jobs|-j)     JOBS=$2; shift ;;
    --backup-dir)  BACKUP=$2; shift ;;
    --patches)     PATCHDIR=$2; shift ;;
    -h|--help)     sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "argumen tak dikenal: $1" >&2; exit 2 ;;
  esac
  shift
done

TREE=$(cd "$TREE" 2>/dev/null && pwd) || { echo "pohon tidak ada: $TREE" >&2; exit 2; }
[ -d "$TREE/.repo" ] || { echo "bukan checkout repo: $TREE" >&2; exit 2; }
PATCHDIR=$(cd "$PATCHDIR" 2>/dev/null && pwd) || PATCHDIR=
: "${BACKUP:=$TREE/.sync-backup/$(date +%Y%m%d-%H%M%S)}"

cd "$TREE"

# --- daftar proyek --------------------------------------------------------
mapfile -t PROJECTS < <(find . -maxdepth 5 -name .git -not -path "./out/*" \
  -not -path "./.repo/*" 2>/dev/null | sed 's|/\.git$||; s|^\./||' | sort)
echo "  pohon    : $TREE"
echo "  proyek   : ${#PROJECTS[@]}"

# --- proyek mana yang punya commit yang TIDAK ada di remote mana pun ------
# Ini ukuran yang benar. Membandingkan terhadap refs/remotes/m/<branch> tidak
# cukup: ref itu basi untuk proyek yang revisinya baru diubah di local manifest,
# sehingga commit yang sudah aman ikut terhitung "lokal".
declare -A LOCAL_N
risky=0
for p in "${PROJECTS[@]}"; do
  n=$(git -C "$p" rev-list --count HEAD --not --remotes 2>/dev/null) || continue
  [ "${n:-0}" -gt 0 ] && { LOCAL_N[$p]=$n; risky=$((risky+n)); }
done
echo "  commit lokal (tidak ada di remote mana pun): $risky di ${#LOCAL_N[@]} proyek"

# --- mana yang tidak tercakup patches/ ------------------------------------
uncovered=()
if [ -n "$PATCHDIR" ]; then
  for p in "${!LOCAL_N[@]}"; do
    key=${p//\//_}; key=${key//-/_}
    found=
    for d in "$PATCHDIR"/*/; do
      [ -d "$d" ] || continue
      dk=$(basename "$d"); dk=${dk//-/_}
      [ "$dk" = "$key" ] && { found=1; break; }
    done
    [ -z "$found" ] && uncovered+=("$p (${LOCAL_N[$p]})")
  done
fi

if [ ${#uncovered[@]} -gt 0 ]; then
  echo
  echo "  ⚠ TIDAK TERCAKUP patches/ -- hanya cadangan yang menyelamatkannya:"
  printf '      %s\n' "${uncovered[@]}"
fi

# --- cadangkan ------------------------------------------------------------
if [ ${#LOCAL_N[@]} -gt 0 ]; then
  mkdir -p "$BACKUP"
  for p in "${!LOCAL_N[@]}"; do
    d=$BACKUP/${p//\//_}
    mkdir -p "$d"
    git -C "$p" format-patch -o "$d" HEAD --not --remotes >/dev/null 2>&1
    git -C "$p" rev-parse HEAD > "$d/.head" 2>/dev/null
  done
  echo
  echo "  cadangan : $BACKUP  ($(find "$BACKUP" -name '*.patch' 2>/dev/null | wc -l) patch)"
fi

if [ $DRYRUN -eq 1 ]; then
  echo
  echo "  --dry-run: tidak ada sync yang dijalankan."
  exit 0
fi

# --- snapshot HEAD sebelum ------------------------------------------------
before=$(mktemp)
for p in "${PROJECTS[@]}"; do
  printf '%s %s\n' "$(git -C "$p" rev-parse HEAD 2>/dev/null)" "$p"
done > "$before"

# --- sync -----------------------------------------------------------------
echo
echo "  === repo sync -c -j$JOBS --force-sync --no-clone-bundle --no-tags ==="
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
rc=$?
[ $rc -ne 0 ] && { echo "  repo sync GAGAL (rc=$rc). Cadangan tetap di $BACKUP" >&2; exit $rc; }

# --- apa yang berubah -----------------------------------------------------
after=$(mktemp)
for p in "${PROJECTS[@]}"; do
  printf '%s %s\n' "$(git -C "$p" rev-parse HEAD 2>/dev/null)" "$p"
done > "$after"
changed=$(join -j2 -o 0,1.1,2.1 <(sort -k2 "$before") <(sort -k2 "$after") \
          | awk '$2!=$3' | wc -l)
echo
echo "  proyek yang HEAD-nya berubah: $changed"
rm -f "$before" "$after"

# --- keadaan patches sesudah sync ----------------------------------------
if [ -x "$SELF_DIR/patches.sh" ]; then
  echo
  "$SELF_DIR/patches.sh" --tree "$TREE" ${PATCHDIR:+--patches "$PATCHDIR"} | tail -6
fi

echo
echo "  Berikutnya:  $SELF_DIR/patches.sh --apply"
[ ${#uncovered[@]} -gt 0 ] && \
  echo "  Lalu pulihkan sendiri yang tidak tercakup, dari $BACKUP"
exit 0
