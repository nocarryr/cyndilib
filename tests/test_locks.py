import pytest
import threading
import time
import traceback

from cyndilib import locks

class WaitThread(threading.Thread):
    def __init__(self, condition, timeout=5):
        super().__init__()
        self.condition = condition
        self.timeout = timeout
        self.result = None
        self.finished = threading.Event()
        self.exception = None
    def run(self):
        try:
            with self.condition:
                self.result = self.condition.wait(self.timeout)
        except Exception as exc:
            traceback.print_exc()
            self.exception = exc
        finally:
            self.finished.set()

class NotifyThread(threading.Thread):
    def __init__(self, condition, sleep_time=1):
        super().__init__()
        self.condition = condition
        self.sleep_time = sleep_time
        self.finished = threading.Event()
        self.exception = None
    def run(self):
        time.sleep(self.sleep_time)
        try:
            with self.condition:
                self.condition.notify_all()
        except Exception as exc:
            traceback.print_exc()
            self.exception = exc
        finally:
            self.finished.set()

def test_conditions():
    condition = locks.Condition()
    wait_threads = [WaitThread(condition) for i in range(10)]
    # wt = WaitThread(condition)
    nt = NotifyThread(condition)
    for wt in wait_threads:
        wt.start()
    nt.start()
    try:
        nt.finished.wait()
        assert nt.exception is None
        for wt in wait_threads:
            wt.finished.wait()
            assert wt.exception is None
            assert wt.result is True
    finally:
        nt.join()
        for wt in wait_threads:
            wt.join()
