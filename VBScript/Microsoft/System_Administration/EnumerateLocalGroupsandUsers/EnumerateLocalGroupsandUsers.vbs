On Error Resume Next

'	Semi-authored by Paul Karl Arthur Kell (paul@kellfamily.org).
'	Most of this script has been quilted together from various freely available scripts on 
'	the web.  Other parts have been added specifically by myself to address specific needs.
'	It has been created to automate tasks at the KapHI Refinery.  Script MUST be run using 
'	wscript.exe.  DO NOT USE cscript.  This script is public domain.

'
'	Global Options
'	Edit based on your own enterprise

'Email Mailsend.exe Location (NO SPACES)
strEmailMailsendLoc 	= "C:\Scripts\apps\"

'Email Output File Option (1 for on, 0 for off)
strEmailOption		= 0
'Email Output File From Address
strEmailFrom		= ""

'Email Output File Return Address
strEmailReturn		= ""

'Email Output File Domain
strEmailDomain		= ""

'Email Output File SMTP Server
strEmailSMTP		= ""

'Email Output File To Address(es) (COMMA SEPARATE MULTIPLE ADDRESSES-NO SPACES)
strEmailTO		= ""

'Email Output File Subject (NO SPACES)
strEmailSub		= "LocalGroupsAndUsersScript"

'Enterprise Name
strEntName		= ""

'Exemption Array of servers not scanned in order they appear in alphabetical order(comma separated/no spaces)
strExempt		= ""

'OU Containing Servers
strServerOU		= "CN=Computers,DC=Contoso,DC=local"

'Output file name (NO SPACES)
strReportFilePre	= "LocalGroupsAndUsersLog"
strReportFileExt	= ".html"	

'Output file path (NO SPACES)
strReportFileLocation	= "c:\scripts\logfiles\"	

'Delete Output File(1 for on, 0 for off)
strDelete		= 0

'Rotate Output File(1 for on, 0 for off)
strRotate		= 1

'Rotate Output Location (NO SPACES)
strRotateLoc		= "c:\scripts\logfiles\LocalGroupsandUsers\"

'GROUP EXCEPTIONS
StrLocalAccountExceptions			= "Administrator,Guest"
strAdministratorsExceptions			= "Administrator,Domain Admins"
strBackupUsersExceptions			= ""
strDistributedComUsersExceptions		= ""
strNetworkConfigurationOperatorsExceptions	= ""
strPerformanceLogUsersExceptions		= "INTERACTIVE,NETWORK SERVICE"
strPerformanceMonitorUsersExceptions		= "MSSQL$SQL2014DEV,MSSQL$SQL2016DEV,MSSQLSERVER,SQLSERVERAGENT,SQLAgent$SQL2014DEV,SQLAgent$SQL2016DEV"
strPowerUsersExceptions				= ""
strPrintOperatorsExceptions			= ""
strRemoteDesktopUsersExceptions			= ""
strReplicatorExceptions				= ""
strUsersExceptions				= "ASPNET,INTERACTIVE,Authenticated Users,Domain Users"
strDebuggerUsersExceptions			= "SYSTEM"
strHelpServicesGroupExceptions			= "SUPPORT_388945a0"
strSMSRCExceptions				= ""
strSophosAdministratorExceptions		= "SYSTEM,Administrator,expadmin,Domain Admins"
strSophosOnAccessExceptions			= ""
strSophosPowerUserExceptions			= ""
strSophosUserExceptions				= "INTERACTIVE,Authenticated Users"
strTelnetUsersExceptions			= ""
'Server Specific Exceptions


'------------------------------------------------------------------------------------------------------------------------
'
'	Constants and Global Variable settings
'	DO NOT EDIT THESE


strReportFile = strReportFilePre & strReportFileExt
Const OpenAsDefault = -2
Const FailIfNotExist = 0
Const ForReading = 1  
Const ForWriting = 2 
Const ForAppending = 8 
Set objFSO = CreateObject("Scripting.FileSystemObject") 
Set ReportFile = objFSO.OpenTextFile (strReportFileLocation & strReportFile, ForAppending, True)
Set objDictionary = CreateObject("scripting.dictionary")
objDictionary.CompareMode = 1
Set dtmStartDate = CreateObject("WbemScripting.SWbemDateTime")
Set dtmEndDate = CreateObject("WbemScripting.SWbemDateTime")

'Set Date Options for logging
DateToCheck = Date - 1
dtmEndDate.SetVarDate Date, True
dtmStartDate.SetVarDate DateToCheck, True



'Set exemptions into dictionary object
ExemptArray = Split(strExempt,",")

For a = 0 to UBound(ExemptArray)
	strComputer = ExemptArray(a)
	objDictionary.Add strComputer, a
Next	
'Local Account Group Exceptions
Set objLocalAccountExceptionDictionary = CreateObject("scripting.dictionary")
objLocalAccountExceptionDictionary.CompareMode = 1
LocalAccountExceptionArray = Split(StrLocalAccountExceptions,",")
For a = 0 to UBound(LocalAccountExceptionArray)
	strLocalAccountException = LocalAccountExceptionArray(a)
	objLocalAccountExceptionDictionary.Add strLocalAccountException, a
Next
'Admin Group Exceptions
Set objAdminExceptionDictionary = CreateObject("scripting.dictionary")
objAdminExceptionDictionary.CompareMode = 1
AdminExceptionArray = Split(strAdministratorsExceptions,",")
For a = 0 to UBound(AdminExceptionArray)
	strAdminException = AdminExceptionArray(a)
	objAdminExceptionDictionary.Add strAdminException, a
Next
'BackupUsers Group Exceptions
Set objBackupUsersExceptionDictionary = CreateObject("scripting.dictionary")
objBackupUsersExceptionDictionary.CompareMode = 1
BackupUsersExceptionArray = Split(strBackupUsersExceptions,",")
For a = 0 to UBound(BackupUsersExceptionArray)
	strBackupUsersException = BackupUsersExceptionArray(a)
	objBackupUsersExceptionDictionary.Add strBackupUsersException, a
Next	
'DistributedComUsers Group Exceptions
Set objDistributedComUsersExceptionDictionary = CreateObject("scripting.dictionary")
objDistributedComUsersExceptionDictionary.CompareMode = 1
DistributedComUsersExceptionArray = Split(strDistributedComUsersExceptions,",")
For a = 0 to UBound(DistributedComUsersExceptionArray)
	strDistributedComUsersException = DistributedComUsersExceptionArray(a)
	objDistributedComUsersExceptionDictionary.Add strDistributedComUsersException, a
Next
'NetworkConfigurationOperators Group Exceptions
Set objNetworkConfigurationOperatorsExceptionDictionary = CreateObject("scripting.dictionary")
objNetworkConfigurationOperatorsExceptionDictionary.CompareMode = 1
NetworkConfigurationOperatorsExceptionArray = Split(strNetworkConfigurationOperatorsExceptions,",")
For a = 0 to UBound(NetworkConfigurationOperatorsExceptionArray)
	strNetworkConfigurationOperatorsException = NetworkConfigurationOperatorsExceptionArray(a)
	objNetworkConfigurationOperatorsExceptionDictionary.Add strNetworkConfigurationOperatorsException, a
Next
'PerformanceLogUsers Group Exceptions
Set objPerformanceLogUsersExceptionDictionary = CreateObject("scripting.dictionary")
objPerformanceLogUsersExceptionDictionary.CompareMode = 1
PerformanceLogUsersExceptionArray = Split(strPerformanceLogUsersExceptions,",")
For a = 0 to UBound(PerformanceLogUsersExceptionArray)
	strPerformanceLogUsersException = PerformanceLogUsersExceptionArray(a)
	objPerformanceLogUsersExceptionDictionary.Add strPerformanceLogUsersException, a
Next
'PerformanceMonitorUsers Group Exceptions
Set objPerformanceMonitorUsersExceptionDictionary = CreateObject("scripting.dictionary")
objPerformanceMonitorUsersExceptionDictionary.CompareMode = 1
PerformanceMonitorUsersExceptionArray = Split(strPerformanceMonitorUsersExceptions,",")
For a = 0 to UBound(PerformanceMonitorUsersExceptionArray)
	strPerformanceMonitorUsersException = PerformanceMonitorUsersExceptionArray(a)
	objPerformanceMonitorUsersExceptionDictionary.Add strPerformanceMonitorUsersException, a
Next
'PowerUsers Group Exceptions
Set objPowerUsersExceptionDictionary = CreateObject("scripting.dictionary")
objPowerUsersExceptionDictionary.CompareMode = 1
PowerUsersExceptionArray = Split(strPowerUsersExceptions,",")
For a = 0 to UBound(PowerUsersExceptionArray)
	strPowerUsersException = PowerUsersExceptionArray(a)
	objPowerUsersExceptionDictionary.Add strPowerUsersException, a
Next
'PrintOperators Group Exceptions
Set objPrintOperatorsExceptionDictionary = CreateObject("scripting.dictionary")
objPrintOperatorsExceptionDictionary.CompareMode = 1
PrintOperatorsExceptionArray = Split(strPrintOperatorsExceptions,",")
For a = 0 to UBound(PrintOperatorsExceptionArray)
	strPrintOperatorsException = PrintOperatorsExceptionArray(a)
	objPrintOperatorsExceptionDictionary.Add strPrintOperatorsException, a
Next
'RemoteDesktopUsers Group Exceptions
Set objRemoteDesktopUsersExceptionDictionary = CreateObject("scripting.dictionary")
objRemoteDesktopUsersExceptionDictionary.CompareMode = 1
RemoteDesktopUsersExceptionArray = Split(strRemoteDesktopUsersExceptions,",")
For a = 0 to UBound(RemoteDesktopUsersExceptionArray)
	strRemoteDesktopUsersException = RemoteDesktopUsersExceptionArray(a)
	objRemoteDesktopUsersExceptionDictionary.Add strRemoteDesktopUsersException, a
Next
'Replicator Group Exceptions
Set objReplicatorExceptionDictionary = CreateObject("scripting.dictionary")
objReplicatorExceptionDictionary.CompareMode = 1
ReplicatorExceptionArray = Split(strReplicatorExceptions,",")
For a = 0 to UBound(ReplicatorExceptionArray)
	strReplicatorException = ReplicatorExceptionArray(a)
	objReplicatorExceptionDictionary.Add strReplicatorException, a
Next
'Users Group Exceptions
Set objUsersExceptionDictionary = CreateObject("scripting.dictionary")
objUsersExceptionDictionary.CompareMode = 1
UsersExceptionArray = Split(strUsersExceptions,",")
For a = 0 to UBound(UsersExceptionArray)
	strUsersException = UsersExceptionArray(a)
	objUsersExceptionDictionary.Add strUsersException, a
Next
'DebuggerUsers Group Exceptions
Set objDebuggerUsersExceptionDictionary = CreateObject("scripting.dictionary")
objDebuggerUsersExceptionDictionary.CompareMode = 1
DebuggerUsersExceptionArray = Split(strDebuggerUsersExceptions,",")
For a = 0 to UBound(DebuggerUsersExceptionArray)
	strDebuggerUsersException = DebuggerUsersExceptionArray(a)
	objDebuggerUsersExceptionDictionary.Add strDebuggerUsersException, a
Next
'HelpServicesGroup Group Exceptions
Set objHelpServicesGroupExceptionDictionary = CreateObject("scripting.dictionary")
objHelpServicesGroupExceptionDictionary.CompareMode = 1
HelpServicesGroupExceptionArray = Split(strHelpServicesGroupExceptions,",")
For a = 0 to UBound(HelpServicesGroupExceptionArray)
	strHelpServicesGroupException = HelpServicesGroupExceptionArray(a)
	objHelpServicesGroupExceptionDictionary.Add strHelpServicesGroupException, a
Next
'SMSRC Group Exceptions
Set objSMSRCExceptionDictionary = CreateObject("scripting.dictionary")
objSMSRCExceptionDictionary.CompareMode = 1
SMSRCExceptionArray = Split(strSMSRCExceptions,",")
For a = 0 to UBound(SMSRCExceptionArray)
	strSMSRCException = SMSRCExceptionArray(a)
	objSMSRCExceptionDictionary.Add strSMSRCException, a
Next
'SophosAdministrator Group Exceptions
Set objSophosAdministratorExceptionDictionary = CreateObject("scripting.dictionary")
objSophosAdministratorExceptionDictionary.CompareMode = 1
SophosAdministratorExceptionArray = Split(strSophosAdministratorExceptions,",")
For a = 0 to UBound(SophosAdministratorExceptionArray)
	strSophosAdministratorException = SophosAdministratorExceptionArray(a)
	objSophosAdministratorExceptionDictionary.Add strSophosAdministratorException, a
Next	
'SophosOnAccess Group Exceptions
Set objSophosOnAccessExceptionDictionary = CreateObject("scripting.dictionary")
objSophosOnAccessExceptionDictionary.CompareMode = 1
SophosOnAccessExceptionArray = Split(strSophosOnAccessExceptions,",")
For a = 0 to UBound(SophosOnAccessExceptionArray)
	strSophosOnAccessException = SophosOnAccessExceptionArray(a)
	objSophosOnAccessExceptionDictionary.Add strSophosOnAccessException, a
Next
'SophosPowerUser Group Exceptions
Set objSophosPowerUserExceptionDictionary = CreateObject("scripting.dictionary")
objSophosPowerUserExceptionDictionary.CompareMode = 1
SophosPowerUserExceptionArray = Split(strSophosPowerUserExceptions,",")
For a = 0 to UBound(SophosPowerUserExceptionArray)
	strSophosPowerUserException = SophosPowerUserExceptionArray(a)
	objSophosPowerUserExceptionDictionary.Add strSophosPowerUserException, a
Next
'SophosUser Group Exceptions
Set objSophosUserExceptionDictionary = CreateObject("scripting.dictionary")
objSophosUserExceptionDictionary.CompareMode = 1
SophosUserExceptionArray = Split(strSophosUserExceptions,",")
For a = 0 to UBound(SophosUserExceptionArray)
	strSophosUserException = SophosUserExceptionArray(a)
	objSophosUserExceptionDictionary.Add strSophosUserException, a
Next
'TelnetUsers Group Exceptions
Set objTelnetUsersExceptionDictionary = CreateObject("scripting.dictionary")
objTelnetUsersExceptionDictionary.CompareMode = 1
TelnetUsersExceptionArray = Split(strTelnetUsersExceptions,",")
For a = 0 to UBound(TelnetUsersExceptionArray)
	strTelnetUsersException = TelnetUsersExceptionArray(a)
	objTelnetUsersExceptionDictionary.Add strTelnetUsersException, a
Next


'
'	Initializing HTML Tags for better formatting
'
ReportFile.writeline("<html>") 
ReportFile.writeline("<head>") 
ReportFile.writeline("<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>") 
ReportFile.writeline("<title>Local Groups and Users on HonBlue Servers</title>") 
ReportFile.writeline("<style type='text/css'>") 
ReportFile.writeline("<!--") 
ReportFile.writeline("td {") 
ReportFile.writeline("font-family: Tahoma;") 
ReportFile.writeline("font-size: 11px;") 
ReportFile.writeline("border-top: 1px solid #999999;") 
ReportFile.writeline("border-right: 1px solid #999999;") 
ReportFile.writeline("border-bottom: 1px solid #999999;") 
ReportFile.writeline("border-left: 1px solid #999999;") 
ReportFile.writeline("padding-top: 2px;") 
ReportFile.writeline("padding-right: 2px;") 
ReportFile.writeline("padding-bottom: 2px;") 
ReportFile.writeline("padding-left: 2px;") 
ReportFile.writeline("}") 
ReportFile.writeline("body {") 
ReportFile.writeline("margin-left: 5px;") 
ReportFile.writeline("margin-top: 5px;") 
ReportFile.writeline("margin-right: 0px;") 
ReportFile.writeline("margin-bottom: 10px;") 
ReportFile.writeline("") 
ReportFile.writeline("table {") 
ReportFile.writeline("border: thin solid #000000;") 
ReportFile.writeline("}") 
ReportFile.writeline("-->") 
ReportFile.writeline("</style>") 
ReportFile.writeline("</head>") 
ReportFile.writeline("<body>")  
ReportFile.writeline("<table>") 
ReportFile.writeline("<tr bgcolor='#CCCCCC'>") 
ReportFile.writeline("<td height='25' align='center'>") 
ReportFile.writeline("<font face='tahoma' color='#003399' size='2'><strong>Local Groups and Users on " & strEntName & " Servers</strong><br>" & Date & "  " & Time & "</font>") 
ReportFile.writeline("</td>") 
ReportFile.writeline("</tr><tr><td align=center>") 

'
' Local Accounts and Group Members
'
	
	ReportFile.writeline("<table width='85%'>") 

Set ServerNames = GetObject ("LDAP://" & strServerOU)
colItems.Filter = Array("Computer")

For Each objItem in ServerNames
	strComputer = objItem.CN
	If objDictionary.Exists(strComputer) Then
		 ReportFile.Writeline("<tr><td bgcolor=FFFF00>" & strComputer & "</td><td align=center colspan=3 bgcolor=FFFF00>Server Administratively Exempted</td></tr>")
	Else	


	ReportFile.writeline("<tr bgcolor='#CCCCCC'>") 
	ReportFile.writeline("<td colspan='4' height='25' align='center'>") 
	ReportFile.writeline("<font face='tahoma' color='#003399' size='2'><strong>" & strComputer & "</strong></font></td></tr>") 
	
	Set objNetwork = CreateObject("Wscript.Network")
	Set colAccounts = GetObject("WinNT://" & strComputer & "")

	colAccounts.Filter = Array("user")
	
	ReportFile.writeline("<tr bgcolor='#CCCCCC'><td colspan=4><strong>All Local Accounts</strong></td></tr><tr>")
	colnum=0
	strLocalAdmin = "!" & strComputer
	For Each objUser In colAccounts
		strUsername = objUser.Name
		If objLocalAccountExceptionDictionary.Exists(strUsername) Then
			strBGcolor = "#008000"
		ElseIf LCase(strUsername) = LCase(strLocalAdmin) Then					
			strBGcolor = "#008000"		
		ElseIf strUsername = "Guest" Then
			strBGcolor = "#FF0000"
		Else
			strBGcolor = "#FF0000"
		End If
		colnum = colnum + 1
		If colnum > 4 Then
			ReportFile.Writeline("</tr><tr>")
			ReportFile.writeline("<td bgcolor=" & strBGcolor & "><font color=white>" & objuser.Name & "</td>")
		colnum = 1
	
		Else
			ReportFile.writeline("<td bgcolor=" & strBGcolor & "><font color=white>" & objuser.Name & "</td>")
		End If
	Next

	ReportFile.writeline("<tr bgcolor='#CCCCCC'><td colspan=4><strong>All Local Groups</strong></td></tr>")

	Set colGroups = GetObject("WinNT://" & strComputer & "")
	colGroups.Filter = Array("group")
	For Each objGroup In colGroups

		ReportFile.Write("<tr><td colspan=4 align=center><strong>" & objGroup.Name & "</strong></td></tr>") 
		colnum = 0
		
		For Each objUser in objGroup.Members
			
			strUsername = objUser.Name
			strUserDomain	= objUser.Domain
			
			If objGroup.Name = "Administrators" Then
				If objAdminExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				ElseIf LCase(strUsername) = LCase(strLocalAdmin) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If
			ElseIf objGroup.Name = "Backup Operators" Then
				If objBackupUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "Distributed COM Users" Then
				If objDistributedComUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "Guests" Then
				If strUsername = "Guest" Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If		
			ElseIf objGroup.Name = "Network Configuration Operators" Then
				If objNetworkConfigurationOperatorsExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If				
			ElseIf objGroup.Name = "Performance Log Users" Then
				If objPerformanceLogUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If			
			ElseIf objGroup.Name = "Performance Monitor Users" Then
				If objPerformanceMonitorUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If		
			ElseIf objGroup.Name = "Power Users" Then
				If objPowerUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If		
			ElseIf objGroup.Name = "Print Operators" Then
				If objPrintOperatorsExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If		
			ElseIf objGroup.Name = "Remote Desktop Users" Then
				If objRemoteDesktopUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If																												
			ElseIf objGroup.Name = "Replicator" Then
				If objReplicatorExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "Users" Then
				If objUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "SophosAdministrator" Then
				If objUsersExceptionDictionary.Exists(strSophosAdministrator) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "SophosOnAccess" Then
				If objUsersExceptionDictionary.Exists(strSophosOnAccess) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "SophosPowerUser" Then
				If objUsersExceptionDictionary.Exists(strSophosPowerUser) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "SophosUser" Then
				If objUsersExceptionDictionary.Exists(strSophosUser) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "Debugger Users" Then
				If objDebuggerUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "HelpServicesGroup" Then
				If objHelpServicesGroupExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "SMSRC" Then
				If objSMSRCExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
			ElseIf objGroup.Name = "TelnetClients" Then
				If objTelnetUsersExceptionDictionary.Exists(strUsername) Then
					strBGcolor = "#008000"
				Else
					strBGcolor = "#FF0000"
				End If	
				
			Else
				strBGcolor = "#FFA500"
			End If	

			colnum = colnum + 1
			If colnum > 4 Then
				ReportFile.Writeline("</tr><tr>")
				ReportFile.writeline("<td bgcolor ='" & strBGcolor & "'><font color=white>" & strUserDomain & "\" & objUser.Name & "</td>")
				colnum = 1
	
			Else
				ReportFile.writeline("<td bgcolor ='" & strBGcolor & "'><font color=white>" & strUserDomain & "\" & objUser.Name & "</td>")
			End If
		Next
	Next
		
End If
Next
	
	ReportFile.writeline("</table>") 

'
'Page Footer
'

Set objNTInfo = CreateObject("WinNTSystemInfo")
strScriptFullName = Wscript.ScriptName
Set objFso = CreateObject("Scripting.FileSystemObject")
Set objFile = objFso.GetFile(strScriptFullName)

ReportFile.writeline("<table>") 
ReportFile.writeline("<tr bgcolor='#CCCCCC'>") 
ReportFile.writeline("<td colspan='7' height='25' align='center'><font size = -2>") 
ReportFile.WriteLine("Report Prepared by<strong> " & objNTInfo.Computername & " " & Wscript.ScriptFullName & "</strong><br>")
Set objWMIService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\" & objNTInfo.Computername & "\root\cimv2") 
Set colProcess = objWMIService.ExecQuery("Select * from Win32_Process")

For Each objProcess in colProcess
		If objProcess.Name = "wscript.exe" Then
			colProperties = objProcess.GetOwner(strNameOfUser,strUserDomain)
			ReportFile.WriteLine("Script run using <strong>" & objProcess.Name & "</strong> By <strong>" & strUserDomain & "\" & strNameOfUser & "</strong><br>")
		End If
Next
ReportFile.WriteLine("Script run against <strong>" & strServerOU & "</strong> OU<br>")
ReportFile.WriteLine("Script written by <strong><a href='mailto:paul@kellfamily.org?subject=" & WScript.ScriptName & " Feedback'>Paul Karl Arthur Kell</a></strong> and last edited <strong>" & objFile.DateLastModified & "</strong>")
ReportFile.WriteLine("</td></tr></table></td><tr></table></body></html>")
ReportFile.Close


'
'Email Nightly Report
'
'	Dim Shell
'	Set shell=CreateObject("wscript.shell")
'	objShell.Run "CMD /K /S 


If strEmailOption = 1 Then
	Dim Shell
	Set shell=CreateObject("wscript.shell")
	shell.run strEmailMailsendLoc & "mailsend.exe -f " & strEmailFrom & " -rt " & strEmailReturn & " -d " & strEmailDomain & " -smtp " & strEmailSMTP & " -t " & strEmailTO & " +cc +bc -sub " & strEmailSub & " -a " & strReportFileLocation & strReportFile & ",text/html,i"
Wscript.sleep 10000
Set shell=nothing
End If

'
'Delete Report
'

If strDelete = 1 Then
	
	strDeleteFile = strReportFileLocation & strReportFile
	objFSO.DeleteFile(strDeleteFile)
End If

'
'Rotate Output File
'

If strRotate = 1 Then
	Function padDate(intNumber)
		if intNumber <= 9 Then
			padDate = "0" & CStr(intNumber)
		Else
			padDate = CStr(intNumber)
		End If
	End Function

	Set objFSO = CreateObject("Scripting.FileSystemObject")
	strDate = "-" & Year(Date) & "-" & padDate(Month(Date)) & "-" & padDate(Day(Date))

'When moving output file ensure version control
	Do until strFileMoveSuccess = 1
		If objFSO.FileExists(strRotateLoc & strReportFilePre & strdate & strFileVersion & strReportFileExt) Then
			strFileVersion = strFileVersion - 1
		Else
			objFSO.MoveFile strReportFileLocation & strReportFile, strRotateLoc & strReportFilePre & strdate & strFileVersion & strReportFileExt
			strFileMoveSuccess = 1
		End If
	Loop
End If
