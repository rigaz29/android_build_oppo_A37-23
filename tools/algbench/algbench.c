/*
 * algbench - ukur throughput cipher lewat AF_ALG di perangkat.
 *
 * Membandingkan xts(aes) (AES-256-XTS, yang dipakai FBE sekarang) melawan
 * adiantum(xchacha12,aes) pada CPU yang sama, dengan ukuran blok yang sama
 * dengan sektor fscrypt (4096 byte).
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <sys/socket.h>
#include <linux/if_alg.h>

#ifndef SOL_ALG
#define SOL_ALG 279
#endif

#define BLK   4096          /* sama dengan ukuran blok fscrypt */
#define MB    (1024 * 1024)

static double now_sec(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int bench(const char *alg, int keylen, int ivlen, double seconds,
		 double *out_mbs)
{
	struct sockaddr_alg sa;
	unsigned char key[64], buf[BLK];
	char cbuf[CMSG_SPACE(4) + CMSG_SPACE(sizeof(struct af_alg_iv) + 32)];
	struct iovec iov;
	struct msghdr msg;
	struct cmsghdr *cmsg;
	struct af_alg_iv *ivm;
	int tfmfd, opfd, i;
	long long bytes = 0;
	double t0, el;

	memset(&sa, 0, sizeof(sa));
	sa.salg_family = AF_ALG;
	strcpy((char *)sa.salg_type, "skcipher");
	strncpy((char *)sa.salg_name, alg, sizeof(sa.salg_name) - 1);

	tfmfd = socket(AF_ALG, SOCK_SEQPACKET, 0);
	if (tfmfd < 0) { printf("  %-26s socket: %s\n", alg, strerror(errno)); return -1; }

	if (bind(tfmfd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
		printf("  %-26s TIDAK TERSEDIA (%s)\n", alg, strerror(errno));
		close(tfmfd); return -1;
	}

	for (i = 0; i < keylen; i++) key[i] = (unsigned char)(i * 7 + 1);
	if (setsockopt(tfmfd, SOL_ALG, ALG_SET_KEY, key, keylen) < 0) {
		printf("  %-26s set_key(%d): %s\n", alg, keylen, strerror(errno));
		close(tfmfd); return -1;
	}

	opfd = accept(tfmfd, NULL, 0);
	if (opfd < 0) { printf("  %-26s accept: %s\n", alg, strerror(errno)); close(tfmfd); return -1; }

	memset(buf, 0xa5, sizeof(buf));
	memset(cbuf, 0, sizeof(cbuf));
	memset(&msg, 0, sizeof(msg));
	msg.msg_control = cbuf;
	msg.msg_controllen = CMSG_SPACE(4) + CMSG_SPACE(sizeof(struct af_alg_iv) + ivlen);

	cmsg = CMSG_FIRSTHDR(&msg);
	cmsg->cmsg_level = SOL_ALG;
	cmsg->cmsg_type = ALG_SET_OP;
	cmsg->cmsg_len = CMSG_LEN(4);
	*(unsigned int *)CMSG_DATA(cmsg) = ALG_OP_ENCRYPT;

	cmsg = CMSG_NXTHDR(&msg, cmsg);
	cmsg->cmsg_level = SOL_ALG;
	cmsg->cmsg_type = ALG_SET_IV;
	cmsg->cmsg_len = CMSG_LEN(sizeof(struct af_alg_iv) + ivlen);
	ivm = (struct af_alg_iv *)CMSG_DATA(cmsg);
	ivm->ivlen = ivlen;
	memset(ivm->iv, 0, ivlen);

	iov.iov_base = buf;
	iov.iov_len = BLK;
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;

	t0 = now_sec();
	while (now_sec() - t0 < seconds) {
		if (sendmsg(opfd, &msg, 0) < 0) {
			printf("  %-26s sendmsg: %s\n", alg, strerror(errno));
			close(opfd); close(tfmfd); return -1;
		}
		if (read(opfd, buf, BLK) != BLK) {
			printf("  %-26s read: %s\n", alg, strerror(errno));
			close(opfd); close(tfmfd); return -1;
		}
		bytes += BLK;
	}
	el = now_sec() - t0;
	close(opfd); close(tfmfd);

	*out_mbs = (double)bytes / MB / el;
	printf("  %-26s %8.2f MB/s   (%lld blok %d B dalam %.1f dtk)\n",
	       alg, *out_mbs, bytes / BLK, BLK, el);
	return 0;
}

int main(int argc, char **argv)
{
	double secs = (argc > 1) ? atof(argv[1]) : 5.0;
	double aes = 0, adi = 0;

	printf("Ukur enkripsi blok %d byte, %.0f detik per algoritma\n\n", BLK, secs);

	/* AES-256-XTS: kunci 64 byte (dua kunci 256-bit), IV 16 byte */
	bench("xts(aes)", 64, 16, secs, &aes);
	/* Adiantum: kunci 32 byte, IV 32 byte */
	bench("adiantum(xchacha12,aes)", 32, 32, secs, &adi);

	if (aes > 0 && adi > 0)
		printf("\n  Adiantum %.2fx dibanding AES-256-XTS\n", adi / aes);
	return 0;
}
