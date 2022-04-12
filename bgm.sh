#!/usr/bin/env python

import os
import sys
import subprocess
import threading
import random
import math
import socket
import atexit

MUSIC_FOLDER = "/media/fat/music"

# special files to play on mister boot
BOOT_NAMES = {"_boot.mp3", "_boot.ogg"}
# ratio of total tracks to keep in play history
HISTORY_SIZE = 0.2

SOCKET_FILE = "/tmp/bgm.sock"
SCRIPTS_FOLDER = "/media/fat/Scripts"
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"
CORENAME_FILE = "/tmp/CORENAME"
MENU_CORE = "MENU"
DEBUG = False


def debug(msg: str):
    if DEBUG:
        print(msg)


def wait_core_change():
    if not os.path.exists(CORENAME_FILE):
        return "MENU"

    args = ("inotifywait", "-e", "modify", CORENAME_FILE)
    subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with open(CORENAME_FILE) as f:
        return str(f.read())


class Player:
    player = None
    end_playlist = threading.Event()
    history = []

    def is_mp3(self, filename: str):
        return filename.lower().endswith(".mp3")

    def is_ogg(self, filename: str):
        return filename.lower().endswith(".ogg")

    def is_valid_file(self, filename: str):
        return self.is_mp3(filename) or self.is_ogg(filename)

    def play_mp3(self, filename: str):
        args = ("mpg123", "--no-control", filename)
        self.player = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        # workaround for a strange issue with mpg123 on MiSTer
        # some mp3 files will play but cause mpg123 to hang at the end
        # this may be fixed when MiSTer ships with a newer version
        while self.player is not None:
            line = self.player.stdout.readline()
            if "finished." in line.decode():
                self.stop()
                break

    def play_ogg(self, filename: str):
        args = ("ogg123", filename)
        self.player = subprocess.Popen(
            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        self.player.wait()

    def all_tracks(self):
        tracks = []

        for track in os.listdir(MUSIC_FOLDER):
            if track in BOOT_NAMES:
                continue
            elif self.is_valid_file(track):
                tracks.append(track)

        return tracks

    def total_tracks(self):
        return len(self.all_tracks())

    def add_history(self, filename: str):
        history_size = math.floor(self.total_tracks() * HISTORY_SIZE)
        if history_size < 1:
            return
        while len(self.history) > history_size:
            self.history.pop(0)
        self.history.append(filename)

    def stop(self):
        if self.player is not None:
            self.player.kill()
            self.player = None

    def play(self, filename: str):
        self.stop()

        if self.is_valid_file(filename):
            self.add_history(filename)
            debug("Now playing: {}".format(filename))
        else:
            return

        if self.is_mp3(filename):
            self.play_mp3(filename)
        elif self.is_ogg(filename):
            self.play_ogg(filename)

    def random_track(self):
        tracks = self.all_tracks()
        if len(tracks) == 0:
            return

        def random_index():
            return random.randint(0, len(tracks) - 1)

        index = random_index()
        # avoid replaying recent tracks
        while tracks[index] in self.history:
            index = random_index()

        return os.path.join(MUSIC_FOLDER, tracks[index])

    def play_random(self):
        self.play(self.random_track())

    def start_random_playlist(self):
        self.stop()
        debug("Starting random playlist...")
        self.end_playlist.clear()

        def playlist_loop():
            while not self.end_playlist.is_set():
                self.play_random()

        playlist = threading.Thread(target=playlist_loop)
        playlist.start()

    def stop_playlist(self):
        self.end_playlist.set()
        self.stop()

    def start_remote(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(SOCKET_FILE)

        def handler(cmd):
            if cmd == "stop":
                self.stop_playlist()
            elif cmd == "play":
                self.stop_playlist()
                self.start_random_playlist()
            elif cmd == "skip":
                self.stop()

        def listener():
            while True:
                s.listen()
                conn, addr = s.accept()
                data = conn.recv(32)
                handler(data.decode())
                conn.close()

        debug("Starting remote...")
        remote = threading.Thread(target=listener)
        remote.start()


def get_boot_track():
    track = None
    for name in os.listdir(MUSIC_FOLDER):
        if name in BOOT_NAMES:
            track = os.path.join(MUSIC_FOLDER, name)
            break
    return track


def start_service():
    debug("Starting service...")
    player = Player()

    boot_track = get_boot_track()
    if boot_track is not None:
        player.play(boot_track)

    if player.total_tracks() == 0:
        debug("No tracks available to play")
        return

    player.start_remote()
    player.start_random_playlist()
    core = MENU_CORE

    while True:
        new_core = wait_core_change()

        if core == new_core:
            pass
        elif new_core == MENU_CORE:
            player.start_random_playlist()
        elif new_core != MENU_CORE:
            player.stop_playlist()

        core = new_core


def try_add_to_startup():
    if not os.path.exists(STARTUP_SCRIPT):
        return False

    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup BGM" in f.read():
            return False

    with open(STARTUP_SCRIPT, "a") as f:
        f.write(
            "\n# Startup BGM\n[[ -e /media/fat/Scripts/bgm.sh ]] && /media/fat/Scripts/bgm.sh start &\n"
        )
        return True


def create_control_scripts():
    play_file = (
        '#!/usr/bin/env bash\n\necho -n "play" | socat - UNIX-CONNECT:/tmp/bgm.sock'
    )
    with open(os.path.join(SCRIPTS_FOLDER, "bgm_play.sh"), "w") as f:
        f.write(play_file)

    stop_file = (
        '#!/usr/bin/env bash\n\necho -n "stop" | socat - UNIX-CONNECT:/tmp/bgm.sock'
    )
    with open(os.path.join(SCRIPTS_FOLDER, "bgm_stop.sh"), "w") as f:
        f.write(stop_file)

    skip_file = (
        '#!/usr/bin/env bash\n\necho -n "skip" | socat - UNIX-CONNECT:/tmp/bgm.sock'
    )
    with open(os.path.join(SCRIPTS_FOLDER, "bgm_skip.sh"), "w") as f:
        f.write(skip_file)


# TODO: playlist and remote threads should respond appropriately to Ctrl-C and SIGTERM

if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "start":
        if os.path.exists(SOCKET_FILE):
            print("BGM service is already running, exiting...")
            sys.exit(1)
        atexit.register(lambda: os.remove(SOCKET_FILE))

        start_service()
        sys.exit(0)

    if not os.path.exists(MUSIC_FOLDER):
        os.mkdir(MUSIC_FOLDER)
        print("Created music folder.")

    if try_add_to_startup():
        print("Added to MiSTer startup script.")

    if not os.path.exists(os.path.join(SCRIPTS_FOLDER, "bgm_play.sh")):
        create_control_scripts()
        print("Created BGM control scripts.")

    if len(os.listdir(MUSIC_FOLDER)) == 0:
        print(
            "Add music files to {} and re-run this script to start.".format(
                MUSIC_FOLDER
            )
        )
        sys.exit(0)
    else:
        if not os.path.exists(SOCKET_FILE):
            print("Starting BGM service...")
            os.system("{} start &".format(os.path.join(SCRIPTS_FOLDER, "bgm.sh")))
            sys.exit(0)
        else:
            print("BGM is already running.")
            sys.exit(0)
