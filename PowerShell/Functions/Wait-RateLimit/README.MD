# Wait-RateLimit

Wait-RateLimit is a lightweight PowerShell function that evenly spreads actions across a defined time window. By calculating the precise delay between each action, it prevents rate-limit errors and ensures steady throughput.

## Requirements

- PowerShell 5.1 or later

## Installation

Save the function to your profile or module file (e.g. `RateLimiter.psm1`) and import it:

```powershell
Import-Module RateLimiter.psm1
