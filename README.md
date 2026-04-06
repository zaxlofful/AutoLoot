# EbonholdAutoLoot

A WoW 3.3.5a AddOn for **Project Ebonhold** that automates the loot-and-sell cycle using two custom companion pets: the **Greedy Scavenger** (auto-looter) and the **Goblin Merchant** (vendor).

---

## Features

- **Auto-loot cycle** — Summons the Greedy Scavenger and monitors your bags. When every slot is full it automatically dismisses the Scavenger and summons the Goblin Merchant.
- **Auto-sell on merchant open** — The moment any vendor window opens, the addon scans your bags and sells all qualifying items instantly.
- **Per-quality sell toggles** — Choose exactly which quality tiers to sell: Grey, White, Uncommon, Rare, and/or Epic.
- **Item blacklist** — Add item names to a protected list; blacklisted items are never sold regardless of quality.
- **In-combat vendor support** — A `SecureActionButtonTemplate` button targets the Goblin Merchant as a hardware event (works during combat lockdown). Pair it with your **Interact with Target** keybind to open the vendor mid-fight.
- **Action-bar macro generator** — One click (or `/eal macro`) creates a ready-to-drag `EBVendor` macro in your macro book.
- **Persistent settings** — All preferences saved between sessions via `SavedVariables`.

---

## Installation

1. Download or clone this repository.
2. Place the `EbonholdAutoLoot` folder into:
   ```
   World of Warcraft/Interface/AddOns/
   ```
3. Launch WoW and enable the addon from the AddOns menu on the character select screen.

> **Requires** the `ProjectEbonhold` base addon.

---

## Usage

### Slash commands

| Command | Action |
|---|---|
| `/eal` | Open / close the settings window |
| `/eal enable` | Enable the loot+sell cycle |
| `/eal disable` | Disable and dismiss any active pet |
| `/eal macro` | Create / update the `EBVendor` action-bar macro |
| `/eal reset` | Clear the entire blacklist |
| `/autoloot` | Alias for `/eal` |

### Basic workflow

1. Open the settings window with `/eal`.
2. Tick the quality tiers you want to sell (Grey is enabled by default).
3. Add any items you want to keep to the **Blacklist**.
4. Click **Enable** — the addon summons your Greedy Scavenger and starts monitoring your bags.
5. When bags fill up, it automatically switches to the Goblin Merchant. Open the vendor window and selling happens instantly.

### Selling in combat

`InteractUnit` is a Blizzard-UI-only protected function and cannot be called from any addon script or macro, even during a hardware event. The supported in-combat workflow is:

1. When bags are full the addon summons the Goblin Merchant automatically.
2. Click the **Target Vendor** button in the addon window (or press your `EBVendor` macro on your action bar) — this targets the Goblin Merchant as a secure hardware event.
3. **Right-click** the Goblin Merchant's model in the world, **or** press your **Interact with Target** keybind.
   - To set the keybind: `Escape → Key Bindings → Targeting → Interact With Target`
4. The vendor window opens and auto-sell fires immediately.

---

## GUI Overview

```
┌─────────────────────────────────────┐
│       Ebonhold AutoLoot & Sell      │
├─────────────────────────────────────┤
│ Status: LOOTING   Free Slots: 12    │
├─────────────────────────────────────┤
│ [Enable/Disable]   [Force Sell Now] │
├─────────────────────────────────────┤
│ IN-COMBAT VENDOR                    │
│ [Target Vendor]     [Create Macro]  │
├─────────────────────────────────────┤
│ SELL QUALITY                        │
│ [x] Grey  [x] White  [ ] Uncommon  │
│ [ ] Rare  [ ] Epic                  │
├─────────────────────────────────────┤
│ ITEM BLACKLIST                      │
│ [Item Name Input      ] [Add]       │
│ ┌─────────────────────────────────┐ │
│ │ Hearthstone              [Remove]│ │
│ │ Tabard of the ...        [Remove]│ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

## Versioning

| Version | Notes |
|---|---|
| 1.1 | In-combat vendor: SecureAction target button + EBVendor macro generator. Removed unsupported InteractUnit macro call. |
| 1.0 | Initial release — auto-loot/sell cycle, quality toggles, blacklist GUI. |

---

## Compatibility

- **WoW version:** 3.3.5a (Interface 30300)
- **Server:** Project Ebonhold / Valanior
- **Dependencies:** ProjectEbonhold
