
from kivy.app import App
from kivy.graphics.texture import Texture
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.widget import Widget
from kivy.uix.dropdown import DropDown
from kivy.uix.button import Button
from kivy.lang import Builder
from kivy.properties import (
    ObjectProperty, BooleanProperty, StringProperty,
    NumericProperty, ListProperty, OptionProperty, AliasProperty,
)
from kivy.clock import Clock, mainthread

from cyndilib.wrapper.ndi_recv import RecvColorFormat, RecvBandwidth
from cyndilib.finder import Finder, Source
from cyndilib.receiver import Receiver, ReceiveFrameType
from cyndilib.video_frame import VideoFrameSync
from cyndilib.audio_frame import AudioFrameSync
from cyndilib.framesync import FrameSyncThread

Builder.load_string('''
<MainWidget>:
    orientation: 'vertical'

    BoxLayout:
        orientation: 'horizontal'
        size_hint_y: .05
        Label:
            text: f'FPS: {root.fps:.2f}'
            height: self.texture_size[1]
        Label:
            text: f'rFPS: {root.rfps:.2f}'
            height: self.texture_size[1]

    VideoWidgetContainer


<VideoWidgetContainer@FloatLayout>:
    VideoWidget:
        size_hint_x: 1
        size_hint_y: None
        pos_hint: {'center_x':.5, 'center_y':.5}
        height: self.width * 0.5625

<VideoWidget>:
    app: app
    canvas.before:
        Color:
            rgba: [.5,.5,.5,1]
        Line:
            rectangle: (self.x, self.y, self.width, self.height)
    canvas:
        Color:
            rgba: (1,1,1,1)
        Rectangle:
            texture: self.blank_texture if self.vid_texture is None else self.vid_texture
            pos: self.pos
            size: self.size
    VideoWidgetHeader:
        id: header
        x: root.x
        top: root.top
        width: root.width
        height: 20



<VideoWidgetHeader>:
    app: app
    orientation: 'horizontal'
    size_hint_x: .2
    source_name: app.source_name
    canvas.before:
        Color:
            rgba: (0,0,0,.5)
        Rectangle:
            pos: self.pos
            size: self.size
    Button:
        id: dropDownBtn
        size_hint_x: .4
        text: 'Source'
        on_release:
            if root.source_dropdown.is_open: root.source_dropdown.dismiss()
            else: root.source_dropdown.open(self)
    Label:
        size_hint_x: .3
        text: '' if not app.source_name else app.source_name
    Label:
        size_hint_x: .3
        text: 'Connected' if app.connected else 'Not Connected'

''')

class MainWidget(BoxLayout):
    fps = NumericProperty(0.0)
    rfps = NumericProperty(0.0)
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        Clock.schedule_interval(self.update_fps, .01)

    def update_fps(self, *args):
        self.fps = Clock.get_fps()
        self.rfps = Clock.get_rfps()

class VideoWidgetHeader(BoxLayout):
    app = ObjectProperty(None)
    source_dropdown = ObjectProperty(None)
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.source_dropdown = SourceDropDown()
        self.source_dropdown.bind(on_select=self.on_dropdown_select)

    def on_app(self, *args):
        self.source_dropdown.app = self.app

    def on_dropdown_select(self, instance, data):
        if data == 'None':
            data = None
        self.app.source_to_connect_to = data


class SourceDropDown(DropDown):
    app = ObjectProperty(None)

    def _get_is_open(self):
        return self.attach_to is not None
    is_open = AliasProperty(_get_is_open, bind=['attach_to'])

    def on_app(self, instance, value):
        self._update_sources()
        self.app.bind(ndi_source_names=self._update_sources)

    def _update_sources(self, *args, **kwargs):
        self.clear_widgets()
        names = self.app.ndi_source_names
        names = [None] + self.app.ndi_source_names
        for name in names:
            _name = name if name else 'None'
            btn = Button(text=_name, size_hint_y=None, height=44, font_size='9sp')
            btn.bind(on_release=lambda btn: self.select(btn.text))
            self.add_widget(btn)


class VideoWidget(Widget):
    app = ObjectProperty(None)
    blank_texture = ObjectProperty(None)
    vid_texture = ObjectProperty(None, allownone=True)
    video_frame_rate = ObjectProperty(None)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Make a blank texture to display when not connected
        self.blank_texture = Texture.create(size=(16,9), colorfmt='luminance')
        bfr = [10 for _ in range(16*9)]
        self.blank_texture.blit_buffer(bytes(bfr), colorfmt='luminance', bufferfmt='ubyte')
        self._video_update_event = None

    def on_app(self, instance, value):
        self.video_frame_rate = self.app.video_frame.get_frame_rate()
        self.app.bind(connected=self.on_app_connected, on_stop=self.close)

    def on_app_connected(self, instance, value):
        if value:
            self.start_video_frame_events()
        else:
            self.stop_video_frame_events()
            self.vid_texture = None

    def close(self, *args, **kwargs):
        self.stop_video_frame_events()

    def start_video_frame_events(self, *args):
        # Schedule the `update_video_frame` method to be called at
        # an interval matching the video_frame's frame rate
        self.stop_video_frame_events()
        target_fps = self.video_frame_rate
        interval = float(1 / target_fps)
        evt = Clock.schedule_interval(self.update_video_frame, interval)
        self._video_update_event = evt

    def stop_video_frame_events(self, *args):
        if self._video_update_event is not None:
            Clock.unschedule(self._video_update_event)
            self._video_update_event = None

    def update_video_frame(self, *args):
        if not self.app.connected:
            return
        # Read a video frame using the FrameSync
        # This method will keep the frame timing as close as possible
        # to their actual timestamps
        self.app.receiver.frame_sync.capture_video()
        vf = self.app.video_frame
        if min(vf.xres, vf.yres) == 0:
            # We haven't received an actual frame yet, do nothing
            return
        # Update the `vid_texture`
        self.set_texture_from_video_frame()

        # Check the frame's current frame rate and restart with the
        # proper interval if it's changed
        fr = vf.get_frame_rate()
        if fr != self.video_frame_rate:
            self.video_frame_rate = fr

    def set_texture_from_video_frame(self):
        vf = self.app.video_frame
        tex = self.vid_texture
        if tex is None:
            tex = self.vid_texture = Texture.create(size=(vf.xres, vf.yres))
            tex.flip_vertical()

        # Get the current frame data as a 1-d array of uint8 (RGBA)
        arr = vf.get_array()
        tex.blit_buffer(arr, colorfmt='rgba', bufferfmt='ubyte')
        self.canvas.ask_update()

    def on_video_frame_rate(self, instance, value):
        if self._video_update_event is not None:
            self.start_video_frame_events()


class TestApp(App):
    finder = ObjectProperty(None, allownone=True)
    ndi_source_names = ListProperty([])
    source_name = StringProperty(None, allownone=True)
    source_to_connect_to = StringProperty(None, allownone=True)
    source = ObjectProperty(None, allownone=True)
    connected = BooleanProperty(False)
    video_frame = ObjectProperty(None)
    video_frame_rate = ObjectProperty(None)
    audio_frame = ObjectProperty(None)

    def build(self):
        # Create and start a Finder with a callback
        self.finder = Finder()
        self.finder.set_change_callback(self._on_finder_change)
        self.finder.open()

        # Create a Receiver without a source
        self.receiver = Receiver(
            color_format=RecvColorFormat.RGBX_RGBA,
            bandwidth=RecvBandwidth.highest,
        )
        self.video_frame = VideoFrameSync()
        self.audio_frame = AudioFrameSync()

        # Add the video/audio frames to the receiver's FrameSync
        self.receiver.frame_sync.set_video_frame(self.video_frame)
        self.receiver.frame_sync.set_audio_frame(self.audio_frame)

        self._recv_connect_event = Clock.schedule_interval(self.check_connected, .1)

        # Now build te rest of the widget tree
        w = None
        try:
            w = MainWidget()
        except:
            self.finder.close()
            raise
        return w

    def on_stop(self, *args, **kwargs):
        if self.finder is not None:
            self.finder.close()

    @mainthread
    def _on_finder_change(self):
        if self.finder is None:
            return
        self.ndi_source_names = self.finder.get_source_names()
        self.update_source()

    def on_source_to_connect_to(self, *args):
        self.update_source()

    def update_source(self, *args):
        # Look for a source matching the `source_to_connect_to` string
        if self.source_to_connect_to is None:
            self.source = None
        else:
            with self.finder.notify:
                self.source = self.finder.get_source(self.source_to_connect_to)

    def on_source(self, *args):
        # Set the receiver's source
        # (can be a valid source object or None to disconnect)
        self.receiver.set_source(self.source)
        if self.source is None:
            self.source_name = None
        else:
            self.source_name = self.source.name

    def check_connected(self, *args):
        self.connected = self.receiver.is_connected()

if __name__ == '__main__':
    TestApp().run()
