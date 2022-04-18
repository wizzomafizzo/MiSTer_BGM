#!/usr/bin/env python

import os
import sys
import subprocess
import threading
import random
import math
import socket
import configparser
import datetime
import time
import signal
import re

DEFAULT_PLAYBACK = "random"
DEFAULT_PLAYLIST = None
MUSIC_FOLDER = "/media/fat/music"
ENABLE_STARTUP = True
HISTORY_SIZE = 0.2  # ratio of total tracks to keep in play history
SOCKET_FILE = "/tmp/bgm.sock"
MESSAGE_SIZE = 32
SCRIPTS_FOLDER = "/media/fat/Scripts"
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"
CORENAME_FILE = "/tmp/CORENAME"
LOG_FILE = "/tmp/bgm.log"
INI_FILENAME = "bgm.ini"
MENU_CORE = "MENU"
DEBUG = False


# TODO: change playback and playlist through socket
# TODO: get status through socket
# TODO: remove control scripts and make dialog gui
# TODO: internet radio/playlist files
# TODO: per track loop options (filename?)
# TODO: remote control http server, separate file
# TODO: way to make it run sooner? put in docs how to add service file


# read ini file
ini_file = os.path.join(MUSIC_FOLDER, INI_FILENAME)
if os.path.exists(ini_file):
    ini = configparser.ConfigParser()
    ini.read(ini_file)
    DEFAULT_PLAYBACK = ini.get("bgm", "playback", fallback=DEFAULT_PLAYBACK)
    DEBUG = ini.getboolean("bgm", "debug", fallback=DEBUG)
    ENABLE_STARTUP = ini.getboolean("bgm", "startup", fallback=ENABLE_STARTUP)
    DEFAULT_PLAYLIST = ini.get("bgm", "playlist", fallback=DEFAULT_PLAYLIST)
    if DEFAULT_PLAYLIST == "none":
        DEFAULT_PLAYLIST = None
else:
    # create a default ini
    if os.path.exists(MUSIC_FOLDER):
        with open(ini_file, "w") as f:
            f.write(
                "[bgm]\nplayback = random\nplaylist = none\nstartup = yes\ndebug = no\n"
            )


def log(msg: str, always_print=False):
    if msg == "":
        return
    if always_print or DEBUG:
        print(msg)
    if DEBUG:
        with open(LOG_FILE, "a") as f:
            f.write(
                "[{}] {}\n".format(
                    datetime.datetime.isoformat(datetime.datetime.now()), msg
                )
            )


def random_index(list):
    return random.randint(0, len(list) - 1)


def get_core():
    if not os.path.exists(CORENAME_FILE):
        return None

    with open(CORENAME_FILE) as f:
        return str(f.read())


def wait_core_change():
    if get_core() is None:
        log("CORENAME file does not exist, retrying...")
        # keep trying to read it for a little while
        attempts = 0
        while get_core() is None and attempts <= 15:
            time.sleep(1)
            attempts += 1
        if get_core() is None:
            log("No CORENAME file found")
            return None

    # FIXME: not a big deal, but this process can be orphaned during service shutdown
    args = ("inotifywait", "-e", "modify", CORENAME_FILE)
    monitor = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    while monitor is not None and monitor.poll() is None:
        line = monitor.stdout.readline()
        log(line.decode().rstrip())

    if monitor.returncode != 0:
        log("Error when running inotify watch")
        return None

    core = get_core()
    log("Core change to: {}".format(core))
    return core


class Player:
    player = None
    playback = DEFAULT_PLAYBACK
    playlist = DEFAULT_PLAYLIST
    playlist_thread = None
    end_playlist = threading.Event()
    history = []

    def is_mp3(self, filename: str):
        return filename.lower().endswith(".mp3")

    def is_ogg(self, filename: str):
        return filename.lower().endswith(".ogg")

    def is_wav(self, filename: str):
        return filename.lower().endswith(".wav")

    def is_vgm(self, filename: str):
        match = re.search(".*\.(vgm|vgz|vgm\.gz)$", filename.lower())
        return match is not None

    def is_valid_file(self, filename: str):
        return (
            self.is_mp3(filename)
            or self.is_ogg(filename)
            or self.is_wav(filename)
            or self.is_vgm(filename)
        )

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
            output = line.decode().rstrip()
            log(output)
            if (
                "finished." in output
                or self.player is None
                or self.player.poll() is not None
            ):
                self.stop()
                break

    def play_file(self, args):
        self.player = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        while self.player is not None and self.player.poll() is None:
            line = self.player.stdout.readline()
            log(line.decode().rstrip())
        self.stop()

    def play_ogg(self, filename: str):
        args = ("ogg123", filename)
        self.play_file(args)

    def play_wav(self, filename: str):
        args = ("aplay", filename)
        self.play_file(args)

    def play_vgm(self, filename: str):
        args = ("vgmplay", filename)
        self.play_file(args)

    def get_playlist_path(self, name=None):
        if name is None:
            name = self.playlist
        if name is None:
            return MUSIC_FOLDER
        else:
            folder = os.path.join(MUSIC_FOLDER, name)
            if not os.path.exists(folder):
                return MUSIC_FOLDER
            else:
                return folder

    def all_tracks(self, playlist=None):
        if playlist is None:
            folder = self.get_playlist_path()
        else:
            folder = self.get_playlist_path(playlist)
        tracks = []
        for track in os.listdir(folder):
            if not track.startswith("_") and self.is_valid_file(track):
                tracks.append(track)
        return tracks

    def total_tracks(self, playlist=None):
        return len(self.all_tracks(playlist))

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
        elif self.is_vgm(filename):
            self.play_vgm(filename)

    def get_random_track(self):
        tracks = self.all_tracks()
        if len(tracks) == 0:
            return

        index = random_index(tracks)
        # avoid replaying recent tracks
        while tracks[index] in self.history:
            index = random_index()

        return os.path.join(self.get_playlist_path(), tracks[index])

    def play_random(self):
        self.play(self.get_random_track())

    def start_random_playlist(self):
        log("Starting random playlist...")
        self.end_playlist.clear()

        def playlist_loop():
            while not self.end_playlist.is_set():
                self.play_random()
            log("Random playlist ended")

        self.playlist_thread = threading.Thread(target=playlist_loop)
        self.playlist_thread.start()

    def start_loop_playlist(self):
        log("Starting loop playlist...")
        self.end_playlist.clear()

        track = self.get_random_track()

        def playlist_loop():
            while not self.end_playlist.is_set():
                self.play(track)
            log("Loop playlist ended")

        self.playlist_thread = threading.Thread(target=playlist_loop)
        self.playlist_thread.start()

    def start_playlist(self, playback=None):
        if playback is None:
            playback = self.playback

        self.stop_playlist()
        if self.playlist_thread is not None and self.playlist_thread.is_alive():
            self.playlist_thread.join()
            self.playlist_thread = None

        if playback == "random":
            self.start_random_playlist()
        elif playback == "loop":
            self.start_loop_playlist()
        elif playback == "disabled":
            return
        else:
            # random playlist is fallback
            self.start_random_playlist()

    def stop_playlist(self):
        self.end_playlist.set()
        self.stop()

    def change_playlist(self, name: str):
        folder = self.get_playlist_path(name)
        if folder is not None and self.total_tracks(name) == 0:
            self.playlist = name
            self.start_playlist()

    def start_remote(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(SOCKET_FILE)

        def handler(cmd: str):
            log("Received command: {}".format(cmd))
            if cmd == "stop":
                self.stop_playlist()
            elif cmd.startswith("play"):
                args = cmd.split(" ")
                if len(args) > 1:
                    playback = args[1]
                else:
                    playback = self.playback
                self.stop_playlist()
                self.start_playlist(playback)
            elif cmd == "skip":
                self.stop()
            elif cmd == "pid":
                return os.getpid()
            else:
                log("Unknown command")

        def listener():
            while True:
                s.listen()
                conn, addr = s.accept()
                data = conn.recv(MESSAGE_SIZE).decode()
                if data == "quit":
                    break
                response = handler(data)
                if response is not None:
                    conn.send(str(response).encode())
                conn.close()
            s.close()
            log("Remote stopped")

        log("Starting remote...")
        remote = threading.Thread(target=listener)
        remote.start()

    def get_boot_track(self):
        boot_tracks = []

        for name in os.listdir(self.get_playlist_path()):
            if name.startswith("_") and self.is_valid_file(name):
                boot_tracks.append(os.path.join(self.get_playlist_path(), name))

        if len(boot_tracks) > 0:
            return boot_tracks[random_index(boot_tracks)]
        else:
            return None

    def play_boot(self):
        track = self.get_boot_track()
        if track is not None:
            log("Selected boot track: {}".format(track))
            self.play(track)


def send_socket(msg: str):
    if not os.path.exists(SOCKET_FILE):
        return
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCKET_FILE)
    s.send(msg.encode())
    response = s.recv(MESSAGE_SIZE)
    s.close()
    if len(response) > 0:
        return response.decode()


def cleanup(player: Player):
    if player is not None:
        player.stop_playlist()
        send_socket("quit")
    if os.path.exists(SOCKET_FILE):
        os.remove(SOCKET_FILE)


def start_service(player: Player):
    log("Starting service...")
    log("Playlist folder: {}".format(player.get_playlist_path()))

    player.start_remote()
    # FIXME: make this non-blocking so it can be cut off during core launch
    #        this only affects people with really long boot sounds
    player.play_boot()

    if player.total_tracks() == 0:
        log("No tracks available to play")
        return

    core = get_core()
    # don't start playing if the boot track ran into a core launch
    # do start playing for a bit if the CORENAME file is still being created
    if core == MENU_CORE or core is None:
        player.start_playlist(DEFAULT_PLAYBACK)

    while True:
        new_core = wait_core_change()

        if new_core is None:
            log("CORENAME file is missing, exiting...")
            break

        if core == new_core:
            pass
        elif new_core == MENU_CORE:
            log("Switched to menu core, starting playlist...")
            player.start_playlist(DEFAULT_PLAYBACK)
        elif new_core != MENU_CORE:
            log("Exited menu core, stopping playlist...")
            player.stop_playlist()

        core = new_core


def try_add_to_startup():
    if not os.path.exists(STARTUP_SCRIPT):
        # create a new startup script
        with open(STARTUP_SCRIPT, "w") as f:
            f.write("#!/bin/sh\n")

    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup BGM" in f.read():
            return

    with open(STARTUP_SCRIPT, "a") as f:
        bgm = os.path.join(SCRIPTS_FOLDER, "bgm.sh")
        f.write("\n# Startup BGM\n[[ -e {} ]] && {} $1\n".format(bgm, bgm))
        log("Added service to startup script.", True)


def try_create_control_scripts():
    template = '#!/usr/bin/env bash\n\necho -n "{}" | socat - UNIX-CONNECT:{}\n'
    for cmd in ("play", "stop", "skip"):
        script = os.path.join(SCRIPTS_FOLDER, "bgm_{}.sh".format(cmd, SOCKET_FILE))
        if not os.path.exists(script):
            with open(script, "w") as f:
                f.write(template.format(cmd))
                log("Created {} script.".format(cmd), True)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        if sys.argv[1] == "start-service":
            if os.path.exists(SOCKET_FILE):
                log("BGM service is already running, exiting...", True)
                sys.exit()

            def stop(sn=0, f=0):
                log("Stopping service ({})".format(sn))
                cleanup(player)
                sys.exit()

            signal.signal(signal.SIGINT, stop)
            signal.signal(signal.SIGTERM, stop)
            player = Player()
            start_service(player)
            stop()
        elif sys.argv[1] == "start":
            if not ENABLE_STARTUP:
                log("Auto-start is disabled in configuration", True)
                sys.exit()
            os.system(
                "{} start-service &".format(os.path.join(SCRIPTS_FOLDER, "bgm.sh"))
            )
            sys.exit()
        elif sys.argv[1] == "stop":
            if not os.path.exists(SOCKET_FILE):
                log("BGM service is not running", True)
                sys.exit()
            pid = send_socket("pid")
            if pid is not None:
                os.system("kill {}".format(pid))
            sys.exit()

    if not os.path.exists(MUSIC_FOLDER):
        os.mkdir(MUSIC_FOLDER)
        log("Created music folder.", True)
    try_add_to_startup()
    try_create_control_scripts()

    player = Player()
    if player.total_tracks() == 0:
        log(
            "Add music files to {} and re-run this script to start.".format(
                MUSIC_FOLDER
            ),
            True,
        )
        sys.exit()
    else:
        if not os.path.exists(SOCKET_FILE):
            log("Starting BGM service...", True)
            os.system(
                "{} start-service &".format(os.path.join(SCRIPTS_FOLDER, "bgm.sh"))
            )
            sys.exit()
        else:
            log("BGM is already running.", True)
            sys.exit()
