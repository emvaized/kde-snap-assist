# <sub><img src="https://github.com/emvaized/kde-snap-assist/blob/dev/assets/logo.png" height="48" width="48"></sub> KDE Snap Assist
This KWin script for KDE Plasma suggests other window thumbnails on snap. It tries to replicate the famous Windows 10/11 feature of the same name.

Assist can be shown by dragging a window to the screen edge, as well as via default keyboard shortcuts (`super`+arrows).
You can select the window with mouse, as well as with arrow keys + `Enter`. 
To dismiss the assist, hit `Escape` key, press the close button or click anywhere on the empty area. 
Script also supports quarter and triple tiling: you can switch layouts with the `Tab` key or using the button in corner.

Since version 1.4, it also provides experimental options for *enhanced* snapped windows management:
- Minimize/restore snapped windows together
- Raise snapped windows together
- On close snapped window, try to fill the area

Few notes:
- To apply new settings, you may need to re-enable the script or restart KWin
- Assist will not show if you have no other windows matching the conditions set in the script settings 

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

### Compatibility with diagonal keyboard shortcuts

Version 1.4 introduces an option "Delay before showing the assist", which gives some time to execute 'diagonal' shortcuts (`super` + `↑` + `→`) before Assist gets shown.

--- 

### Donate
If you really like this script, you can thank for it by buying me a coffee :)

<a href="https://www.paypal.com/donate/?business=2KDNGXNUVZW7N&no_recurring=0&currency_code=USD"><img src="https://www.paypalobjects.com/en_US/DK/i/btn/btn_donateCC_LG.gif" height="25"/></a>
