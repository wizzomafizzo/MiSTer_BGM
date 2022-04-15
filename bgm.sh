#!/usr/bin/env python

import os
import sys
import subprocess
import threading
import random
import math
import socket
import atexit
import configparser
import datetime

DEFAULT_PLAYLIST = "random"
MUSIC_FOLDER = "/media/fat/music"
HISTORY_SIZE = 0.2  # ratio of total tracks to keep in play history
SOCKET_FILE = "/tmp/bgm.sock"
SCRIPTS_FOLDER = "/media/fat/Scripts"
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"
CORENAME_FILE = "/tmp/CORENAME"
LOG_FILE = "/tmp/bgm.log"
INI_FILENAME = "bgm.ini"
MENU_CORE = "MENU"
DEBUG = False


# TODO: way to make it run sooner? put in an faq

# read ini file
ini_file = os.path.join(MUSIC_FOLDER, INI_FILENAME)
if os.path.exists(ini_file):
    ini = configparser.ConfigParser()
    ini.read(ini_file)
    DEFAULT_PLAYLIST = ini.get("bgm", "playlist", fallback=DEFAULT_PLAYLIST)
    DEBUG = ini.getboolean("bgm", "debug", fallback=DEBUG)
else:
    # create a default ini
    if os.path.exists(MUSIC_FOLDER):
        with open(ini_file, "w") as f:
            f.write("[bgm]\nplaylist = random\ndebug = no\n")


def log(msg: str):
    if not DEBUG:
        return
    print(msg)
    with open(LOG_FILE, "a") as f:
        f.write(
            "[{}] {}\n".format(datetime.datetime.isoformat(datetime.datetime.now()), msg)
        )


def random_index(list):
    return random.randint(0, len(list) - 1)


# TODO: get current core fn


def wait_core_change():
    # FIXME: this could turn very bad if the tmp file never appears
    if not os.path.exists(CORENAME_FILE):
        return MENU_CORE

    # TODO: log output
    args = ("inotifywait", "-e", "modify", CORENAME_FILE)
    subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    with open(CORENAME_FILE) as f:
        return str(f.read())


# TODO: vgmplay support
# TODO: disable playlist (boot sound only)
# TODO: single track loop options
class Player:
    player = None
    end_playlist = threading.Event()
    history = []

    def is_mp3(self, filename: str):
        return filename.lower().endswith(".mp3")

    def is_ogg(self, filename: str):
        return filename.lower().endswith(".ogg")

    def is_wav(self, filename: str):
        return filename.lower().endswith(".wav")

    # TODO: this might get crazy if vgmplay is added. use a regex?
    def is_valid_file(self, filename: str):
        return self.is_mp3(filename) or self.is_ogg(filename) or self.is_wav(filename)

    def play_mp3(self, filename: str):
        args = ("mpg123", "--no-control", filename)
        self.player = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        # TODO: log output
        # TODO: change to communicate?
        # workaround for a strange issue with mpg123 on MiSTer
        # some mp3 files will play but cause mpg123 to hang at the end
        # this may be fixed when MiSTer ships with a newer version
        while self.player is not None:
            line = self.player.stdout.readline()
            # TODO: or poll
            if "finished." in line.decode():
                self.stop()
                break

    def play_ogg(self, filename: str):
        args = ("ogg123", filename)
        # TODO: log output
        self.player = subprocess.Popen(
            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        self.player.wait()

    def play_wav(self, filename: str):
        args = ("aplay", filename)
        # TODO: log output
        self.player = subprocess.Popen(
            args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        self.player.wait()

    def all_tracks(self):
        tracks = []

        for track in os.listdir(MUSIC_FOLDER):
            if not track.startswith("_") and self.is_valid_file(track):
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
            log("Now playing: {}".format(filename))
        else:
            return

        if self.is_mp3(filename):
            self.play_mp3(filename)
        elif self.is_ogg(filename):
            self.play_ogg(filename)
        elif self.is_wav(filename):
            self.play_wav(filename)

    def random_track(self):
        tracks = self.all_tracks()
        if len(tracks) == 0:
            return

        index = random_index(tracks)
        # avoid replaying recent tracks
        while tracks[index] in self.history:
            index = random_index()

        return os.path.join(MUSIC_FOLDER, tracks[index])

    def play_random(self):
        self.play(self.random_track())

    def start_random_playlist(self):
        self.stop()
        log("Starting random playlist...")
        self.end_playlist.clear()

        def playlist_loop():
            while not self.end_playlist.is_set():
                self.play_random()

        playlist = threading.Thread(target=playlist_loop)
        playlist.start()

    def start_loop_playlist(self):
        self.stop()
        log("Starting loop playlist...")
        self.end_playlist.clear()

        track = self.random_track()

        def playlist_loop():
            while not self.end_playlist.is_set():
                self.play(track)

        playlist = threading.Thread(target=playlist_loop)
        playlist.start()

    def start_playlist(self, name):
        if name == "random":
            self.start_random_playlist()
        elif name == "loop":
            self.start_loop_playlist()
        else:
            # random playlist is fallback
            self.start_random_playlist()

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
                self.start_playlist(DEFAULT_PLAYLIST)
            elif cmd == "skip":
                self.stop()

        def listener():
            while True:
                s.listen()
                conn, addr = s.accept()
                data = conn.recv(32)
                handler(data.decode())
                conn.close()

        log("Starting remote...")
        remote = threading.Thread(target=listener)
        remote.start()

    def boot_track(self):
        tracks = []

        for name in os.listdir(MUSIC_FOLDER):
            if name.startswith("_") and self.is_valid_file(name):
                tracks.append(os.path.join(MUSIC_FOLDER, name))

        if len(tracks) > 0:
            return tracks[random_index(tracks)]
        else:
            return None

    def play_boot(self):
        track = self.boot_track()
        if track is not None:
            log("Selected boot track: {}".format(track))
            self.play(track)


def start_service():
    log("Starting service...")
    player = Player()

    # FIXME: make non-blocking, this can run past a core launch and bug out
    player.play_boot()

    if player.total_tracks() == 0:
        log("No tracks available to play")
        return

    player.start_remote()
    player.start_playlist(DEFAULT_PLAYLIST)
    core = MENU_CORE

    while True:
        new_core = wait_core_change()

        if core == new_core:
            pass
        elif new_core == MENU_CORE:
            player.start_playlist(DEFAULT_PLAYLIST)
        elif new_core != MENU_CORE:
            player.stop_playlist()

        core = new_core


def try_add_to_startup():
    if not os.path.exists(STARTUP_SCRIPT):
        # create a new startup script
        with open(STARTUP_SCRIPT, "w") as f:
            f.write("#!/bin/sh\n")

    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup BGM" in f.read():
            return False

    with open(STARTUP_SCRIPT, "a") as f:
        bgm = os.path.join(SCRIPTS_FOLDER, "bgm.sh")
        f.write(
            "\n# Startup BGM\n[[ -e {} ]] && {} $1 &\n".format(bgm, bgm)
        )
        return True


# TODO: single template for these and check if socket exists
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


def cleanup():
    if os.path.exists(SOCKET_FILE):
        os.remove(SOCKET_FILE)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        if sys.argv[1] == "start":
            if os.path.exists(SOCKET_FILE):
                print("BGM service is already running, exiting...")
                sys.exit(1)
            atexit.register(cleanup)
            start_service()
            sys.exit(0)
        elif sys.argv[1] == "stop":
            # TODO: don't think it really matters in practice but a stop service would be nice
            sys.exit(0)

    if not os.path.exists(MUSIC_FOLDER):
        os.mkdir(MUSIC_FOLDER)
        print("Created music folder.")

    if try_add_to_startup():
        print("Added to MiSTer startup script.")

    if not os.path.exists(os.path.join(SCRIPTS_FOLDER, "bgm_play.sh")):
        create_control_scripts()
        print("Created BGM control scripts.")

    player = Player()
    if player.total_tracks() == 0:
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
