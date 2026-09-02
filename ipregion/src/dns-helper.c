// SPDX-License-Identifier: MIT

#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <curl/curl.h>
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define DNS_MIN_SIZE 12
#define DNS_MAX_SIZE 65535
#define EXIT_CONNECT_FAILED 7
#define EXIT_TIMEOUT 28
#define EXIT_IO_ERROR 74

static long long monotonic_ms(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0;

	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int wait_socket(int fd, short events, long long deadline)
{
	struct pollfd pfd = { .fd = fd, .events = events };

	for (;;) {
		long long remaining = deadline - monotonic_ms();
		int result;

		if (remaining <= 0)
			return 0;
		if (remaining > 2147483647)
			remaining = 2147483647;

		result = poll(&pfd, 1, (int)remaining);
		if (result > 0)
			return 1;
		if (result == 0)
			return 0;
		if (errno != EINTR)
			return -1;
	}
}

static int parse_number(const char *value, long minimum, long maximum, long *result)
{
	char *end = NULL;
	long parsed;

	errno = 0;
	parsed = strtol(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || parsed < minimum || parsed > maximum)
		return -1;

	*result = parsed;
	return 0;
}

static int read_request(const char *path, unsigned char **data, size_t *length)
{
	struct stat st;
	FILE *file;
	unsigned char *buffer;

	if (stat(path, &st) != 0 || st.st_size < DNS_MIN_SIZE || st.st_size > DNS_MAX_SIZE) {
		fprintf(stderr, "invalid DNS request file\n");
		return EXIT_IO_ERROR;
	}

	file = fopen(path, "rb");
	if (file == NULL) {
		fprintf(stderr, "cannot open DNS request: %s\n", strerror(errno));
		return EXIT_IO_ERROR;
	}

	buffer = malloc((size_t)st.st_size);
	if (buffer == NULL) {
		fclose(file);
		fprintf(stderr, "out of memory\n");
		return EXIT_IO_ERROR;
	}

	if (fread(buffer, 1, (size_t)st.st_size, file) != (size_t)st.st_size) {
		free(buffer);
		fclose(file);
		fprintf(stderr, "cannot read DNS request\n");
		return EXIT_IO_ERROR;
	}

	fclose(file);
	*data = buffer;
	*length = (size_t)st.st_size;
	return 0;
}

static int write_response(const char *path, const unsigned char *data, size_t length)
{
	FILE *file = fopen(path, "wb");
	int failed;

	if (file == NULL) {
		fprintf(stderr, "cannot open DNS response: %s\n", strerror(errno));
		return EXIT_IO_ERROR;
	}

	failed = fwrite(data, 1, length, file) != length;
	if (fclose(file) != 0)
		failed = 1;
	if (failed) {
		fprintf(stderr, "cannot write DNS response\n");
		return EXIT_IO_ERROR;
	}

	return 0;
}

static int socket_address(int family, const char *address, const char *interface,
		unsigned short port,
		struct sockaddr_storage *storage, socklen_t *length)
{
	memset(storage, 0, sizeof(*storage));

	if (family == AF_INET) {
		struct sockaddr_in *value = (struct sockaddr_in *)storage;
		value->sin_family = AF_INET;
		value->sin_port = htons(port);
		if (inet_pton(AF_INET, address, &value->sin_addr) != 1)
			return -1;
		*length = sizeof(*value);
		return 0;
	}

	if (family == AF_INET6) {
		struct sockaddr_in6 *value = (struct sockaddr_in6 *)storage;
		unsigned int scope_id;

		value->sin6_family = AF_INET6;
		value->sin6_port = htons(port);
		if (inet_pton(AF_INET6, address, &value->sin6_addr) != 1)
			return -1;
		if (IN6_IS_ADDR_LINKLOCAL(&value->sin6_addr)) {
			if (strcmp(interface, "-") == 0 || (scope_id = if_nametoindex(interface)) == 0)
				return -1;
			value->sin6_scope_id = scope_id;
		}
		*length = sizeof(*value);
		return 0;
	}

	return -1;
}

static int connect_socket(int fd, const struct sockaddr *address, socklen_t length,
		long long deadline)
{
	int error = 0;
	socklen_t error_length = sizeof(error);
	int result = connect(fd, address, length);

	if (result == 0)
		return 0;
	if (errno != EINPROGRESS) {
		fprintf(stderr, "connection failed: %s\n", strerror(errno));
		return EXIT_CONNECT_FAILED;
	}

	result = wait_socket(fd, POLLOUT, deadline);
	if (result == 0) {
		fprintf(stderr, "connection timeout\n");
		return EXIT_TIMEOUT;
	}
	if (result < 0 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &error_length) != 0) {
		fprintf(stderr, "connection failed: %s\n", strerror(errno));
		return EXIT_CONNECT_FAILED;
	}
	if (error != 0) {
		fprintf(stderr, "connection failed: %s\n", strerror(error));
		return EXIT_CONNECT_FAILED;
	}

	return 0;
}

static int send_all(int fd, const unsigned char *data, size_t length, long long deadline)
{
	size_t offset = 0;

	while (offset < length) {
		ssize_t written = send(fd, data + offset, length - offset, MSG_NOSIGNAL);
		if (written > 0) {
			offset += (size_t)written;
			continue;
		}
		if (written < 0 && errno == EINTR)
			continue;
		if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
			int ready = wait_socket(fd, POLLOUT, deadline);
			if (ready > 0)
				continue;
			if (ready == 0) {
				fprintf(stderr, "send timeout\n");
				return EXIT_TIMEOUT;
			}
		}

		fprintf(stderr, "send failed: %s\n", strerror(errno));
		return EXIT_IO_ERROR;
	}

	return 0;
}

static int receive_exact(int fd, unsigned char *data, size_t length, long long deadline)
{
	size_t offset = 0;

	while (offset < length) {
		ssize_t received = recv(fd, data + offset, length - offset, 0);
		if (received > 0) {
			offset += (size_t)received;
			continue;
		}
		if (received == 0) {
			fprintf(stderr, "connection closed before the DNS response completed\n");
			return EXIT_IO_ERROR;
		}
		if (errno == EINTR)
			continue;
		if (errno == EAGAIN || errno == EWOULDBLOCK) {
			int ready = wait_socket(fd, POLLIN, deadline);
			if (ready > 0)
				continue;
			if (ready == 0) {
				fprintf(stderr, "receive timeout\n");
				return EXIT_TIMEOUT;
			}
		}

		fprintf(stderr, "receive failed: %s\n", strerror(errno));
		return EXIT_IO_ERROR;
	}

	return 0;
}

static int plain_probe(const char *transport, int family, const char *endpoint,
		const char *source, const char *interface, unsigned short port, long timeout_ms,
		const unsigned char *request, size_t request_length,
		unsigned char **response, size_t *response_length)
{
	struct sockaddr_storage remote_address;
	struct sockaddr_storage source_address;
	socklen_t remote_length;
	socklen_t source_length;
	int type = strcmp(transport, "udp") == 0 ? SOCK_DGRAM : SOCK_STREAM;
	long long deadline = monotonic_ms() + timeout_ms;
	unsigned char *buffer = NULL;
	int fd;
	int result;

	if (socket_address(family, endpoint, interface, port, &remote_address, &remote_length) != 0) {
		fprintf(stderr, "invalid endpoint address\n");
		return EXIT_CONNECT_FAILED;
	}

	fd = socket(family, type, 0);
	if (fd < 0) {
		fprintf(stderr, "socket failed: %s\n", strerror(errno));
		return EXIT_CONNECT_FAILED;
	}

	if (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK) < 0) {
		fprintf(stderr, "cannot configure socket: %s\n", strerror(errno));
		close(fd);
		return EXIT_IO_ERROR;
	}

	if (strcmp(source, "-") != 0) {
		if (socket_address(family, source, interface, 0, &source_address, &source_length) != 0 ||
				bind(fd, (struct sockaddr *)&source_address, source_length) != 0) {
			fprintf(stderr, "source bind failed: %s\n", strerror(errno));
			close(fd);
			return EXIT_CONNECT_FAILED;
		}
	}

	result = connect_socket(fd, (struct sockaddr *)&remote_address, remote_length, deadline);
	if (result != 0) {
		close(fd);
		return result;
	}

	if (type == SOCK_DGRAM) {
		ssize_t received;

		result = send_all(fd, request, request_length, deadline);
		if (result != 0) {
			close(fd);
			return result;
		}

		result = wait_socket(fd, POLLIN, deadline);
		if (result <= 0) {
			fprintf(stderr, result == 0 ? "receive timeout\n" : "receive failed: %s\n",
				result == 0 ? "" : strerror(errno));
			close(fd);
			return result == 0 ? EXIT_TIMEOUT : EXIT_IO_ERROR;
		}

		buffer = malloc(DNS_MAX_SIZE);
		if (buffer == NULL) {
			close(fd);
			return EXIT_IO_ERROR;
		}
		received = recv(fd, buffer, DNS_MAX_SIZE, 0);
		if (received < DNS_MIN_SIZE) {
			fprintf(stderr, "invalid UDP DNS response\n");
			free(buffer);
			close(fd);
			return EXIT_IO_ERROR;
		}

		*response = buffer;
		*response_length = (size_t)received;
		close(fd);
		return 0;
	}

	buffer = malloc(request_length + 2);
	if (buffer == NULL) {
		close(fd);
		return EXIT_IO_ERROR;
	}
	buffer[0] = (unsigned char)(request_length >> 8);
	buffer[1] = (unsigned char)(request_length & 0xff);
	memcpy(buffer + 2, request, request_length);
	result = send_all(fd, buffer, request_length + 2, deadline);
	free(buffer);
	if (result != 0) {
		close(fd);
		return result;
	}

	{
		unsigned char size_bytes[2];
		size_t length;

		result = receive_exact(fd, size_bytes, sizeof(size_bytes), deadline);
		if (result != 0) {
			close(fd);
			return result;
		}
		length = ((size_t)size_bytes[0] << 8) | size_bytes[1];
		if (length < DNS_MIN_SIZE) {
			fprintf(stderr, "invalid TCP DNS response length\n");
			close(fd);
			return EXIT_IO_ERROR;
		}

		buffer = malloc(length);
		if (buffer == NULL) {
			close(fd);
			return EXIT_IO_ERROR;
		}
		result = receive_exact(fd, buffer, length, deadline);
		if (result != 0) {
			free(buffer);
			close(fd);
			return result;
		}
		*response = buffer;
		*response_length = length;
	}

	close(fd);
	return 0;
}

static int curl_wait(CURL *curl, short events, long long deadline)
{
	curl_socket_t socket_fd = CURL_SOCKET_BAD;

	if (curl_easy_getinfo(curl, CURLINFO_ACTIVESOCKET, &socket_fd) != CURLE_OK ||
			socket_fd == CURL_SOCKET_BAD)
		return -1;

	return wait_socket((int)socket_fd, events, deadline);
}

static int curl_send_all(CURL *curl, const unsigned char *data, size_t length,
		long long deadline)
{
	size_t offset = 0;

	while (offset < length) {
		size_t written = 0;
		if (monotonic_ms() >= deadline) {
			fprintf(stderr, "DoT send timeout\n");
			return EXIT_TIMEOUT;
		}
		CURLcode code = curl_easy_send(curl, data + offset, length - offset, &written);

		if (code == CURLE_OK && written > 0) {
			offset += written;
			continue;
		}
		if (code == CURLE_OK) {
			fprintf(stderr, "DoT connection closed while sending the DNS request\n");
			return EXIT_IO_ERROR;
		}
		if (code == CURLE_AGAIN) {
			int ready = curl_wait(curl, POLLOUT, deadline);
			if (ready > 0)
				continue;
			if (ready == 0) {
				fprintf(stderr, "DoT send timeout\n");
				return EXIT_TIMEOUT;
			}
			fprintf(stderr, "DoT socket wait failed\n");
			return EXIT_IO_ERROR;
		}

		fprintf(stderr, "DoT send failed: %s\n", curl_easy_strerror(code));
		return code > 0 && code < 126 ? (int)code : EXIT_IO_ERROR;
	}

	return 0;
}

static int curl_receive_exact(CURL *curl, unsigned char *data, size_t length,
		long long deadline)
{
	size_t offset = 0;

	while (offset < length) {
		size_t received = 0;
		if (monotonic_ms() >= deadline) {
			fprintf(stderr, "DoT receive timeout\n");
			return EXIT_TIMEOUT;
		}
		CURLcode code = curl_easy_recv(curl, data + offset, length - offset, &received);

		if (code == CURLE_OK && received > 0) {
			offset += received;
			continue;
		}
		if (code == CURLE_OK) {
			fprintf(stderr, "DoT connection closed before the DNS response completed\n");
			return EXIT_IO_ERROR;
		}
		if (code == CURLE_AGAIN) {
			int ready = curl_wait(curl, POLLIN, deadline);
			if (ready > 0)
				continue;
			if (ready == 0) {
				fprintf(stderr, "DoT receive timeout\n");
				return EXIT_TIMEOUT;
			}
			fprintf(stderr, "DoT socket wait failed\n");
			return EXIT_IO_ERROR;
		}

		fprintf(stderr, "DoT receive failed: %s\n", curl_easy_strerror(code));
		return code > 0 && code < 126 ? (int)code : EXIT_IO_ERROR;
	}

	return 0;
}

static int dot_probe(int family, const char *endpoint, const char *source,
		unsigned short port, long timeout_ms, const char *hostname,
		const unsigned char *request, size_t request_length,
		unsigned char **response, size_t *response_length)
{
	char url[512];
	char resolve_entry[768];
	char source_entry[INET6_ADDRSTRLEN + 6];
	const char *ca_bundle = getenv("IPREGION_CA_BUNDLE");
	struct curl_slist *resolve = NULL;
	unsigned char *frame = NULL;
	unsigned char size_bytes[2];
	long long deadline;
	CURL *curl;
	CURLcode code;
	int result = EXIT_IO_ERROR;

#define SETOPT(option, value) do { \
	code = curl_easy_setopt(curl, option, value); \
	if (code != CURLE_OK) { \
		fprintf(stderr, "cannot configure DoT transport: %s\n", curl_easy_strerror(code)); \
		result = code > 0 && code < 126 ? (int)code : EXIT_IO_ERROR; \
		goto cleanup; \
	} \
} while (0)

	if (snprintf(url, sizeof(url), "https://%s:%u/", hostname, port) >= (int)sizeof(url) ||
			snprintf(resolve_entry, sizeof(resolve_entry), strchr(endpoint, ':') != NULL ?
			"%s:%u:[%s]" : "%s:%u:%s", hostname, port, endpoint) >= (int)sizeof(resolve_entry)) {
		fprintf(stderr, "DoT endpoint is too long\n");
		return EXIT_CONNECT_FAILED;
	}

	curl = curl_easy_init();
	if (curl == NULL) {
		fprintf(stderr, "cannot initialize libcurl\n");
		return EXIT_IO_ERROR;
	}

	resolve = curl_slist_append(resolve, resolve_entry);
	if (resolve == NULL)
		goto cleanup;

	SETOPT(CURLOPT_URL, url);
	SETOPT(CURLOPT_CONNECT_ONLY, 1L);
	SETOPT(CURLOPT_RESOLVE, resolve);
	SETOPT(CURLOPT_PROXY, "");
	SETOPT(CURLOPT_NOSIGNAL, 1L);
	SETOPT(CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
	SETOPT(CURLOPT_TIMEOUT_MS, timeout_ms);
	SETOPT(CURLOPT_SSL_VERIFYPEER, 1L);
	SETOPT(CURLOPT_SSL_VERIFYHOST, 2L);
	SETOPT(CURLOPT_IPRESOLVE, family == AF_INET6 ? CURL_IPRESOLVE_V6 : CURL_IPRESOLVE_V4);

	if (ca_bundle == NULL || *ca_bundle == '\0') {
		if (access("/etc/ssl/certs/ca-certificates.crt", R_OK) == 0)
			ca_bundle = "/etc/ssl/certs/ca-certificates.crt";
		else if (access("/etc/ssl/cert.pem", R_OK) == 0)
			ca_bundle = "/etc/ssl/cert.pem";
	}
	if (ca_bundle != NULL && *ca_bundle != '\0')
		SETOPT(CURLOPT_CAINFO, ca_bundle);

	if (strcmp(source, "-") != 0) {
		if (snprintf(source_entry, sizeof(source_entry), "host!%s", source) >= (int)sizeof(source_entry)) {
			result = EXIT_CONNECT_FAILED;
			goto cleanup;
		}
		SETOPT(CURLOPT_INTERFACE, source_entry);
	}

	deadline = monotonic_ms() + timeout_ms;
	code = curl_easy_perform(curl);
	if (code != CURLE_OK) {
		fprintf(stderr, "DoT connection failed: %s\n", curl_easy_strerror(code));
		result = code > 0 && code < 126 ? (int)code : EXIT_CONNECT_FAILED;
		goto cleanup;
	}

	frame = malloc(request_length + 2);
	if (frame == NULL)
		goto cleanup;
	frame[0] = (unsigned char)(request_length >> 8);
	frame[1] = (unsigned char)(request_length & 0xff);
	memcpy(frame + 2, request, request_length);

	result = curl_send_all(curl, frame, request_length + 2, deadline);
	free(frame);
	frame = NULL;
	if (result == 0)
		result = curl_receive_exact(curl, size_bytes, sizeof(size_bytes), deadline);
	if (result == 0) {
		size_t length = ((size_t)size_bytes[0] << 8) | size_bytes[1];
		if (length < DNS_MIN_SIZE) {
			fprintf(stderr, "invalid DoT DNS response length\n");
			result = EXIT_IO_ERROR;
		}
		else {
			frame = malloc(length);
			if (frame == NULL)
				result = EXIT_IO_ERROR;
			else {
				result = curl_receive_exact(curl, frame, length, deadline);
				if (result == 0) {
					*response = frame;
					*response_length = length;
					frame = NULL;
				}
			}
		}
	}

cleanup:
	free(frame);
	curl_slist_free_all(resolve);
	curl_easy_cleanup(curl);

#undef SETOPT

	return result;
}

static void usage(const char *program)
{
	fprintf(stderr, "usage: %s udp|tcp|dot 4|6 endpoint source|- port timeout-ms request response interface|- tls-hostname|-\n", program);
}

int main(int argc, char **argv)
{
	const char *transport;
	const char *hostname;
	unsigned char *request = NULL;
	unsigned char *response = NULL;
	size_t request_length = 0;
	size_t response_length = 0;
	long port_value;
	long timeout_ms;
	int family;
	int result;

	if (argc != 11) {
		usage(argv[0]);
		return 2;
	}

	transport = argv[1];
	hostname = argv[10];
	if (strcmp(transport, "udp") != 0 && strcmp(transport, "tcp") != 0 &&
			strcmp(transport, "dot") != 0) {
		usage(argv[0]);
		return 2;
	}
	if (strcmp(argv[2], "4") == 0)
		family = AF_INET;
	else if (strcmp(argv[2], "6") == 0)
		family = AF_INET6;
	else {
		usage(argv[0]);
		return 2;
	}
	if (parse_number(argv[5], 1, 65535, &port_value) != 0 ||
			parse_number(argv[6], 100, 600000, &timeout_ms) != 0 ||
			(strcmp(transport, "dot") == 0 && strcmp(hostname, "-") == 0)) {
		usage(argv[0]);
		return 2;
	}

	unlink(argv[8]);
	result = read_request(argv[7], &request, &request_length);
	if (result != 0)
		return result;

	if (strcmp(transport, "dot") == 0) {
		if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
			free(request);
			return EXIT_IO_ERROR;
		}
		result = dot_probe(family, argv[3], argv[4], (unsigned short)port_value,
			timeout_ms, hostname, request, request_length, &response, &response_length);
		curl_global_cleanup();
	}
	else {
		result = plain_probe(transport, family, argv[3], argv[4], argv[9],
			(unsigned short)port_value, timeout_ms, request, request_length,
			&response, &response_length);
	}

	free(request);
	if (result == 0)
		result = write_response(argv[8], response, response_length);
	free(response);
	return result;
}
