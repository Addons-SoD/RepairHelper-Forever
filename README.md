# RepairHelper

A lightweight World of Warcraft (Classic Era) addon that automatically repairs all equipped items when you visit a merchant capable of repairing.

Originally extracted and cleaned up from the BigFoot addon suite's `RepairHelper` module, this standalone version removes all BigFoot dependencies and adds persistent settings with in-game slash commands.

## Features

- **Auto Repair** — Automatically repairs all equipment when opening a merchant window.
- **Guild Bank Support** — Optionally prefer guild bank funds for repairs.
- **Smart Fallback** — When guild funds are insufficient, optionally fall back to personal gold.
- **Cost Report** — Prints the repair cost to the chat frame after each repair.
- **Persistent Settings** — All preferences are saved per-account via `SavedVariables`.
- **Multi-Language** — Supports English, Simplified Chinese (zhCN), and Traditional Chinese (zhTW).

## Usage

### Slash Commands

| Command | Description |
|---|---|
| `/rh enable` or `/rh on` | Enable auto-repair |
| `/rh disable` or `/rh off` | Disable auto-repair |
| `/rh guild` | Toggle "prefer guild bank funds" |
| `/rh self` | Toggle "use personal funds when guild bank is insufficient" |
| `/rh` (no argument) | Show usage help |

`/repairhelper` works as an alias for `/rh`.

### Default Behavior

On first login the addon is **enabled** with guild-bank and self-fallback options **off**, meaning it will always repair using your personal gold.

## Installation

1. Download or clone this repository.
2. Copy the `RepairHelper` folder into your WoW addon directory:
   ```
   World of Warcraft\_classic_era_\Interface\AddOns\RepairHelper\
   ```
3. Enable **RepairHelper** in the in-game AddOns list at the character select screen.

## Compatibility

- **Interface**: 11508, 11509 (Classic Era / Season of Discovery)
- **Dependencies**: None

## License

[MIT](LICENSE)
