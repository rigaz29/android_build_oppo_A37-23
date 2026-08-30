# algbench — ukur cipher kernel lewat AF_ALG

Membandingkan throughput cipher **di CPU perangkat**, bukan dari angka publik.
Dibuat untuk memutuskan apakah Adiantum sepadan menggantikan AES-256-XTS pada
A37 (Cortex-A53 tanpa ARMv8 Crypto Extensions).

## Pakai

Salin ke `external/algbench/` di pohon LineageOS, lalu:

```
m algbench
adb push out/target/product/A37/system/bin/algbench /data/local/tmp/
adb shell chmod 755 /data/local/tmp/algbench
adb shell /data/local/tmp/algbench 6      # 6 detik per algoritma
```

Butuh `CONFIG_CRYPTO_USER_API_SKCIPHER=y` di kernel.

## Hasil di A37 (30 Agustus 2026)

Blok 4096 byte, sama dengan unit fscrypt:

```
xts(aes)                  30.90 MB/s   driver xts-aes-neon   prio 200
adiantum(xchacha12,aes)   47.67 MB/s   seluruhnya C generik  prio 100
rasio                     1.54x
```

**Angka Adiantum adalah lantai, bukan langit-langit.** Ia berjalan sebagai
`adiantum(xchacha12-generic, aes-generic, nhpoly1305-generic)` sementara AES
memakai NEON. Tidak ada NEON ChaCha untuk arm64 di rujukan mana pun; a6010
hanya punya `arch/arm/crypto/chacha-neon-*` (ARM 32-bit) dan
`arch/arm64/crypto/` mereka identik dengan kita.

Dua syscall per blok membebani kedua cipher sama besar, jadi overhead AF_ALG
**menekan** rasio, bukan menggelembungkannya. Perkiraan kasar rasio sebenarnya
sekitar 1,7x.

## Catatan pemakaian

- `xts(aes)` butuh kunci **64 byte** (dua kunci 256-bit) dan IV 16 byte.
- `adiantum(xchacha12,aes)` butuh kunci 32 byte dan IV **32 byte**.
- Adiantum adalah *template*: ia tidak muncul di `/proc/crypto` sampai
  diinstansiasi. Kalau mencari bukti keberadaannya sebelum diukur, cari blok
  penyusunnya (`xchacha12`, `nhpoly1305`, `poly1305`).
