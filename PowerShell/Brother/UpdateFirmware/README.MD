# Brother Firmware Update
This PowerShell script helps you to check if your Brother printer is running the latest firmware version and provides an option to download and install the latest firmware if it's different from the one currently installed on the printer.

**Important:** This script assumes that the remote printer supports firmware updates via the web interface. Some Brother printers may not support this feature, or it may be disabled by default.

## Requirements
* PowerShell
* A Brother printer with an accessible web interface

## Usage
1. Download the script `BrotherPrinterFirmwareUpdate.ps1`.
2. Open the script in a text editor, and replace the `$PrinterIP` and `$PrinterModel` variables with the actual IP address and model number of your Brother printer.
3. Open PowerShell and navigate to the folder where you downloaded the script.
4. Run the script by typing `.\BrotherPrinterFirmwareUpdate.ps1` and pressing Enter.

The script will connect to the printer, retrieve its firmware version, and compare it with the latest version available on the Brother support website. If the printer isn't running the latest firmware, it will prompt you to download and install the latest firmware.

## Example
`PS > .\UpdateFirmware.ps1`  
`Latest firmware version for HL-L8360CDW: 1.34`  
`Current firmware version of the remote printer: 1.32`  
`The remote Brother printer is NOT running the latest firmware version. An update is recommended.`  
`Do you want to download and install the latest firmware? (Y/N): Y`  
`Firmware file downloaded`  
`Uploading firmware file to the printer...`  
`Firmware update process has started. Please wait for the printer to reboot and complete the update.`  
