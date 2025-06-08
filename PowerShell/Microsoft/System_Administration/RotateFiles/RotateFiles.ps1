
$ScriptTitle = "File Rotation Report"
$LogFileName = ($ScriptTitle -replace '\s','_') + "_" + $(Get-Date -Format yy_MM_dd_HHmm)
$FullLogFileName = $LogFileName + ".html"
$LogPath = "C:\Scripts\Logfiles\RotateFiles\"
$LogFile = $LogPath + $FullLogFileName
$EmailTo = ""
$EmailCC = ""
$ExpirationDays = 90

$limit = (Get-Date).AddDays(-$ExpirationDays)
$path = "D:\FilePath"

# --- Functions
Function Format-FileSize() {
    Param ([int]$size)
    If ($size -gt 1TB) {[string]::Format("{0:0.00} TB", $size / 1TB)}
    ElseIf ($size -gt 1GB) {[string]::Format("{0:0.00} GB", $size / 1GB)}
    ElseIf ($size -gt 1MB) {[string]::Format("{0:0.00} MB", $size / 1MB)}
    ElseIf ($size -gt 1KB) {[string]::Format("{0:0.00} kB", $size / 1KB)}
    ElseIf ($size -gt 0) {[string]::Format("{0:0.00} B", $size)}
    Else {""}
}

Function Get-FileSizeSum {
    [cmdletbinding()]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateScript({Test-Path -path $_})]
        [string]$FilePath,
 
        [parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('KB', 'MB', 'GB', 'Byte')]
        [string]$SizeDisplay = 'MB',
 
        [parameter(ValueFromPipelineByPropertyName)]
        [switch]$Recurse
    )
    
    $Parameters = @{
        "FilePath" = $FilePath 
    }
 
    If($Recurse) {$null = $Parameters.Add("Recurse",$null)}
    Get-ChildItem @Parameters | ForEach-Object {$TotalSize  = $_.Length}
    If($SizeDisplay -eq "Byte"){$TotalSize} else {$TotalSize/$SizeDisplay}
}

Import-Module HTMLReport

WriteReportHeader -Title $ScriptTitle -Columns 1 -NoColumnNames -OutFile $LogFile

# --- Delete Expired Files Summary
$ReportName = "File Deletion Summary Report"
$ColumnCount = 3
$ColumnNames = "Count","Max Date","File Size"

WriteTableHeader -Title $ReportName -Columns $ColumnCount -ColumnNames $ColumnNames -OutFile $LogFile

$Query = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le $limit} | Sort-Object {$_.LastWriteTime}
$FSize = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le $limit} | Measure-Object -Property Length -Sum
$LastMember = ($Query.LastWriteTime).Count - 1
$CellBGColor = "Red"
WriteReportCell -NewLine -CellBGColor $CellBGColor -Cell ($Query.LastWriteTime).Count -OutFile $LogFile
WriteReportCell -CellBGColor $CellBGColor -Cell $limit -OutFile $LogFile
WriteReportCell -EndLine -CellBGColor $CellBGColor -Cell $FSize.Length -OutFile $LogFile

$Query = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le ($limit.AddDays($ExpirationDays/2)) -and $_.LastWriteTime -ge $limit} | Sort-Object {$_.LastWriteTime}
$FSize = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le ($limit.AddDays($ExpirationDays/2)) -and $_.LastWriteTime -ge $limit} | Measure-Object -Property length -Sum
$LastMember = ($Query.LastWriteTime).Count - 1
$CellBGColor = "Yellow"
WriteReportCell -NewLine -CellBGColor $CellBGColor -Cell ($Query.LastWriteTime).Count -OutFile $LogFile
WriteReportCell -CellBGColor $CellBGColor -Cell $limit.AddDays(($ExpirationDays/2)) -OutFile $LogFile
WriteReportCell -EndLine -CellBGColor $CellBGColor -Cell $FSize.Length -OutFile $LogFile

$Query = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le ($limit.AddDays($ExpirationDays)) -and $_.LastWriteTime -ge ($limit.AddDays($ExpirationDays/2))} | Sort-Object {$_.LastWriteTime}
$FSize = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer -and $_.LastWriteTime -le ($limit.AddDays($ExpirationDays)) -and $_.LastWriteTime -ge ($limit.AddDays($ExpirationDays/2))} | Measure-Object -Property Length -Sum
$LastMember = ($Query.LastWriteTime).Count - 1
$CellBGColor = "3CFF33"
WriteReportCell -NewLine -CellBGColor $CellBGColor -Cell ($Query.LastWriteTime).Count -OutFile $LogFile
WriteReportCell -CellBGColor $CellBGColor -Cell $limit.AddDays($ExpirationDays) -OutFile $LogFile
WriteReportCell -EndLine -CellBGColor $CellBGColor -Cell $FSize.Length -OutFile $LogFile

$Query = Get-ChildItem -Path $path -Recurse -Force | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime}
$FSize = Get-FileSizeSum -FilePath $path -SizeDisplay MB
$LastMember = ($Query.LastWriteTime).Count - 1
WriteReportCell -NewLine -Cell ($Query.LastWriteTime).Count -OutFile $LogFile
WriteReportCell -Cell $limit.AddDays($ExpirationDays) -OutFile $LogFile
WriteReportCell -EndLine -Cell $FSize.Length -OutFile $LogFile

WriteTableFooter -OutFile $LogFile 


# --- Delete Expired Files
$ReportName = "File Deletion Detail Report"
$ColumnCount = 5
$ColumnNames = "Date","Expire Date","File Name","File Path","File Size"

$Query = Get-ChildItem -File $path -Recurse -Force | Where-Object {!$_.PSIsContainer} | Sort-Object {$_.LastWriteTime}
WriteTableHeader -Title $ReportName -Columns $ColumnCount -ColumnNames $ColumnNames -OutFile $LogFile
Foreach ($File in $Query) {

    $FSize = Format-FileSize((Get-Item $File.FullName).Length)
    If($File.LastWriteTime -le $limit){$CellBGColor = "Red"}
    ElseIf($File.LastWriteTime -le ($limit.AddDays(($ExpirationDays/2)))){$CellBGColor = "Yellow"}
    ElseIf($File.LastWriteTime -le ($limit.AddDays($ExpirationDays))){$CellBGColor = "3CFF33"}
    Else {$CellBGColor = ""}

    WriteReportCell -NewLine -CellBGColor $CellBGColor -Cell $File.LastWriteTime -OutFile $LogFile
    WriteReportCell -CellBGColor $CellBGColor -Cell ($File.LastWriteTime).AddDays($ExpirationDays) -OutFile $LogFile
    WriteReportCell -CellBGColor $CellBGColor -Cell $File.BaseName -OutFile $LogFile
    WriteReportCell -CellBGColor $CellBGColor -Cell $File.Directory -OutFile $LogFile
    WriteReportCell -EndLine -CellBGColor $CellBGColor -Cell $FSize -OutFile $LogFile
    If($File.LastWriteTime -le $limit){Remove-Item $File.FullName -Force}
    }
WriteTableFooter -OutFile $LogFile

# --- Delete Empty Folders
$ReportName = "Delete Empty Folders"
$ColumnCount = 2
$ColumnNames = "Date", "Folder Name"

$Query = Get-ChildItem -Path $path -Recurse -Force | Where-Object { $_.PSIsContainer -and (Get-ChildItem -Path $_.FullName -Recurse -Force | Where-Object { !$_.PSIsContainer }) -eq $null }
WriteTableHeader -Title  $ReportName -Columns $ColumnCount -ColumnNames $ColumnNames -OutFile $LogFile
ForEach ($Folder in $Query) {
    WriteReportCell -NewLine -Cell $Folder.CreationTime -OutFile $LogFile
    WriteReportCell -EndLine -Cell $Folder.FullName -OutFile $LogFile
    Remove-Item $Folder.FullName -Force -Recurse
    }
WriteTableFooter -OutFile $LogFile

WriteReportFooter -OutFile $LogFile

$EmailBody = Get-Content $LogFile | Out-String
SendEmailFile -To $EmailTo -CC $EmailCC -Subject $ScriptTitle -Body $EmailBody -Attachment $LogFile
