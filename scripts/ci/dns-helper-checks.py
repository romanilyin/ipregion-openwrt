#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import os
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


HELPER = Path(sys.argv[1]).resolve()
QUERY = struct.pack("!HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0) + b"\x07example\x03com\x00\x00\x01\x00\x01"
RESPONSE = QUERY[:2] + struct.pack("!H", 0x8180) + QUERY[4:]


def start_server(transport, context=None, response=RESPONSE, close_early=False, stall=0):
    sock_type = socket.SOCK_DGRAM if transport == "udp" else socket.SOCK_STREAM
    server = socket.socket(socket.AF_INET, sock_type)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    if transport != "udp":
        server.listen(1)

    def serve():
        try:
            if transport == "udp":
                data, peer = server.recvfrom(65535)
                assert data == QUERY
                server.sendto(RESPONSE, peer)
                return

            connection, _ = server.accept()
            try:
                if context is not None:
                    connection = context.wrap_socket(connection, server_side=True)
                if close_early:
                    return
                size = struct.unpack("!H", receive_exact(connection, 2))[0]
                assert receive_exact(connection, size) == QUERY
                if stall:
                    time.sleep(stall)
                connection.sendall(struct.pack("!H", len(response)) + response)
            finally:
                connection.close()
        except (OSError, ssl.SSLError, RuntimeError):
            pass
        finally:
            server.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    return server.getsockname()[1], thread


def receive_exact(connection, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = connection.recv(remaining)
        if not chunk:
            raise RuntimeError("connection closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def run_probe(directory, transport, port, hostname="-", env=None, expected=0,
              source="-", timeout_ms=2000):
    request = directory / f"{transport}.query"
    response = directory / f"{transport}.response"
    request.write_bytes(QUERY)
    command = [
        str(HELPER), transport, "4", "127.0.0.1", source, str(port), str(timeout_ms),
        str(request), str(response), "-", hostname,
    ]
    result = subprocess.run(command, env=env, text=True, capture_output=True, check=False)
    expected_codes = expected if isinstance(expected, tuple) else (expected,)
    assert result.returncode in expected_codes, (command, result.returncode, result.stderr)
    if result.returncode == 0:
        assert response.read_bytes() == RESPONSE
    else:
        assert not response.exists()
    return result


def create_tls_context(directory, server_names):
    certificate = directory / "certificate.pem"
    key = directory / "key.pem"
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
        "-keyout", str(key), "-out", str(certificate),
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, key)
    context.set_servername_callback(lambda _socket, name, _context: server_names.append(name))
    return context, certificate


with tempfile.TemporaryDirectory(prefix="ipregion-dns-helper-") as tmp:
    directory = Path(tmp)
    server_names = []

    for transport in ("udp", "tcp"):
        port, thread = start_server(transport)
        run_probe(directory, transport, port)
        thread.join(timeout=3)
        assert not thread.is_alive()

    port, thread = start_server("udp")
    run_probe(directory, "udp", port, source="127.0.0.1")
    thread.join(timeout=3)
    assert not thread.is_alive()

    tls_context, certificate = create_tls_context(directory, server_names)
    tls_env = os.environ.copy()
    tls_env["IPREGION_CA_BUNDLE"] = str(certificate)
    port, thread = start_server("dot", tls_context)
    run_probe(directory, "dot", port, "localhost", tls_env)
    thread.join(timeout=3)
    assert not thread.is_alive()
    assert server_names[-1] == "localhost"

    untrusted_env = os.environ.copy()
    untrusted_env.pop("IPREGION_CA_BUNDLE", None)
    port, thread = start_server("dot", tls_context)
    run_probe(directory, "dot", port, "localhost", untrusted_env, expected=60)
    thread.join(timeout=3)
    assert not thread.is_alive()

    port, thread = start_server("dot", tls_context)
    run_probe(directory, "dot", port, "wrong.example", tls_env, expected=60)
    thread.join(timeout=3)
    assert not thread.is_alive()

    port, thread = start_server("dot", tls_context, close_early=True)
    run_probe(directory, "dot", port, "localhost", tls_env, expected=(56, 74))
    thread.join(timeout=3)
    assert not thread.is_alive()

    port, thread = start_server("tcp", response=b"short")
    run_probe(directory, "tcp", port, expected=74)
    thread.join(timeout=3)
    assert not thread.is_alive()

    port, thread = start_server("tcp", stall=1)
    started = time.monotonic()
    run_probe(directory, "tcp", port, expected=28, timeout_ms=200)
    assert time.monotonic() - started < 0.8
    thread.join(timeout=3)
    assert not thread.is_alive()

print("native DNS helper checks OK")
