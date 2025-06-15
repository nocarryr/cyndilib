import time
from cyndilib.finder import Finder
from cyndilib.receiver import Receiver
from cyndilib.wrapper.ndi_recv import RecvColorFormat, RecvBandwidth


def main():
    finder = Finder()
    finder.open()
    for i in range(5):
        has_source = finder.wait_for_sources(timeout=5)
        if has_source:
            break
        print(f"No sources detected ({i})")

    source_names = finder.get_source_names()
    print(source_names)

    source = source_names[0]
    source_obj = finder.get_source(source)
    print(source_obj)

    receiver = Receiver(
        color_format=RecvColorFormat.fastest,
        bandwidth=RecvBandwidth.metadata_only,
        recv_name="obs_ndi_ptz"
    )

    receiver.set_source(source_obj)
    time.sleep(1.5)

    if not receiver.is_ptz_supported():
        raise f"The NDI '{source}' does not indicate PTZ support."

    ptz = receiver.ptz

    print("pan to center, tilt to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(5)

    print("zoom to min")
    ptz.set_zoom_level(0)
    time.sleep(2)

    print("zoom to max")
    ptz.set_zoom_level(1)
    time.sleep(2)

    print("zoom to min")
    ptz.set_zoom_level(0)
    time.sleep(2)

    print("zoom in")
    for _ in range(0, 100):
        time.sleep(0.01)
        ptz.zoom(1)

    print("zoom out")
    for _ in range(0, 100):
        time.sleep(0.01)
        ptz.zoom(-0.5)

    print("zoom to min")
    ptz.set_zoom_level(0)
    time.sleep(2)

    print("pan to left, tilt to middle")
    ptz.set_pan_and_tilt_values(-0.5, 0.0)
    time.sleep(5)

    print("pan to center, tilt to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(5)

    print("pan to right, tilt to middle")
    ptz.set_pan_and_tilt_values(0.5, 0.0)
    time.sleep(5)

    print("pan to center, tilt to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(5)

    print("pan to center, title to down")
    ptz.set_pan_and_tilt_values(0.0, -1.0)
    time.sleep(5)

    print("pan to center, tilt to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(5)

    print("pan to center, tilt to up")
    ptz.set_pan_and_tilt_values(0.0, 1.0)
    time.sleep(5)

    print("continuously pan left")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.pan(.5)

    print("continuously pan right")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.pan(-.5)

    print("pan to center, title to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(2)

    print("continuously tilt down")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.tilt(-.5)

    print("continuously tilt up")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.tilt(.5)

    print("pan to center, title to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(2)

    print("store as preset to slot 10")
    ptz.store_preset(10)

    print("move")
    ptz.set_pan_and_tilt_values(.5, .5)
    time.sleep(2)

    print("store as preset to slot 11")
    ptz.store_preset(11)

    print("recall preset in slot 10")
    ptz.recall_preset(10, 1.0)
    time.sleep(2)

    print("recall preset in slot 11")
    ptz.recall_preset(11, 1.0)
    time.sleep(2)

    print("recall preset in slot 10, slower")
    ptz.recall_preset(10, 0.5)
    time.sleep(4)

    print("recall preset in slot 11, slowest")
    ptz.recall_preset(11, 0.0)
    time.sleep(6)

    print("pan to center, title to middle")
    ptz.set_pan_and_tilt_values(0.0, 0.0)
    time.sleep(2)

    print("trigger autofocus")
    ptz.autofocus()
    time.sleep(1)

    print("focus min (infinity)")
    ptz.set_focus(0.0)
    time.sleep(2)

    print("focus max")
    ptz.set_focus(1.0)
    time.sleep(2)

    print("decrease focus")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.focus(-.5)

    print("increase focus")
    for _ in range(0, 100):
        time.sleep(0.05)
        ptz.focus(.5)

    print("trigger autofocus")
    ptz.autofocus()
    time.sleep(1)

    print("trigger auto white-balance")
    ptz.white_balance_auto()
    time.sleep(2)

    print("set indoor white-balance")
    ptz.white_balance_indoor()
    time.sleep(2)

    print("set outdoor white-balance")
    ptz.white_balance_outdoor()
    time.sleep(2)

    print("trigger oneshot white-balance")
    ptz.white_balance_oneshot()
    time.sleep(2)

    print("set white-balance to min")
    ptz.set_white_balance(0.0, 0.0)
    time.sleep(2)

    print("set white-balance to max")
    ptz.set_white_balance(1.0, 1.0)
    time.sleep(2)

    print("trigger auto white-balance")
    ptz.white_balance_auto()
    time.sleep(2)

    print("(re-)enable auto exposure")
    ptz.exposure_auto()
    time.sleep(2)

    print("set exposure to dark")
    ptz.set_exposure_coarse(0.0)
    time.sleep(2)

    print("set exposure to bright")
    ptz.set_exposure_coarse(1.0)
    time.sleep(2)

    print("set exposure to dark (fine adjustment)")
    ptz.set_exposure_fine(.0, .0, .0)
    time.sleep(2)

    print("set exposure to bright (fine adjustment)")
    ptz.set_exposure_fine(1.0, 1.0, 1.0)
    time.sleep(2)

    print("re-enable auto exposure")
    ptz.exposure_auto()
    time.sleep(2)


if __name__ == "__main__":
    main()
