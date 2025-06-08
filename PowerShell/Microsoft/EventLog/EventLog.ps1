# --- Variables
$ScriptTitle = "Event Logs " + $env:COMPUTERNAME
$LogFileName = ($ScriptTitle -replace '\s','_') + "_" + $(Get-Date -Format yy_MM_dd_HHmm)
$FullLogFileName = $LogFileName + ".html"
$LogPath = "C:\Scripts\Logfiles\EventLogs\"
$LogFile = $LogPath + $FullLogFileName
$EmailTo = ""
$EmailCC = ""
$EmailSubject = $ScriptTitle
$Date = (Get-date).AddHours(-25)

# --- Functions
Function WriteReportHeader
    {
param( [string]$Title, [int]$Columns, [Switch]$NoColumnNames, [string[]]$ColumnNames, [string]$OutFile, [string]$CSV)
$Header = @"
<HTML><HEAD>

<Title>$Title $(Get-Date)</Title>
<style>
    body { background-color:#737373; font-family:Segoe UI; font-size:10pt; }
    td, th {  border:0px solid black; border-collapse:collapse;  }
    th { max-width:40%; color:black; background-color:#a6a6a6; }
    td { white-space:pre-wrap; word-wrap: break-word;}
    table, tr, td, th { padding:2px; margin:0px;}
    tr:nth-child(odd) { background-color:#d9d9d9; }
    tr:nth-child(even) { background-color:#f2f2f2; }
    table { width:95%; margin-left:5px; margin-bottom:20px; background-color:#ffffff; align:center; }
    .footer { font-size:6pt; padding:2px; margin:0px; white-space:pre; width:95%; margin-left:5px; margin-bottom:20px; background-color:#ffffff; }
</style>
</HEAD><BODY>
"@
$Header | Out-File -FilePath $OutFile
"<Table border='1'><tr><th colspan=$Columns><b>$Title $(Get-Date)</b></th></tr><tr>" | Out-File -Append -FilePath $OutFile

If($NoColumnNames){
    } Else {
        ForEach($ColumnName in $ColumnNames)
        {
            "<th><b>$ColumnName</th>" | Out-File -Append -FilePath $OutFile
        }
    }
"</tr>" | Out-File -Append -FilePath $OutFile  
}

Function WriteReportCell 
    {
param([string]$Cell,[string]$CellBGColor,[Switch]$NewLine,[Switch]$AlignLeft,[Switch]$EndLine,[string]$OutFile)
If($AlignLeft){$Align="Left"} else {$Align="Center"}
If($NewLine){"<tr>" | Out-File -Append -FilePath $OutFile}
"<td style='max-width:50%; word-break:break-word; ' align=$Align bgcolor=$CellBGColor>$Cell</td>" | Out-File -Append -FilePath $OutFile
If($EndLine){"</tr>" | Out-File -Append -FilePath $OutFile}
    }

Function WriteReportFooter
    {
    param([string]$OutFile)
    $Referrer = $MyInvocation.PSCommandPath
    $LastModified = Get-ChildItem $Referrer | ForEach{$_.LastWriteTime}
    $Footer = @"
    </TABLE><TABLE class='footer'>
    <tr><td>Written By: <A href='mailto:paul@kellfamily.org'>Paul Kell</a></td><td>Last Modified: $LastModified</td></tr>
    <tr><td>Script Run By: $env:userdomain\$env:username</td><td>Script Run From: $env:computername</td></tr>
    <tr><td>Script Path: $Referrer</td><td>Log File: $OutFile</td></tr>
    </TABLE></TABLE></BODY></HTML>"  
"@
$Footer| Out-File -FilePath $OutFile -Append
}

Function SendEmailFile
    {
    param( [string]$To, [string]$CC, [string]$Subject, [string]$Body, [string]$Attachment)
    $EmailServer = ""
    $login = ""
    $password = ""| Convertto-SecureString -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.Pscredential -Argumentlist $login,$password
    #-Cc $CC
    Send-MailMessage -SmtpServer $EmailServer -From $login -Subject $Subject -To $To -CC $CC -UseSsl -port 587 -Attachments $Attachment -BodyAsHtml -Body $Body -Credential $credentials
    }

Function WriteTableHeader
    {
    param( [string]$Title, [int]$Columns, [string[]]$ColumnNames, [Switch]$NoColumnNames, [string]$OutFile, [string]$CSV)

    "<Table border='1' width='90%'><tr><th colspan=$Columns><b>$Title $(Get-Date)</b></th></tr><tr>" | Out-File -Append -FilePath $OutFile
    If($NoColumnNames){
    } Else {
        ForEach($ColumnName in $ColumnNames)
        {
            "<th><b>$ColumnName</th>" | Out-File -Append -FilePath $OutFile
        }
    }
    "</tr>" | Out-File -Append -FilePath $OutFile  
    }

Function WriteTableFooter
    {
    param([string]$OutFile)
    $Referrer = $MyInvocation.PSCommandPath
    $LastModified = Get-ChildItem $Referrer | ForEach{$_.LastWriteTime}
    $Footer = "</TABLE>"
    $Footer| Out-File -FilePath $OutFile -Append
    }    

# --- Start Script
$CmdOutput =""
CLS
New-Item -ItemType Directory -Force -Path $LogPath

WriteReportHeader -Title "$ScriptTitle" -Columns 1 -NoColumnNames -OutFile $LogFile
    WriteReportCell -NewLine -Cell $null -OutFile $LogFile

    
    WriteTableHeader -Title "Application Event Log" + $(Get-Date -Format yy_MM_dd_HHmm) -Columns 6 -ColumnNames IndexID,TimeGenerated,EntryType,Source,InstanceID#,Message  -OutFile $LogFile
        $LogOutput = Get-EventLog -ComputerName $env:COMPUTERNAME -After $Date -LogName Application -EntryType FailureAudit,Error,Warning -Verbose | Select Index,TimeGenerated,EntryType,Source,InstanceID,Message 
        ForEach ($LogEntry in $LogOutput) {
            WriteReportCell -NewLine -Cell $LogEntry.Index -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.TimeGenerated -OutFile $LogFile 
            If($LogEntry.EntryType -eq "Error") {$CellBG="Red"
            }ElseIf($LogEntry.EntryType -eq "Warning") {$CellBG="Yellow"
            }else{$CellBG = ""}           
            WriteReportCell -CellBGColor $CellBG -Cell $LogEntry.EntryType -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.Source -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.InstanceID -OutFile $LogFile
            WriteReportCell -EndLine -AlignLeft -Cell $LogEntry.Message -OutFile $LogFile
        } 
    WriteTableFooter -OutFile $LogFile

    WriteTableHeader -Title "System Event Log" + $(Get-Date -Format yy_MM_dd_HHmm) -Columns 6 -ColumnNames IndexID,TimeGenerated,EntryType,Source,InstanceID#,Message  -OutFile $LogFile
        $LogOutput = Get-EventLog -ComputerName $env:COMPUTERNAME -After $Date -LogName System -EntryType FailureAudit,Error,Warning -Verbose | Select Index,TimeGenerated,EntryType,Source,InstanceID,Message 
        ForEach ($LogEntry in $LogOutput) {
            WriteReportCell -NewLine -Cell $LogEntry.Index -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.TimeGenerated -OutFile $LogFile 
            If($LogEntry.EntryType -eq "Error") {$CellBG="Red"
            }ElseIf($LogEntry.EntryType -eq "Warning") {$CellBG="Yellow"
            }else{$CellBG = ""}           
            WriteReportCell -CellBGColor $CellBG -Cell $LogEntry.EntryType -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.Source -OutFile $LogFile
            WriteReportCell -Cell $LogEntry.InstanceID -OutFile $LogFile
            WriteReportCell -EndLine -AlignLeft -Cell $LogEntry.Message -OutFile $LogFile
        } 
    WriteTableFooter -OutFile $LogFile

WriteReportFooter -OutFile $LogFile


$EmailBody = Get-Content $LogFile | Out-String
SendEmailFile -To $EmailTo -CC $EmailCC -Subject $LogFileName -Body $EmailBody -Attachment $LogFile
