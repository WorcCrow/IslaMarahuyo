# 2026-09-26 22:17 -- Bodega, police, gear, Shark Bait, Health Post scanners

Backup of the Studio place after two rounds of playtest fixes (items 1-15). The previous
local save, `IslaMarahuyoRoblox.rbxl` (19:22), predates most of this.

**Must revert before release (quick-test values):**
- `ReplicatedStorage.ItemConfig` -> `Bodega.AxeDamage = 20` (real value `1`, i.e. 100 swings).
- `ServerScriptService.PoliceService` -> `SERVICE_TRACKS.vendor.credit = 0.4` (real value
  `0.1`, i.e. 20 restocks for a 2-day sentence).

## Round 1 (items 1-9)

| # | Asked for | What changed |
|---|---|---|
| 1 | Non-admins can't see glowsticks in the hotbar | No admin gating existed; the admin account simply owned some. Every profile now gets a one-time starter kit (3 glowsticks, 1 O2 tank) via a `StarterKitGiven` flag -- `PlayerProfileService` (`STARTER_KIT`, `grantStarterKit`). |
| 2 | Hotbar should show item pictures, not names | New custom hotbar `StarterPlayerScripts.Hotbar` replaces Roblox's built-in backpack bar (CoreGui Backpack disabled). Each slot renders the tool's own 3D model; keys 1-9, tap to equip. `PhotoModeController` hides it and keeps the built-in bar off. |
| 3 | Player gets stuck under a newly placed bodega | `BodegaService`: an invisible collider fills the gap under the wood hut's raised floor (`UnderSkirt`); placement is refused if anyone stands in the footprint; each tier is seated by its base (the stone tier was being buried half underground). |
| 4 | Police leave when the bodega closes | `PoliceUnit.EndWatch`, called from `BodegaService.removeRecord`: officers watching a closed scene go home unless still chasing a Wanted suspect. |
| 5 | Captured thief walked to the station | `PoliceUnit` "escort" state: the officer cuffs the downed suspect, drags them (welded, in a non-colliding `PulisEscort` collision group) to the station door, then books them. `PoliceService` gains `OnCuffed`/`OnReleased` and a `custody` table that holds the player still for the whole walk. |
| 6 | Officers come from the station | Already worked; confirmed in testing. No change. |
| 7 | Bodega breaks in 5 hits | `ItemConfig.Bodega.AxeDamage = 20` (**test value**). |
| 8 | Show how many consumables are left | Count badges on hotbar slots (O2, glowsticks, bait, lambat; flashlight shows charge + spare batteries). |
| 9 | Shark Bait item | `ItemConfig.Items.sharkbait` (80 Peso, 0.5 slots). New `SharkBaitService` (throw via `RequestBaitThrow`), `SharkLure` (shared state), `SharkService` targeting: held bait > thrown bait > plain swimmer, 400-stud lure range. Assets `ServerStorage.ItemAssets.SharkBait` / `SharkBaitTool` (+ `ThrowBait` LocalScript). |

## Round 2 (items 10-15)

| # | Asked for | What changed |
|---|---|---|
| 10 | Remove Nurse Fely's beds (content-policy risk) | `Cot_1..5` deleted; `MedScanner_1..5` standing scanner bays built (pad, arch, sweeping scan beam, console). `RecoverySpot_N` raised to standing height. `ReviveService`: patient held upright, exits out the front; bot nurse works the console (`poseMedic`, clean `PoseRoot`/`PoseYaw` pose -- also fixes nurses standing knee-deep in the floor and four nurses with stale home positions); scan beam `sweepScan`; VIP cosmetic turns scanner trim gold (`setBayVip`; profile key `RecoveryCot` unchanged). Wording: "Pulse the scanner on the beat" (`ReviveService`, `NurseController`). `ReviveController` overhead camera shot replaced with a front view. Bilao Box item renamed "Gold Scanner Bay" (`MonetizationConfig`). Comments updated in `BreathService`, `RoleService`. |
| 11 | Hide bag gear until the bodega is placed | `InventoryService.syncTools`: `BODEGA_GATED` (oxygen, glowstick, sharkbait, lambat -- not tolda) only get hotbar tools while `BodegaUp`; a `BodegaUp` attribute listener re-syncs instantly. |
| 12 | Community service 20 -> 5 restocks | `PoliceService` `SERVICE_TRACKS.vendor.credit = 0.4` (**test value**). |
| 13 | Bigger tile-view bag/bodega on mobile | `GearHud`: on touch devices the DIVE BAG and BODEGA tabs are a grid of picture cards (panel up to 640 wide, 2-6 cards per row, Close moved to the header). Desktop and the Palengke list are unchanged. New shared renderer `ReplicatedStorage.ItemIcon` and client-visible models `ReplicatedStorage.ItemIcons` (the prefabs live in ServerStorage). |
| 14 | Lambat not visible | `InventoryService.TOOL_FOR.lambat` + new `ServerStorage.ItemAssets.LambatTool`; added to hotbar order and counts. Staking (H) unchanged. |
| 15 | Sharks attracted to merely carried bait | Measured, not a bug: carried bait 8/18 far sharks closed in (random), equipped 9/9. Normal night aggression (50-200 sharks, 180-stud notice range) explains it. No code change. |

## Created instances
`ServerScriptService.SharkBaitService`, `ServerScriptService.SharkLure`,
`StarterPlayer.StarterPlayerScripts.Hotbar`, `ReplicatedStorage.ItemIcon`,
`ReplicatedStorage.ItemIcons` (folder), `ServerStorage.ItemAssets.SharkBait`,
`ServerStorage.ItemAssets.SharkBaitTool`, `ServerStorage.ItemAssets.LambatTool`,
`Workspace.IslaMarahuyo.Activities.MedicalDock.MedScanner_1..5`.

## Removed
`Workspace.IslaMarahuyo.Activities.MedicalDock.Cot_1..5`.

## Verified in Studio playtests
Starter kit + hotbar pictures/counts; escort from a crime scene to the station door and
booking; stone bodega seated on the ground; Shark Bait lure and thrown decoy; bodega gate
hiding/showing gear; revive in a scanner bay (upright, beam, nurse animation, clean exit);
phone tile grid in Studio's device emulation.

## Not verified
A real two-player bodega break-in end to end; a wood bodega placed live (under-floor collider
checked by geometry only); `EndWatch` after packing up; the 5-restock service path; the tile
grid on a physical phone.

## Restoring
Open the place in Studio, right-click a service -> "Insert from File..." -> the matching
`place\<Service>.rbxm` (delete the service's current children first to avoid duplicates).
`scripts\` holds every script's source for reading or diffing against another backup.
