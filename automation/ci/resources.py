"""Cross-worktree workstation slots; never terminates another session's work."""
from contextlib import contextmanager
import fcntl
from pathlib import Path
import subprocess
import time


@contextmanager
def flutter_slot():
    directory=Path.home()/'.cache/festapp-resources';directory.mkdir(parents=True,exist_ok=True)
    with (directory/'flutter.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        while 'flutter_tools.snapshot' in subprocess.check_output(['ps','-axo','args='],text=True):
            print('Waiting for the workstation Flutter task...',file=__import__('sys').stderr,flush=True);time.sleep(5)
        yield


if __name__ == '__main__':
    import sys
    with flutter_slot():
        sys.exit(subprocess.call(sys.argv[1:]))
