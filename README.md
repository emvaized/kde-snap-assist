# <sub><img src="https://github.com/emvaized/kde-snap-assist/blob/dev/assets/logo.png" height="48" width="48"></sub> Snap Assist script for KDE Plasma
This KWin script suggests other window thumbnails on snap. It tries to replicate famous Windows 10/11 feature called "snap assist".
Assist can be shown by dragging a window to the screen edge, as well as via default keyboard shortcuts (Super + arrows).

You can select the window with mouse, as well as with arrow keys + Enter. To dismiss the assist, you can hit Escape key, press the close button or click anywhere on the empty area.
Script also supports quarter and triple tiling now: you can switch layouts with the Tab key or using the button in corner.

Few notes:
- To apply new settings, you may need to re-enable the script or restart KWin
- Assist will not show if you have no other windows matching the conditions set in the script settings 
- I only tested the scripts on monitors with 1080p and 720p resolution with 100% scaling. It may misbehave on other resolutions or scaling — please report your issues

Ideas, suggestions, bugs reports and contributions are welcome!

[KDE Store](https://store.kde.org/p/1875687)

![screenshot_snapassist](https://user-images.githubusercontent.com/37851576/183264649-da8d01cd-a8b7-4bac-92d7-ea71be00047d.png)


---
### Manual Installation
In order to install this script manually from GitHub, you'd need to:
- Delete current version of script and re-login to KDE Plasma
- Download the code as .zip (green "Code" button > "Download as ZIP"), and rename file to .kwinscript extension
- Use the "Install from file" button in System settings > Windows manager > KWin scripts
- Re-login to Plasma again (or restart KWin) to make sure the script is installed

---

### Compatibility with [Window Gap](https://github.com/nclarius/tile-gaps) script

Since version 1.2, there's an option "Snap detect tolerance" in the script settings, which basically defines how much window's size and position can differ to still be detected as "snapped" by the script. If you use some external scripts which constantly modify windows size and position, you may want to set it to `15px` or `25px`, so that Snap Assist could detect your snaps.

--- 

### Donate
If you really enjoy this product, there's no better way to thank for it than to send a couple of bucks for coffee :)

<a href="https://www.paypal.com/donate/?business=2KDNGXNUVZW7N&no_recurring=0&currency_code=USD"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" height="25"/></a>
