// SPDX-License-Identifier: MIT
/*
 * try-bind: create a socket, bind() it, and report whether that was allowed.
 *
 *   try-bind inet                    TCP socket bound to 127.0.0.1, any port
 *   try-bind alg <type> <name>       AF_ALG socket, e.g.
 *                                      try-bind alg hash sha256
 *                                      try-bind alg aead 'gcm(aes)'
 *
 * Creating and binding an AF_ALG "aead" socket is the first step of the Copy
 * Fail exploit (CVE-2026-31431). This tool stops there: it performs no
 * cryptographic operation and is harmless.
 *
 * Exit status: 0 if bind() succeeded, 1 if it failed, 2 on usage errors.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <linux/if_alg.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int report(int fd, const struct sockaddr *addr, socklen_t len, const char *what)
{
	if (fd < 0) {
		printf("socket(%s): %s\n", what, strerror(errno));
		return 1;
	}
	if (bind(fd, addr, len) < 0) {
		printf("bind(%s): %s\n", what, strerror(errno));
		return 1;
	}
	printf("bind(%s): OK\n", what);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 2 && !strcmp(argv[1], "inet")) {
		struct sockaddr_in sin = {
			.sin_family = AF_INET,
			.sin_addr.s_addr = htonl(INADDR_LOOPBACK),
		};

		return report(socket(AF_INET, SOCK_STREAM, 0),
			      (struct sockaddr *)&sin, sizeof(sin), "AF_INET");
	}

	if (argc == 4 && !strcmp(argv[1], "alg")) {
		struct sockaddr_alg alg = { .salg_family = AF_ALG };
		char what[128];

		if (strlen(argv[2]) >= sizeof(alg.salg_type) ||
		    strlen(argv[3]) >= sizeof(alg.salg_name)) {
			fprintf(stderr, "type or name too long\n");
			return 2;
		}
		strcpy((char *)alg.salg_type, argv[2]);
		strcpy((char *)alg.salg_name, argv[3]);
		snprintf(what, sizeof(what), "AF_ALG %s %s", argv[2], argv[3]);

		return report(socket(AF_ALG, SOCK_SEQPACKET, 0),
			      (struct sockaddr *)&alg, sizeof(alg), what);
	}

	fprintf(stderr, "usage: %s inet | alg <type> <name>\n", argv[0]);
	return 2;
}
