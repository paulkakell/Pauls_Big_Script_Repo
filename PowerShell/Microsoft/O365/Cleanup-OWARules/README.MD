# Cleanup-OWARules
This PowerShell script is designed to clean up erroring OWA (Outlook Web App) rules from user mailboxes in Exchange Online. It connects to Exchange Online, retrieves all user mailboxes, identifies erroring OWA rules, and removes them.
## Prerequisites
* Windows PowerShell 5.1 or later
* Exchange Admin Permissions
* Exchange Online Management Module installed
To install the Exchange Online Management Module, open PowerShell as an administrator and run:
`Install-Module -Name ExchangeOnlineManagement`
## Usage
1. Save the script in a file named CleanUpOWARules.ps1.
2. Open PowerShell and navigate to the directory containing the script.
3. Run the script using the command:  
`.\CleanUp-OWARules.ps1`  

The script will prompt you for your Office 365 admin credentials. After providing the credentials, it will process each mailbox, removing erroring OWA rules.
