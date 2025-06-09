function Wait-RateLimit {
    [CmdletBinding()]                                                    # Enables advanced function features
    param(
        [Parameter(Mandatory)][int]$ActionCount,                        # Total number of actions to distribute over the interval
        [int]$Seconds,                                                  # Seconds portion of the time window
        [int]$Minutes,                                                  # Minutes portion of the time window
        [int]$Hours,                                                    # Hours portion of the time window
        [int]$Days                                                      # Days portion of the time window
    )

    # Ensure at least one time unit was specified
    if (!($Seconds -or $Minutes -or $Hours -or $Days)) {
        throw 'Specify at least one time interval.'
    }

    # Convert all specified time units into a total count of seconds
    $interval = $Seconds + ($Minutes * 60) + ($Hours * 3600) + ($Days * 86400)

    # Validate that the computed interval is positive
    if ($interval -le 0) {
        throw 'Interval must be greater than zero.'
    }

    # Calculate the delay between each action to spread them evenly
    $delay = [double]$interval / $ActionCount

    # Pause execution for the computed delay
    Start-Sleep -Seconds $delay
}
