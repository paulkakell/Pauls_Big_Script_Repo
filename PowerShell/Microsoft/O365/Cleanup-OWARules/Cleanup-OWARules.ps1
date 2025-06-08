# Connect to Exchange Online
$UserCredential = Get-Credential
$ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $UserCredential -Authentication Basic -AllowRedirection
Import-PSSession $ExchangeSession -DisableNameChecking

# Retrieve all user mailboxes
$Mailboxes = Get-Mailbox -ResultSize Unlimited

# Loop through each user mailbox
foreach ($Mailbox in $Mailboxes) {
    Write-Host "Processing mailbox: $($Mailbox.PrimarySmtpAddress)"
    
    # Get inbox rules
    $InboxRules = Get-InboxRule -Mailbox $Mailbox.PrimarySmtpAddress
    
    # Loop through each rule
    foreach ($Rule in $InboxRules) {
        # Check if the rule is in an error state
        if ($Rule.RuleErrorActionRequired -eq $true) {
            Write-Host "Removing erroring rule: $($Rule.Name)"
            
            # Remove erroring rule
            Remove-InboxRule -Mailbox $Mailbox.PrimarySmtpAddress -Identity $Rule.Identity -Confirm:$false
        }
    }
}

# End the Exchange Online session
Remove-PSSession $ExchangeSession
