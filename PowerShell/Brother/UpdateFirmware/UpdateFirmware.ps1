# Set your printer's IP address and model number
$PrinterIP = "192.168.1.100"
$PrinterModel = "HL-L8360CDW"

# Define the URL for the firmware download page
$FirmwareURL = "https://support.brother.com/g/b/downloadtop.aspx?c=us&lang=en&prod=$($PrinterModel.ToLower())_eus"

# Get the latest firmware version from Brother's website
$LatestFirmwareInfo = (Invoke-WebRequest -Uri $FirmwareURL -UseBasicParsing).Links |
    Where-Object { $_.href -like "*.firm" } |
    ForEach-Object { @{ Version = $_.innerText.Trim() -replace '[^0-9.]', ''; DownloadUrl = $_.href } } |
    Sort-Object -Descending -Property Version |
    Select-Object -First 1

if (!$LatestFirmwareInfo) {
    Write-Host "Couldn't retrieve the latest firmware version for the printer model. Please verify the printer model and try again."
    exit
}

$LatestFirmwareVersion = $LatestFirmwareInfo.Version
$LatestFirmwareDownloadUrl = $LatestFirmwareInfo.DownloadUrl

Write-Host "Latest firmware version for $($PrinterModel): $LatestFirmwareVersion"

# Connect to the remote printer and get its firmware version
$PrinterInfo = Invoke-WebRequest -Uri "http://$PrinterIP/general/information.xml" -UseBasicParsing

if (!$PrinterInfo) {
    Write-Host "Couldn't connect to the remote printer. Please verify the printer's IP address and try again."
    exit
}

$CurrentFirmwareVersion = ([xml]$PrinterInfo.Content).information.version

Write-Host "Current firmware version of the remote printer: $CurrentFirmwareVersion"

# Compare the current firmware version with the latest one
if ($CurrentFirmwareVersion -eq $LatestFirmwareVersion) {
    Write-Host "The remote Brother printer is running the latest firmware version."
} else {
    Write-Host "The remote Brother printer is NOT running the latest firmware version. An update is recommended."
    $UpdateChoice = Read-Host "Do you want to download and install the latest firmware? (Y/N)"

    if ($UpdateChoice -eq "Y") {
        $FirmwareFile = "$env:TEMP\BrotherFirmware.firm"
        Invoke-WebRequest -Uri $LatestFirmwareDownloadUrl -OutFile $FirmwareFile

        if (Test-Path $FirmwareFile) {
            Write-Host "Firmware file downloaded to: $FirmwareFile"
            Write-Host "Uploading firmware file to the printer..."

            $FirmwareUpdateUrl = "http://$PrinterIP/firmware_upload.html"
            $FirmwareUpdateResult = Invoke-WebRequest -Uri $FirmwareUpdateUrl -Method Post -InFile $FirmwareFile -ContentType 'application/octet-stream'

            if ($FirmwareUpdateResult.StatusCode -eq 200) {
                Write-Host "Firmware update process has started. Please wait for the printer to reboot and complete the update."
            } else {
                Write-Host "Failed to update the firmware. Please check the printer's web interface for more details."
            }
        } else {
            Write-Host "Failed to download the firmware file. Please try again."
        }
    }
}
