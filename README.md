# MiSTer_BGM
Background music player for the [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki) menu

## Installation
Copy [bgm.sh](https://github.com/wizzomafizzo/MiSTer_BGM/raw/main/bgm.sh) to the `Scripts` folder on your SD card.

Run `bgm` from the `Scripts` section of the MiSTer menu.

Copy your .mp3, .ogg, .wav or .vgm files to the newly created `music` folder on your SD card. You can do this in advance by creating the music folder yourself.

Reboot your MiSTer or re-run `bgm`.

### Updates

BGM can be automatically updated with the MiSTer downloader script (and update_all). Add the following text to the `downloader.ini` file on your SD card:

```
[bgm]
db_url = 'https://github.com/wizzomafizzo/MiSTer_BGM/blob/main/bgm.json'
```

## Usage

Once installed, BGM will automatically start on MiSTer boot and randomly play any tracks in the `music` folder.

BGM will stop playing when a core is launched, and resume playing when you get back to the menu.

Launch `bgm` from the scripts menu to show the control GUI.

### Supported files

BGM supports playback of .mp3, .ogg, .wav and .vgm/.vgz files. These files can be used interchangeably in any playlist.

#### Internet radio

Internet radio stations can also be played using .pls files. The best way to manage these is by creating a new playlist folder, placing a single .pls file in that folder and playing it via the new playlist.

Note that a .pls file must be a file containing a single URL to the radio stream. Most radio files come like this, but be sure to double check if it's not working.

### Controls

When the BGM service is running, launch the `bgm` script from the MiSTer Scripts menu to launch the control GUI. This GUI will give you basic playback functions, configuration options and the current playback status.

Changes made in the control GUI will also be written to the `bgm.ini` file and remembered between MiSTer boots.

### Boot sounds

Rename a music file with a `_` in front to make BGM play this file first on MiSTer startup (e.g. `_Mario 64 - Level Select.mp3`).

This can be done with multiple files to have it pick a random one each time. Boot sounds are picked from the active playlist.

### Playback types

Playback types can be configured in the control GUI or in the `bgm.ini` file.

By default, BGM will play the `random` playback type, which repeatedly picks a track at random to play.

An alternate playback type called `loop` can be used, which picks a random track to start, and then plays that same track on repeat until a reboot or core change.

The `disabled` playback type will stop tracks from playing completely, except for boot sounds.

### Playlists

Music files can be separated into playlists. Create a subfolder in the `music` directory and fill it with music files, it will now show up in the control GUI as a playlist.

You can switch between playlists in the control GUI. As you switch, the current playlist will also be written to `bgm.ini` so it will be started automatically next boot. Boot sounds are also taken from the current playlist.

The `none` playlist can be used to continue using music files from the top level of the `music` folder. Music files in the top level of the `music` folder and playlist subfolders will not conflict with each other.

### Per track looping

Individual music files can be configured to loop a certain number of times. If you have a short piece of background music from a game that you'd like to run longer, you can set it so that when that track starts playing it will loop a certain number of times before continuing to the next track.

You can do this be renaming the music file so it has `X##_` in front of the filename where `##` is the number of times it should loop with a leading zero. For example: `X05_My File.mp3` would loop it 5 times, while `X23_My File.mp3` would loop it 23 times.
