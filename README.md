# Garry's Mod StarfallEx self-driving script
A [StarfallEx](https://github.com/thegrb93/StarfallEx) script for Garry's Mod, which allows [simfphys](https://steamcommunity.com/workshop/filedetails/?id=771487490) vehicles to drive themselves **under limited conditions** when no driver is present using [Wiremod](https://steamcommunity.com/sharedfiles/filedetails/?id=160250458).<br>
*Speed control is currently simple and will not adjust accordingly to moving objects in the vehicle's path.*<br>

### Required addons
- [StarfallEx](https://github.com/thegrb93/StarfallEx)
- [Wiremod](https://steamcommunity.com/sharedfiles/filedetails/?id=160250458)
- [simfphys](https://steamcommunity.com/workshop/filedetails/?id=771487490)

## Usage
It is recommended to use this script on maps which have walls/fences so the vehicle can recognise where to drive and what is a turn.<br><br>
**To use this script:**
1. Spawn a simfphys vehicle.
2. Place three WireMod rangers with default settings and max distance set at least to 1000 (1500 is recommended, you can type it in) and default to zero disabled, on the vehicle:<br>
- one looking in front of the vehicle
- one looking around 30° - 45° to the left
- one looking around 30° - 45° to the right
3. Place a speedometer on the vehicle
4. Place a StarfallEx chip on the vehicle and copy [the script](https://raw.githubusercontent.com/flgx16/gmod-selfdriving/master/selfdriving.lua) into the chip.
5. Connect the WireMod inputs and outputs of the chip accordingly using `Wiring tool` under `Wiremod` tab in the spawn menu.<br>
*Front, Left, Right should be connected to rangers' distance outputs accordingly.<br>
Speed should be connected to speedometer's `Out` output*
6. Every player with StarfallEx should now be able to use this script's keybinds

## Keybinds
- L - toggle pullover mode
- I - go straight
- O - find a left turn and turn there
- P - find a right turn and turn there

## License
Copyright (c) 2020-2021 Lukáš Horáček<br><br>
Licensed under the [GNU General Public License v3.0](https://github.com/flgx16/gmod-selfdriving/blob/master/LICENSE.txt).