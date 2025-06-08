Function WriteReportHeader
    {
param( [string]$Title, [int]$Columns, [Switch]$NoColumnNames, [string[]]$ColumnNames, [string]$OutFile, [string]$CSV)
$Header = @"
<HTML><HEAD>

<Title>$Title $(Get-Date)</Title>
<style>
    body { background-color:#737373; font-family:Segoe UI; font-size:10pt; }
    td, th { border:0px solid black; border-collapse:collapse; white-space:pre; }
    th { color:black; background-color:#a6a6a6; }
    table, tr, td, th { padding:2px; margin:0px; white-space:pre; }
    tr:nth-child(odd) { background-color:#d9d9d9; }
    tr:nth-child(even) { background-color:#f2f2f2; }
    table { width:95%; margin-left:5px; margin-bottom:20px; background-color:#ffffff; }
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
param([string]$Cell,[string]$CellBGColor,[Switch]$NewLine,[Switch]$AlignLeft,[Switch]$EndLine,[string]$OutFile,[int]$Span)
If($Span){$ColSpan=$Span} else {$ColSpan=1}
If($AlignLeft){$Align="Left"} else {$Align="Center"}
If($NewLine){"<tr>" | Out-File -Append -FilePath $OutFile}
"<td align=$Align colspan=$ColSpan bgcolor=$CellBGColor>$Cell</td>" | Out-File -Append -FilePath $OutFile
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
        Send-MailMessage -SmtpServer $EmailServer -From $login -Subject $Subject -To $To -CC $CC -UseSsl -port 587 -Attachments $Attachment -BodyAsHtml -Body $Body -Credential $credentials
    }

Function WriteTableHeader
    {
    param( [string]$Title, [int]$Columns, [string[]]$ColumnNames, [Switch]$NoColumnNames, [string]$OutFile, [string]$CSV)
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

Function WriteTableFooter
    {
    param([string]$OutFile)
    $Referrer = $MyInvocation.PSCommandPath
    $LastModified = Get-ChildItem $Referrer | ForEach{$_.LastWriteTime}
    $Footer = "</TABLE>"
    $Footer| Out-File -FilePath $OutFile -Append
    }    
