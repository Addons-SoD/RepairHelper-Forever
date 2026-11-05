# RepairHelper

A lightweight World of Warcraft addon that automatically repairs all equipped items when you visit a merchant capable of repairing.

Originally extracted and cleaned up from the BigFoot addon suite's `RepairHelper` module, this standalone version removes all BigFoot dependencies and adds persistent settings with in-game slash commands.

This branch targets **World of Warcraft: Forever** (`wowf`, client 1.60.1, TOC Interface `16001`, modern Mainline API ~12.1.5).

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
2. Copy the `RepairHelper` folder into your WoW Forever addon directory:
   ```
   World of Warcraft\_forever_\Interface\AddOns\RepairHelper\
   ```
3. Enable **RepairHelper** in the in-game AddOns list at the character select screen.

## Compatibility

- **Interface**: 16001 (World of Warcraft: Forever)
- **Dependencies**: None

### API notes for the Forever client

- The removed globals (`GetSpellInfo`, `GetItemInfo`, `GetContainerItemInfo`, `GetContainerNumSlots`, `UnitAura*`, `GetSpellCooldown`, `GetSpellTexture`, …) are not used by this addon, so no `C_Spell` / `C_Item` / `C_Container` / `C_UnitAuras` rewrite is needed.
- `CanMerchantRepair`, `GetRepairAllCost` and `RepairAllItems` are the only required calls; they are still available on modern Mainline.
- `CanGuildBankRepair`, `GetGuildBankMoney` and `GetGuildBankWithdrawMoney` are probed at runtime — if a build drops them, repairs silently fall back to personal funds instead of erroring.
- `MERCHANT_SHOW` is the primary trigger. `MERCHANT_UPDATE` is registered as a fallback (for custom merchant UIs) and `MERCHANT_CLOSED` resets the per-merchant guard, so a single merchant visit never repairs or reports twice.
- If an addon file is loaded while already logged in, `IsLoggedIn()` handles the initialization so the addon never waits for a `PLAYER_LOGIN` that already fired.
- No combat-log events and no player health/power/name reads, so the disabled combat log and the "secret values" restrictions do not affect this addon.

## License

[MIT](LICENSE)
