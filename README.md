# MiSTer_BGM
Background music player for the MiSTer menu.

## Installation
Copy [bgm.sh](https://github.com/wizzomafizzo/MiSTer_BGM/raw/main/bgm.sh) to the `Scripts` folder on your SD card.

Run `bgm` from the `Scripts` section of the MiSTer menu.

Copy your .mp3 and .ogg files to the newly created `music` folder on your SD card. You can do this in advance by creating the music folder yourself.

Reboot your MiSTer or re-run `bgm`.

## Usage

Once installed, BGM will automatically start on MiSTer boot and randomly play any music in the `music` folder.

BGM will stop playing when a core is launched, and resume playing when you get back to the menu.

The scripts `bgm_play`, `bgm_stop` and `bgm_skip` will be added the the `Scripts` menu, these can be used to manually control the player.

Rename a music file to `_boot.mp3` or `_boot.ogg` to make BGM play this file first on MiSTer startup.
