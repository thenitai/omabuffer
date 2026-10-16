#!/usr/bin/python3
"""Read foreign clipboard data outside the shell, with hard per-request limits."""

import os
import selectors
import signal
import subprocess
import sys
import time

MAX_BYTES = 64 * 1024
DEADLINE_SECONDS = 2


class ClipboardError(Exception):
    def __init__(self, code):
        self.code = code


def read_clipboard(command):
    deadline = time.monotonic() + DEADLINE_SECONDS
    output = bytearray()
    total = 0
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             start_new_session=True)
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            selector.register(child.stderr, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ClipboardError(124)
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fileobj.fileno(), 4096)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    total += len(chunk)
                    if total > MAX_BYTES:
                        raise ClipboardError(125)
                    if key.fileobj is child.stdout:
                        output.extend(chunk)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ClipboardError(124)
            try:
                code = child.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                raise ClipboardError(124) from None
            if code != 0:
                raise ClipboardError(126)
        return output
    finally:
        # Also kill descendants that can outlive wl-paste and keep pipes open.
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.stdout.close()
        child.stderr.close()
        child.wait()


def cancel(_signum, _frame):
    raise ClipboardError(143)


def main(command=None):
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)
    if command is None:
        command = ["/usr/bin/wl-paste", "--no-newline", "--type", "text"]
        if sys.argv[1:] == ["primary"]:
            command.append("--primary")
        elif sys.argv[1:] != ["clipboard"]:
            return 126
    try:
        # No partial output or provider-supplied errors ever reach QML.
        data = read_clipboard(command)
        sys.stdout.buffer.write(data)
        return 0
    except ClipboardError as error:
        return error.code
    except OSError:
        return 126


if __name__ == "__main__":
    sys.exit(main())
