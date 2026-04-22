# AutoLoot

A player-created WoW 3.3.5a addon for **Project Ebonhold** that automates the loot-and-sell cycle using two custom companion pets: the **Greedy Scavenger** (auto-looter) and the **Goblin Merchant** (vendor).

---

## Features

- **Auto-loot cycle** — Summons the Greedy Scavenger and monitors your bags every 3 seconds. When every slot is full it automatically dismisses the Scavenger and summons the Goblin Merchant.
- **Auto-repair** — Calls `RepairAllItems()` the moment a merchant window opens, before selling, so durability is always restored first.
- **Auto-sell on merchant open** — Scans your bags and sells all qualifying items the instant any vendor window opens. Items are sold in batches of up to **45 per pulse** with a **1.0-second pause** between batches to prevent server disconnects on large inventories; the vendor window stays open throughout and a single summary prints when the last batch finishes.
- **Fast Mode** — Optional toggle in the status row. Doubles items sold per batch (45 → 90) and halves the inter-batch delay (1.0s → 0.5s). Use on higher-end hardware only — a tooltip warns of potential disconnects. Setting persists between sessions.
- **Per-quality sell toggles** — Choose exactly which quality tiers to sell: Grey, White, Uncommon, Rare, and/or Epic.
- **Item whitelist** — Add item names to a protected list; whitelisted items are never sold regardless of quality.
- **Whitelist Tome of Echo items** — One-click button scans your bags and whitelists every item whose name starts with `Tome of Echo:` automatically.
- **Delete Savage PvP gear** — One-click button scans all bags and permanently deletes every item whose name starts with `Savage `. Deletions are processed one at a time with automatic confirmation of the quality-check popup. Blocked during combat.
- **On-screen vendor button** — A draggable `SecureActionButtonTemplate` button (parented to UIParent) targets the Goblin Merchant on click. Works in and out of combat. Alt+Drag to reposition; position is saved between sessions.
- **Mount-aware companion management** — Dismisses the active companion automatically when you mount. Re-summons the correct pet (Greedy Scavenger or Goblin Merchant) 1.5 seconds after dismounting.
- **Companion stuck detection** — Every bag-check tick, if the Greedy Scavenger drifts more than 5 yards from the player it is automatically dismissed and re-summoned. Skipped while mounted or airborne.
- **Persistent settings** — All preferences saved between sessions via `SavedVariables`.

---

## Installation

1. Download the latest release from: [GitHub Releases](../../releases/latest)
2. Place the `AutoLoot` folder into:
   ```
   Ebonhold/Interface/AddOns/
   ```
3. Launch WoW and enable the addon from the AddOns menu on the character select screen.

> **Requires** the `ProjectEbonhold` base addon.

---

## Usage

### Slash commands

| Command | Action |
|---|---|
| `/eal` | Open / close the settings window (works in and out of combat) |
| `/eal enable` | Enable the loot+sell cycle |
| `/eal disable` | Disable and dismiss any active pet |
| `/eal reset` | Clear the entire whitelist |
| `/autoloot` | Alias for `/eal` |

### Basic workflow

1. Open the settings window with `/eal`.
2. Tick the quality tiers you want to sell (Grey is on by default).
3. Add any items you want to keep to the **Whitelist**, or click **Whitelist all "Tome of Echo:" in bags** to protect those items in one click.
4. Click **Enable** — the addon summons your Greedy Scavenger and starts monitoring your bags.
5. When bags fill up, it automatically dismisses the Scavenger and summons the Goblin Merchant.
6. Interact with the Goblin Merchant to open the vendor window — the addon immediately repairs all gear, then sells qualifying items. Keep the vendor window open until the summary message appears in chat.
7. Once the vendor window closes, the Greedy Scavenger is automatically re-summoned and looting resumes.

### Selling in combat

`InteractUnit` is a Blizzard-UI-only protected function and cannot be called from any addon or macro. The addon works around this with an **on-screen vendor button**:

1. The **Vendor** button appears on your screen automatically on login (coin icon with a gold border). Alt+Drag to move it wherever suits your HUD.
2. When the Goblin Merchant is summoned, click the **Vendor** button — this targets the NPC even during combat.
3. Press your **Interact with Target** keybind (`Escape → Key Bindings → Targeting → Interact With Target`) to open the vendor window.
4. Auto-repair and auto-sell fire instantly the moment `MERCHANT_SHOW` triggers.

The button can be shown or hidden at any time from the **Show/Hide Vendor Btn** toggle in the `/eal` window.

> **Server-side note:** The fully seamless automatic flow — zero player interaction required — can be achieved by configuring the Goblin Merchant companion on the server to send the merchant list on summon (firing `MERCHANT_SHOW` automatically). Once that is in place the addon handles the entire cycle without any input and the vendor button is no longer needed.

---

## GUI Overview

```
┌─────────────────────────────────────────┐
│           AutoLoot & Sell               │
├─────────────────────────────────────────┤
│ Status: LOOTING  Free Slots: 12         │
│                        [ ] Fast Mode    │
├─────────────────────────────────────────┤
│ [ Enable/Disable ]    [ Force Sell Now ]│
├─────────────────────────────────────────┤
│ Click vendor button, then Interact key  │
│ to sell               [Show Vendor Btn] │
├─────────────────────────────────────────┤
│ SELL QUALITY                            │
│ [x] Grey  [ ] White  [ ] Uncommon       │
│ [ ] Rare  [ ] Epic                      │
├─────────────────────────────────────────┤
│ [ Delete All Savage PvP Gear from Bags ]│
├─────────────────────────────────────────┤
│ ITEM WHITELIST                          │
│ [Item Name Input            ] [  Add  ] │
│ [ Whitelist all "Tome of Echo:" in bags]│
│ ┌───────────────────────────────────┐   │
│ │ Hearthstone              [Remove] │   │
│ │ Tome of Echo: Fire       [Remove] │   │
│ └───────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

*The on-screen Vendor button floats separately from this window. Alt+Drag to reposition it.*

---

## Versioning

| Version | Notes |
|---|---|
| 3.2 | Ctrl+Click on vendor button opens settings GUI. Version loaded from TOC metadata. `ToggleGUI()` helper replaces duplicated show/hide logic. `OnUpdate` free-slot caching. Load-order fix for `EAL_WhitelistTomes`. README installation instructions corrected (PR #5 & #6 by @zaxlofful). |
| 3.1 | Added **Fast Mode** toggle (PR #4 by @zaxlofful) — doubles items sold per batch and halves inter-batch delay. Replaces the separate high-end release. |
| 3.0 | Added "Delete All Savage PvP Gear" button — async one-at-a-time deletion with auto-confirmation of quality popups. |
| 2.9 | Reduced batch size to 45 items and increased inter-batch delay to 1.0 s to prevent disconnects on large inventories (PR #1 by @zaxlofful). Added `FinishSelling` helper and guard for vendor closing mid-batch. Status bar now refreshes every bag-check tick. High-end release also available (80 items / 0.5 s). |
| 2.8 | README updated to reflect all current features; arrow glyph fixed in vendor hint text. |
| 2.7 | Renamed all player-facing "blacklist" text to "whitelist". |
| 2.6 | Added "Whitelist all Tome of Echo: in bags" one-click button. |
| 2.5 | Batched selling: up to 80 items per pulse, 0.5 s delay between batches, single summary on completion. |
| 2.4 | Added `MAX_SELL_PER_PULSE = 80` cap to prevent packet flooding on low-end clients. |
| 2.3 | Mount-aware companion management: dismiss on mount, re-summon correct pet on dismount. |
| 2.2 | On-screen vendor button (`SecureActionButtonTemplate`) replaces macro/keybind approach. |
| 2.1 | Vendor macro reworked to `VendorBind` pattern with automatic F5 keybind. |
| 2.0 | Vendor macro auto-creation on login. |
| 1.6 | Auto-repair: calls `RepairAllItems()` before selling whenever merchant supports it. |
| 1.5 | Removed macro creation code; documented `InteractUnit` limitation and server-side fix. |
| 1.4 | Re-enabled `/eal` during combat — plain frames need no `InCombatLockdown` guard. |
| 1.3 | Removed `SecureActionButtonTemplate` from GUI (caused "Interface action failed" error). |
| 1.2 | Companion stuck detection: auto-resummon if Greedy Scavenger > 5 yards away while not mounted. |
| 1.1 | Case-insensitive companion name matching; in-combat vendor attempt with SecureAction button. |
| 1.0 | Initial release — auto-loot/sell cycle, quality toggles, blacklist GUI. |

---

## Contributors

| Contributor | Contribution |
|---|---|
| [zaxlofful](https://github.com/zaxlofful) (Zachary Laughlin) | PR #1 — reduced sell batch size and increased inter-batch delay to prevent disconnects on large inventories |
| [zaxlofful](https://github.com/zaxlofful) (Zachary Laughlin) | PR #4 — Fast Mode toggle: doubles sell batch size and halves inter-batch delay for higher-end hardware |

---

## Compatibility

- **WoW version:** 3.3.5a (Interface 30300)
- **Server:** Project Ebonhold / Valanior
- **Dependencies:** ProjectEbonhold
