# MiSTer BGM (archived)

Development moved to the main [mrext repository](https://github.com/wizzomafizzo/mrext#bgm).

Current source and manual download: [`scripts/bgm.sh`](https://github.com/wizzomafizzo/mrext/raw/main/scripts/bgm.sh)

## Existing MiSTer Downloader installations

The standalone BGM downloader database will no longer receive updates from this repository. Downloader configuration is not migrated automatically.

In `downloader.ini` on the SD card, remove the old BGM entry:

```ini
[bgm]
db_url = 'https://raw.githubusercontent.com/wizzomafizzo/MiSTer_BGM/main/bgm.json'
```

Replace it with the combined mrext database:

```ini
[mrext/all]
db_url = https://raw.githubusercontent.com/wizzomafizzo/mrext/main/releases/all.json
```

Then run `downloader` or `update` from the MiSTer Scripts menu.

This repository remains available as a read-only archive. Its complete Git history and contributor authorship were imported into `wizzomafizzo/mrext` before archival.
