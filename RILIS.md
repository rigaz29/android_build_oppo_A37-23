# Membangun ROM rilis — OPPO A37

Ditulis 3 September 2026, sesudah empat kegagalan berturut-turut. Isinya bukan
panduan umum penandatanganan LineageOS — itu sudah ada di wiki mereka. Yang
dicatat di sini hanya hal-hal yang **tidak ada di panduan mana pun** dan
menggigit di perangkat ini.

## Ringkasan

| yang diminta | hasilnya |
|---|---|
| ditandatangani kunci sendiri, tanpa password | bisa |
| adb insecure dicabut | bisa |
| varian `user` | **TIDAK BISA** — lihat §3 |

Yang akhirnya dipakai: **`userdebug` + kunci rilis + adb insecure dicabut**.
Praktisnya setara `user` dalam pengerasan adb (lihat §4), bedanya SELinux tetap
permissive.

---

## 1. Jebakan `testkey.x509.pem` — kunci ke-9 yang tidak disebut panduan mana pun

Panduan LineageOS menyuruh membuat kunci bernama `releasekey`, `platform`,
`shared`, `media`, `networkstack`, `sdk_sandbox`, `bluetooth`. Delapan kunci itu
benar semua, dan build tetap gagal di 69% setelah 1 jam 41 menit:

```
FAILED: .../plat_mac_permissions.xml/android_common/gen/mac_perms_keys.tmp
Path vendor/lineage-priv/keys/testkey.x509.pem does not exist or is not a file!
```

Sebabnya `system/sepolicy/private/keys.conf` meng-**hardcode** nama berkasnya
untuk tag `@RELEASE`, tanpa peduli nama kunci default yang kita pilih:

```
[@RELEASE]
ENG       : $DEFAULT_SYSTEM_DEV_CERTIFICATE/testkey.x509.pem
USER      : $DEFAULT_SYSTEM_DEV_CERTIFICATE/testkey.x509.pem
USERDEBUG : $DEFAULT_SYSTEM_DEV_CERTIFICATE/testkey.x509.pem
```

`insertkeys` menerima `DEFAULT_SYSTEM_DEV_CERTIFICATE` sebagai **direktori**,
lalu mencari `testkey.x509.pem` di dalamnya. Tujuh nama lain
(`platform`, `media`, `shared`, `sdk_sandbox`, `networkstack`, `nfc`) cocok
dengan yang dibuat panduan; hanya `testkey` yang tidak.

**Perbaikannya** — salin `releasekey` ke nama itu, dan itu juga semantiknya yang
benar: `build/make` tidak punya pemetaan khusus untuk nama `testkey`, ia
diperlakukan sebagai nama berkas biasa. Jadi modul apa pun yang merujuk
`testkey` ikut ditandatangani kunci rilis kita, bukan kunci uji AOSP.

```sh
cd vendor/lineage-priv/keys
cp releasekey.x509.pem testkey.x509.pem
cp releasekey.pk8      testkey.pk8
# verifikasi: sidik jari harus identik
openssl x509 -in releasekey.x509.pem -noout -fingerprint -sha256
openssl x509 -in testkey.x509.pem    -noout -fingerprint -sha256
```

Catatan: `@BLUETOOTH` sengaja menunjuk `build/make/target/product/security`
(kunci AOSP), bukan direktori kita. Itu bawaan `keys.conf`, bukan kekurangan.

### Membuat kunci tanpa password

```sh
SUBJ='/C=ID/ST=Jawa/L=Bandung/O=rigaz29/OU=A37/CN=rigaz29/emailAddress=...'
for k in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc; do
  printf '\n\n' | ./development/tools/make_key vendor/lineage-priv/keys/$k "$SUBJ"
done
cp vendor/lineage-priv/keys/releasekey.x509.pem vendor/lineage-priv/keys/testkey.x509.pem
cp vendor/lineage-priv/keys/releasekey.pk8      vendor/lineage-priv/keys/testkey.pk8
```

Bukti benar-benar tanpa password (PKCS#8 tak terenkripsi):

```sh
openssl pkcs8 -inform DER -nocrypt -in .../releasekey.pk8 -out /dev/null && echo OK
```

`vendor/lineage-priv/keys/keys.mk` cukup menyebut satu baris; tujuh sertifikat
lain dicari di direktori yang sama lewat
`$(dir $(DEFAULT_SYSTEM_DEV_CERTIFICATE))` — `build/make/core/config.mk:849`
dan `app_prebuilt_internal.mk:112`. Berkas ini di-include otomatis oleh
`vendor/lineage/config/common.mk:304`.

```make
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
PRODUCT_OTA_PUBLIC_KEYS := vendor/lineage-priv/keys/releasekey
```

---

## 2. `WITH_ADB_INSECURE` harus DIKOMENTARI, bukan disetel `false`

Sudah tercatat panjang di `device/oppo/A37/lineage_A37.mk`, diulang di sini
karena satu paket dengan build rilis: `vendor/lineage/config/common.mk:35`
memakai `ifdef`, dan `ifdef` di GNU Make bernilai benar untuk **nilai apa pun
yang tidak kosong**, termasuk string `"false"`.

---

## 3. Varian `user` TIDAK BISA boot — SELinux dipaksa enforcing

Build `user` selesai dan tertandatangani dengan benar, lalu **berhenti di logo
OPPO**. Bukan panic kernel: `dmesg-ramoops` nol `Kernel panic`, nol
`Unable to handle kernel`. Yang ada 9 denial, semuanya `permissive=0`:

```
avc: denied { read } comm="surfaceflinger"  tcontext=u:object_r:vendor_files  permissive=0
avc: denied { read } comm="audioserver"     vendor_default_prop               permissive=0
avc: denied { read } comm="perf@1.0-servic" system_prop                       permissive=0
```

Sebelumnya perangkat ini SELALU permissive lewat
`BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive` (`BoardConfig.mk:292`).
**Cmdline itu diabaikan di build `user`:**

```c
// system/core/init/selinux.cpp:113
bool IsEnforcing() {
    if (ALLOW_PERMISSIVE_SELINUX) { return StatusFromProperty() == SELINUX_ENFORCING; }
    return true;                       // varian user: SELALU enforcing
}
```

```
system/core/init/Android.bp:124      "-DALLOW_PERMISSIVE_SELINUX=0"   (bawaan)
system/core/init/Android.bp:140-147  debuggable: { ... "=1" }         (hanya userdebug/eng)
```

Jadi sepolicy A37 belum pernah lengkap untuk enforcing — ia hanya tidak pernah
ketahuan karena selalu permissive. **Ini pekerjaan yang belum dikerjakan**, dan
satu-satunya hal yang memisahkan ROM ini dari build `user` sungguhan.

Cara mengerjakannya nanti: build `userdebug`, `setenforce 1` di perangkat,
kumpulkan denial dengan `audit2allow`, tulis aturan, ulangi sampai bersih, baru
pindah ke `user`. Ketiga denial di atas adalah titik awalnya.

---

## 4. `userdebug` + adb insecure dicabut = `ro.debuggable=0`

Temuan menyenangkan yang tidak terduga. `vendor/lineage/config/common.mk:43`:

```make
# Set ro.debuggable=0 for userdebug
PRODUCT_NOT_DEBUGGABLE_IN_USERDEBUG := true
```

Baris itu aktif justru ketika adb insecure dimatikan. Hasil terukur di build
20260903_183402:

```
ro.build.type   = userdebug     ro.debuggable  = 0
ro.build.tags   = release-keys  ro.secure      = 1
ro.adb.secure   = 1
```

Artinya **`adb root` ikut tertutup** meski varian `userdebug`. Dalam hal
pengerasan adb, ROM ini setara `user`.

---

## 5. Jangan pakai `-j14` untuk build penuh di mesin ini

Pergantian varian memaksa SETIAP aplikasi menjalani ulang `dex`/`proguard`, dan
tiap R8 diluncurkan `-JXmx4096M`. Di mesin 11,7 GB, OOM killer membunuh `ninja`:

```
HeapHelper invoked oom-killer
oom-kill: ... task=ninja, pid=2447945
Out of memory: Killed process 2447945 (ninja) total-vm:9549656kB
```

Gejalanya menyesatkan: belasan `FAILED:` pada target Java yang tampak seperti
galat kompilasi. Yang membedakan — cari `error: action cancelled when ninja
exited`. Kalau itu yang muncul dan tidak ada galat kompilasi lain, buildnya
**dibunuh**, bukan gagal.

`-j4` untuk build penuh. `-j14` bawaan hanya aman untuk incremental, karena
sedikit aplikasi yang perlu di-dex ulang.

## 6. Ruang disk

Pengemasan OTA butuh ~10 GB transien di luar pohon build. Gagal begini:

```
zip2zip.go:103: write .../out/soong/.temp/tmp5vnkwno5: no space left on device
```

Perhatikan huruf kecil semua — filter monitor yang mencari `No space left`
akan melewatkannya.

Lever paling murah: `ccache -M 6G && ccache -c`. Tahap pengemasan tidak memakai
kompilasi sama sekali, jadi memangkas cache di titik ini tidak memperlambat
apa pun. Kembalikan dengan `ccache -M 20G` sesudah disk lega.

---

## Kunci itu rahasia

`vendor/lineage-priv/keys/` sudah diberi `.gitignore` berisi `*`. Cadangkan ke
tempat aman di luar pohon build:

- **Hilang** → tidak bisa lagi menerbitkan pembaruan yang mau dipasang
  perangkat yang sudah memakai ROM ini.
- **Bocor** → orang lain bisa menandatangani pembaruan yang akan diterima
  perangkat itu.
