# Auto-HDR-Colour-Profile-Switcher

A powershell script for automatically swapping windows advanced colour profiles based on a whitelist of exe files. This will remove other colour profiles from the list within display settings so I suggest making sure any existing colour profiles are in "C:\Windows\System32\spool\drivers\color" so that you can easily re-add them in the colour management control panel.

This script requires administrator privileges so you will first need to create a shortcut to the script (drag and drop while holding control + shift). Then in the target field within properties, add “powershell.exe -f ” without the quotes, before the existing file path to the script. Then click the advanced button and check run as administrator.

Several things within the script also must be configured in order to work properly. Please see the script file for commented instructions.


