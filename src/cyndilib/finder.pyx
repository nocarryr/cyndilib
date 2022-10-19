from cython.operator cimport dereference

import time
import threading

cdef class Source:
    # cdef NDIlib_source_t* ptr
    # cdef readonly str name

    @staticmethod
    cdef Source create(NDIlib_source_t* ptr, str name):
        cdef Source obj = Source()
        obj.ptr = ptr
        obj.name= name
        return obj

    def __repr__(self):
        return f'<Source: {self}>'
    def __str__(self):
        return self.name


cdef class Finder:
    # cdef NDIlib_find_instance_t find_p
    # cdef NDIlib_source_t* source_ptr
    # cdef readonly list source_names

    def __init__(self):
        # self.source_names = []
        self.lock = RLock()
        self.notify = Condition(self.lock)
        self.num_sources = 0
        self._initial_source_get = True
        self.build_finder()
        self.finder_thread = None
        self.finder_thread_running = Event()

    def __dealloc__(self):
        cdef NDIlib_find_instance_t p = self.find_p
        if p != NULL:
            self.find_p = NULL
            NDIlib_find_destroy(p)

    def open(self):
        assert self.finder_thread is None
        self.finder_thread = FinderThread(self)
        self.finder_thread.start()
        self.finder_thread_running.wait()

    def close(self):
        assert self.finder_thread is not None
        t = self.finder_thread
        self.finder_thread = None
        t.stop()
        t.join()

    cpdef get_source_names(self):
        # self.lock.lock()
        # cdef unique_lock[mutex]* lk = new unique_lock[mutex](self.lock)
        cdef list result = []
        cdef cpp_string cppname
        cdef bytes cname
        cdef str name
        with self.notify:
            for cppname in self.source_names:
                cname = cppname.c_str()
                name = cname.decode()
                result.append(name)
        # for pair in self.source_map:
        #     s = pair.first
        #     result.append(s)
        # self.lock.unlock()
        # del lk
        return result

    def iter_sources(self):
        # cdef list result = []
        cdef Source src
        # cdef Source src2
        cdef cpp_string cppname
        cdef bytes cname
        cdef str name
        cdef NDIlib_source_t* ptr
        with self.notify:
            for cppname in self.source_names:
                cname = cppname.c_str()
                name = cname.decode()
                ptr = self.source_map[cppname]
                src = Source.create(ptr, name)
                # src2 = self.get_source(src.name)
                # assert src2.name == src.name
                yield src
                # result.append(src)
        # return result

    cpdef Source get_source(self, str name):
        cdef cpp_string cname = name.encode()
        cdef NDIlib_source_t* ptr
        with self.notify:
            ptr = self._get_source(cname)
            if ptr is NULL:
                return None
            return Source.create(ptr, name)

    cdef NDIlib_source_t* _get_source(self, cpp_string name) nogil except *:
        # self.lock.lock()
        # cdef unique_lock[mutex]* lk = new unique_lock[mutex](self.lock)
        cdef NDIlib_source_t* result
        # cdef cpp_string cpp_name = name
        if self.source_map.count(name) > 0:
            result = NULL
        else:
            result = self.source_map[name]
        # self.lock.unlock()
        # del lk
        # return result

    def __len__(self):
        return self.num_sources

    def update_sources(self):
        with self.notify:
            self._update_sources()
            return self.get_source_names()

    cdef bint _update_sources(self) nogil except *:
        self.__notify_acquire()
        # self._lock.lock()
        cdef bint changed = False
        # cdef unique_lock[mutex]* lk = new unique_lock[mutex](self.lock)
        cdef uint32_t n_sources = 0
        cdef const NDIlib_source_t* src_p = NDIlib_find_get_current_sources(self.find_p, &n_sources)

        cdef size_t i
        self.source_names.clear()
        cdef const NDIlib_source_t* src_cn
        cdef NDIlib_source_t* src
        cdef cpp_string name
        cdef source_pair_t pair

        for i in range(n_sources):
            src_c = &(src_p[i])
            src = <NDIlib_source_t*> &(src_c)[0]
            name = cpp_string(src.p_ndi_name)
            if self.source_map.count(name) > 0:
                self.source_map.erase(name)
            else:
                changed = True
            pair = source_pair_t(name, src)
            self.source_map.insert(pair)
            self.source_names.push_back(name)

        self._initial_source_get = False
        # lk.unlock()
        # del lk
        # if changed:
        #     self.notify.notify_all()
        # self._lock.unlock()
        self.num_sources = n_sources
        if changed:
            self.__notify_notify_and_release()
        else:
            self.__notify_release()
        return changed

    def wait(self, timeout=None):
        if timeout is None:
            self._wait()
            return True
        return self._wait_timed(timeout)

    cdef void _wait(self) nogil except *:
        with gil:
            with self.notify:
                self.notify.wait()
        # cdef unique_lock[mutex]* lk = new unique_lock[mutex](self.lock)
        # self.notify.wait(dereference(lk))
        # # lk.unlock()
        # del lk

    cdef bint _wait_timed(self, float timeout) nogil except *:
        cdef bint notified
        with gil:
            with self.notify:
                notified = self.notify.wait(timeout)
        return notified

    def wait_for_sources(self, float timeout):
        cdef uint32_t timeout_ms = int(timeout * 1000)
        return self._wait_for_sources(timeout_ms)

    cdef bint _wait_for_sources(self, uint32_t timeout_ms) nogil except *:
        cdef bint changed
        # with gil:
        #     self.notify.acquire()
        if self._initial_source_get:
            changed = self._update_sources()
        else:
            changed = NDIlib_find_wait_for_sources(self.find_p, timeout_ms)
            if changed:
                self._update_sources()
        return changed

        # cdef unique_lock[mutex]* lk
        # if changed:
        #     self._update_sources()
        # else:
        #     lk = new unique_lock[mutex](self.lock)
        #     self.notify.notify_all()
        #     del lk

    cdef void build_finder(self) except *:
        cdef NDIlib_find_create_t find_settings = [True, NULL, NULL]
        self.find_p = NDIlib_find_create_v2(&find_settings)
        if self.find_p == NULL:
            raise MemoryError()

    cdef void __notify_acquire(self) nogil except *:
        with gil:
            self.notify.acquire()

    cdef void __notify_notify(self) nogil except *:
        with gil:
            self.notify.notify_all()

    cdef void __notify_notify_and_release(self) nogil except *:
        with gil:
            self.notify.notify_all()
            self.notify.release()

    cdef void __notify_release(self) nogil except *:
        with gil:
            self.notify.release()



cdef class FinderThreadWorker:
    cdef Finder finder
    cdef Event sleep_evt
    # cdef Event waiting
    cdef bint running
    cdef uint32_t timeout_ms

    def __init__(self, Finder finder, int timeout_ms=3000):
        self.finder = finder
        assert timeout_ms > 0
        self.timeout_ms = 1
        self.sleep_evt = Event()
        self.running = False
        # self.waiting = Event()
        print('FinderThreadWorker init')

    cdef void run(self) except *:
        cdef bint first_loop = True
        cdef bint changed
        self.running = True
        while self.running:
            if first_loop:
                self.finder.finder_thread_running.set()
                first_loop = False
            print('FinderThreadWorker waiting')
            # self.waiting.set()
            changed = self.finder._wait_for_sources(self.timeout_ms)
            print(f'FinderThreadWorker wait complete: changed={changed}')
            if self.finder.num_sources == 0:
                time.sleep(.1)
            else:
                self.sleep_evt.wait(5)
            # self.waiting.clear()
        self.finder.finder_thread_running.clear()
        self.finder = None

    def stop(self):
        self.running = False
        self.sleep_evt.set()


class FinderThread(threading.Thread):
    # cdef Finder finder
    def __init__(self, Finder finder):
        super().__init__()
        print('FinderThread init')
        self.finder = Finder
        self.worker = FinderThreadWorker(finder)
        self.running = False
        self.stopped = threading.Event()

    def run(self):
        print('FinderThread.run')
        cdef FinderThreadWorker worker = self.worker
        try:
            worker.run()
        except:
            import traceback
            traceback.print_exc()
        finally:
            self.finder = None
            self.stopped.set()

    def stop(self):
        self.worker.stop()
        self.stopped.wait()


def test():
    cdef Finder finder = Finder()
    cdef bint notified
    def wait_for_finder():
        if len(finder):
            print('finder has sources. thread exit')
            return
        print('waitng in thread')
        finder._wait_timed(10)
        print('thread wait complete')
    try:
        print('wait_t')
        wait_t = threading.Thread(target=wait_for_finder)
        wait_t.start()
        print('finder.open start')
        finder.open()
        print('finder.open exit')
        print('waiting for wait_t')
        # notified = finder._wait_timed(5)
        wait_t.join()
        print('wait complete')
        # time.sleep(.1)
        print('finder.source_names: ', finder.get_source_names())
    except:
        import traceback
        traceback.print_exc()
        raise
    finally:
        print('finder.close')
        # time.sleep(.1)
        finder.close()
        print('complete')
