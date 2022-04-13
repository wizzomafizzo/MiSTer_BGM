# MiSTer_BGM
Background music player for the MiSTer menu.

## Installation
Copy [bgm.sh](https://github.com/wizzomafizzo/MiSTer_BGM/raw/main/bgm.sh) to the `Scripts` folder on your SD card.

Run `bgm` from the `Scripts` section of the MiSTer menu.

Copy your .mp3 and .ogg files to the newly created `music` folder on your SD card. You can do this in advance by creating the music folder yourself.

Reboot your MiSTer or re-run `bgm`.

## Usage

Once installed, BGM will automatically start on MiSTer boot and randomly play any tracks in the `music` folder.

BGM will stop playing when a core is launched, and resume playing when you get back to the menu.

### Control

The scripts `bgm_play`, `bgm_stop` and `bgm_skip` will be added the the `Scripts` menu. These can be used to manually control the player.

### Bootup sounds

Rename a music file with a `_` in front to make BGM play this file first on MiSTer startup (e.g. `_Mario 64 - Level Select.mp3`).

This can be done with multiple files to have it pick a random one each time.

### Playlists

By default, BGM will play the `random` playlist, which just repeatedly picks a track at random to play.

An alternate playlist called `loop` can also be used, which picks a random track to start, and then plays that same track on repeat until a reboot or core change.

You can specify which playlist should be used by editing the `bgm.ini` file in your SD card's `music` folder, and changing the `playlist` entry to be either `random` or `loop`.

This .ini file will be created automatically if it doesn't existed with default values populated.
