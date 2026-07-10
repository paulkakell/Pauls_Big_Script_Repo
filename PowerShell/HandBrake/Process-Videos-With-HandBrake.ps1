<#
.SYNOPSIS
Recursively finds video files that do not contain a marker string in the filename,
processes each file with HandBrakeCLI, and replaces the original file with the
processed file renamed to include the marker string.

.EXAMPLE
.\Process-Videos-With-HandBrake.ps1 `
  -RequiredString " - H.265 720p" `
  -PresetName "Paul Preset" `
  -OutputExtension ".mkv" `
  -HandBrakeCliPath "C:\Program Files\HandBrake\HandBrakeCLI.exe" `
  -RootPath "C:\av\Complete" `
  -ImportGuiPresets

.EXAMPLE
.\Process-Videos-With-HandBrake.ps1 `
  -RequiredString " - H.265 720p" `
  -PresetName "Paul Preset" `
  -OutputExtension ".mkv" `
  -HandBrakeCliPath "C:\Program Files\HandBrake\HandBrakeCLI.exe" `
  -RootPath "C:\av\Complete" `
  -ImportGuiPresets `
  -MaxFiles 1
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$RootPath = "C:\av\Complete",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RequiredString,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PresetName,

    [ValidateNotNullOrEmpty()]
    [string]$HandBrakeCliPath = "HandBrakeCLI.exe",

    [ValidateNotNullOrEmpty()]
    [string]$OutputExtension = ".mp4",

    [ValidateNotNullOrEmpty()]
    [string[]]$VideoExtensions = @(
        ".mp4", ".m4v", ".mkv", ".avi", ".mov", ".wmv",
        ".mpg", ".mpeg", ".webm", ".ts", ".m2ts"
    ),

    [string]$CandidateListPath,

    [string]$LogDirectory,

    [switch]$ImportGuiPresets,

    [string]$PresetImportFile,

    [switch]$KeepBackup,

    [bool]$PreserveTimestamps = $true,

    [int64]$MinimumOutputBytes = 1024,

    [int]$MaxFiles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-Extension {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Extension
    )

    $trimmed = $Extension.Trim()

    if ($trimmed.StartsWith(".")) {
        return $trimmed.ToLowerInvariant()
    }

    return ".$($trimmed.ToLowerInvariant())"
}

function Get-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "Directory does not exist: $Directory"
    }

    $candidate = Join-Path -Path $Directory -ChildPath $FileName

    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    for ($i = 1; $i -le 9999; $i++) {
        $numberedName = "$baseName.$i$extension"
        $numberedPath = Join-Path -Path $Directory -ChildPath $numberedName

        if (-not (Test-Path -LiteralPath $numberedPath)) {
            return $numberedPath
        }
    }

    throw "Unable to create a unique path in '$Directory' for '$FileName'"
}

function Resolve-HandBrakeCli {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandPath
    )

    if (Test-Path -LiteralPath $CommandPath -PathType Leaf) {
        return (Get-Item -LiteralPath $CommandPath).FullName
    }

    try {
        $command = Get-Command -Name $CommandPath -ErrorAction Stop
        return $command.Source
    }
    catch {
        throw "HandBrakeCLI could not be found. Check -HandBrakeCliPath. Current value: $CommandPath"
    }
}

function Test-FileNameStringIsValid {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()

    if ($Value.IndexOfAny($invalidCharacters) -ge 0) {
        throw "RequiredString contains one or more invalid filename characters."
    }
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $safe = $Name

    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($character, "_")
    }

    $safe = $safe.Trim()

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "handbrake"
    }

    if ($safe.Length -gt 120) {
        $safe = $safe.Substring(0, 120)
    }

    return $safe
}

function Invoke-HandBrakeCli {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try {
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
            Set-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop

        "Executable: $Executable" |
            Add-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop

        "Arguments: $($Arguments -join ' ')" |
            Add-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop

        "" |
            Add-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop

        $ErrorActionPreference = "Continue"

        # PowerShell 7.3+ can treat native command non-zero exits as PowerShell errors.
        # This keeps HandBrake logging from being handled as a terminating script error.
        $PSNativeCommandUseErrorActionPreference = $false

        & $Executable @Arguments *>&1 |
            Tee-Object -FilePath $LogPath -Append |
            ForEach-Object {
                Write-Host $_
            }

        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
    throw "RootPath does not exist or is not a folder: $RootPath"
}

if ($MaxFiles -lt 0) {
    throw "MaxFiles cannot be negative."
}

Test-FileNameStringIsValid -Value $RequiredString

$HandBrakeCliPath = Resolve-HandBrakeCli -CommandPath $HandBrakeCliPath
$OutputExtension = Normalize-Extension -Extension $OutputExtension
$VideoExtensions = $VideoExtensions | ForEach-Object {
    Normalize-Extension -Extension $_
} | Select-Object -Unique

if (-not [string]::IsNullOrWhiteSpace($PresetImportFile)) {
    if (-not (Test-Path -LiteralPath $PresetImportFile -PathType Leaf)) {
        throw "PresetImportFile does not exist: $PresetImportFile"
    }
}

if ([string]::IsNullOrWhiteSpace($CandidateListPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $CandidateListPath = Join-Path -Path $RootPath -ChildPath "handbrake_candidates_$timestamp.csv"
}
else {
    $candidateListDirectory = Split-Path -Parent $CandidateListPath

    if (-not [string]::IsNullOrWhiteSpace($candidateListDirectory)) {
        if (-not (Test-Path -LiteralPath $candidateListDirectory -PathType Container)) {
            throw "Candidate list folder does not exist: $candidateListDirectory"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path -Path $RootPath -ChildPath "handbrake_logs"
}

Write-Host "Scanning: $RootPath"
Write-Host "Marker string: $RequiredString"
Write-Host "Preset: $PresetName"
Write-Host "HandBrakeCLI: $HandBrakeCliPath"
Write-Host "Output extension: $OutputExtension"
Write-Host "Import GUI presets: $($ImportGuiPresets.IsPresent)"
Write-Host "Log directory: $LogDirectory"

$allCandidates = @(
    Get-ChildItem -LiteralPath $RootPath -File -Recurse |
        Where-Object {
            $extension = $_.Extension.ToLowerInvariant()
            $isVideo = $VideoExtensions -contains $extension
            $lacksMarker = $_.Name.IndexOf($RequiredString, [System.StringComparison]::OrdinalIgnoreCase) -lt 0
            $isNotTemp = $_.Name.IndexOf(".handbrake.", [System.StringComparison]::OrdinalIgnoreCase) -lt 0

            $isVideo -and $lacksMarker -and $isNotTemp
        } |
        Sort-Object FullName
)

if ($MaxFiles -gt 0) {
    $candidates = @($allCandidates | Select-Object -First $MaxFiles)
}
else {
    $candidates = $allCandidates
}

Write-Host "Files to process: $($candidates.Count)"

if ($PSCmdlet.ShouldProcess($CandidateListPath, "Write candidate CSV list")) {
    $candidates |
        Select-Object FullName, DirectoryName, Name, Extension, Length, LastWriteTime |
        Export-Csv -LiteralPath $CandidateListPath -NoTypeInformation -Encoding UTF8

    Write-Host "Candidate list written to: $CandidateListPath"
}

if ($candidates.Count -eq 0) {
    Write-Host "No matching files found."
    exit 0
}

foreach ($file in $candidates) {
    $sourcePath = $file.FullName
    $directory = $file.DirectoryName

    if ([string]::IsNullOrWhiteSpace($directory)) {
        Write-Warning "Skipping because directory could not be determined: $sourcePath"
        continue
    }

    $originalBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    $finalName = "$originalBaseName$RequiredString$OutputExtension"
    $finalPath = Join-Path -Path $directory -ChildPath $finalName

    if (Test-Path -LiteralPath $finalPath) {
        Write-Warning "Skipping because target already exists: $finalPath"
        continue
    }

    $tempName = ".$originalBaseName.handbrake.$([System.Guid]::NewGuid().ToString('N'))$OutputExtension"
    $tempPath = Join-Path -Path $directory -ChildPath $tempName

    $backupFileName = "$($file.Name).original-before-handbrake.bak"
    $backupPath = Get-UniquePath -Directory $directory -FileName $backupFileName

    $safeLogBase = ConvertTo-SafeFileName -Name $originalBaseName
    $logName = "$safeLogBase.$(Get-Date -Format 'yyyyMMdd_HHmmss').$([System.Guid]::NewGuid().ToString('N')).log"
    $logPath = Join-Path -Path $LogDirectory -ChildPath $logName

    $operation = "Encode, replace original, and rename to '$finalName'"

    if (-not $PSCmdlet.ShouldProcess($sourcePath, $operation)) {
        continue
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    Write-Host ""
    Write-Host "Processing: $sourcePath"
    Write-Host "Log: $logPath"

    $sourceMovedToBackup = $false
    $outputMovedToFinal = $false

    try {
        $handBrakeArgs = @()

        if ($ImportGuiPresets) {
            $handBrakeArgs += "--preset-import-gui"
        }

        if (-not [string]::IsNullOrWhiteSpace($PresetImportFile)) {
            $handBrakeArgs += "--preset-import-file"
            $handBrakeArgs += $PresetImportFile
        }

        $handBrakeArgs += "--preset"
        $handBrakeArgs += $PresetName
        $handBrakeArgs += "-i"
        $handBrakeArgs += $sourcePath
        $handBrakeArgs += "-o"
        $handBrakeArgs += $tempPath

        $exitCode = Invoke-HandBrakeCli `
            -Executable $HandBrakeCliPath `
            -Arguments $handBrakeArgs `
            -LogPath $logPath

        if ($exitCode -ne 0) {
            throw "HandBrakeCLI failed with exit code $exitCode. Review log: $logPath"
        }

        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            throw "HandBrakeCLI did not create an output file. Review log: $logPath"
        }

        $tempFile = Get-Item -LiteralPath $tempPath

        if ($tempFile.Length -lt $MinimumOutputBytes) {
            throw "Output file is smaller than the minimum valid size: $($tempFile.Length) bytes. Review log: $logPath"
        }

        $originalCreationTime = $file.CreationTime
        $originalLastWriteTime = $file.LastWriteTime
        $originalLastAccessTime = $file.LastAccessTime

        Move-Item -LiteralPath $sourcePath -Destination $backupPath -ErrorAction Stop
        $sourceMovedToBackup = $true

        Move-Item -LiteralPath $tempPath -Destination $finalPath -ErrorAction Stop
        $outputMovedToFinal = $true

        if ($PreserveTimestamps) {
            try {
                $processedFile = Get-Item -LiteralPath $finalPath -ErrorAction Stop
                $processedFile.CreationTime = $originalCreationTime
                $processedFile.LastWriteTime = $originalLastWriteTime
                $processedFile.LastAccessTime = $originalLastAccessTime
            }
            catch {
                Write-Warning "Processed file was created, but timestamps could not be preserved: $finalPath"
                Write-Warning $_.Exception.Message
            }
        }

        if ($KeepBackup) {
            Write-Host "Original retained as backup: $backupPath"
        }
        else {
            try {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Processed file was created, but the backup could not be deleted: $backupPath"
                Write-Warning $_.Exception.Message
            }
        }

        Write-Host "Created: $finalPath"
    }
    catch {
        Write-Warning "Failed: $sourcePath"
        Write-Warning $_.Exception.Message

        if ((Test-Path -LiteralPath $tempPath) -and (-not $outputMovedToFinal)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        if ($sourceMovedToBackup -and (-not $outputMovedToFinal)) {
            if ((Test-Path -LiteralPath $backupPath) -and (-not (Test-Path -LiteralPath $sourcePath))) {
                Move-Item -LiteralPath $backupPath -Destination $sourcePath -ErrorAction SilentlyContinue
            }
        }

        continue
    }
}
