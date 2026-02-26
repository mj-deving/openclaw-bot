#!/usr/bin/env python3
"""Watch PAI pipeline results directory and trigger notifications.

Uses inotify via ctypes (zero external dependencies) to detect new result
files, then calls pai-result-notify.sh to drain all un-notified results.

Runs as a systemd user service (Type=simple). Debounces rapid events to
batch multiple near-simultaneous results into one notification pass.

This replaces a systemd path unit, which cannot watch /var/lib/ directories
from user-level systemd instances due to namespace restrictions.
"""

import ctypes
import ctypes.util
import os
import select
import subprocess
import sys
import time

RESULTS_DIR = b"/var/lib/pai-pipeline/results"
NOTIFY_SCRIPT = os.path.expanduser("~/scripts/pai-result-notify.sh")
DEBOUNCE_SECONDS = 2

# inotify constants
IN_CREATE = 0x00000100
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_DELETE_SELF = 0x00000400
IN_IGNORED = 0x00008000


def main():
    libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)

    fd = libc.inotify_init()
    if fd < 0:
        print(f"inotify_init failed: errno={ctypes.get_errno()}", file=sys.stderr)
        sys.exit(1)

    wd = libc.inotify_add_watch(
        fd, RESULTS_DIR, IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE_SELF
    )
    if wd < 0:
        errno = ctypes.get_errno()
        print(
            f"inotify_add_watch failed: errno={errno} ({os.strerror(errno)})",
            file=sys.stderr,
        )
        os.close(fd)
        sys.exit(1)

    print(f"Watching {RESULTS_DIR.decode()} for new results (debounce={DEBOUNCE_SECONDS}s)")
    sys.stdout.flush()

    try:
        while True:
            # Block until an event arrives
            r, _, _ = select.select([fd], [], [])
            if not r:
                continue

            # Read and drain initial event(s)
            data = os.read(fd, 65536)
            if not data:
                continue

            # Check for directory deletion (watch invalidated)
            # Each event is 16 bytes header + variable name length
            offset = 0
            while offset < len(data):
                # struct inotify_event: wd(4) + mask(4) + cookie(4) + len(4) + name(len)
                if offset + 16 > len(data):
                    break
                wd_ev, mask, cookie, name_len = (
                    int.from_bytes(data[offset : offset + 4], "little"),
                    int.from_bytes(data[offset + 4 : offset + 8], "little"),
                    int.from_bytes(data[offset + 8 : offset + 12], "little"),
                    int.from_bytes(data[offset + 12 : offset + 16], "little"),
                )
                offset += 16 + name_len

                if mask & (IN_DELETE_SELF | IN_IGNORED):
                    print("Watch directory deleted, exiting", file=sys.stderr)
                    sys.exit(1)

            # Debounce: wait for more events to accumulate
            time.sleep(DEBOUNCE_SECONDS)

            # Drain any events that arrived during debounce window
            while select.select([fd], [], [], 0)[0]:
                os.read(fd, 65536)

            # Run notification script
            print(f"Change detected, running notification script")
            sys.stdout.flush()
            result = subprocess.run([NOTIFY_SCRIPT], capture_output=False)
            if result.returncode != 0:
                print(
                    f"Notification script exited with code {result.returncode}",
                    file=sys.stderr,
                )

    except KeyboardInterrupt:
        print("Shutting down watcher")
    finally:
        libc.inotify_rm_watch(fd, wd)
        os.close(fd)


if __name__ == "__main__":
    main()
