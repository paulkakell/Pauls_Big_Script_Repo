# --- Variables
$client_id = 'YOUR_CLIENT_ID'
$client_secret = 'YOUR_CLIENT_SECRET'
$user_agent = 'YOUR_USER_AGENT'
$username = 'YOUR_REDDIT_USERNAME'
$password = 'YOUR_REDDIT_PASSWORD'

# Install required modules if not already installed
if (-not (Get-Module -ListAvailable -Name 'PSReadline')) {
    Install-Module -Name PSReadline -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import necessary modules
Import-Module PSReadline

# Get the authentication token (OAuth2)
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${client_id}:${client_secret}"))
$authHeader = @{
    "Authorization" = "Basic $auth"
    "User-Agent" = $user_agent
}

# Get the access token
$response = Invoke-RestMethod -Uri 'https://www.reddit.com/api/v1/access_token' -Method Post -Headers $authHeader -Body @{
    grant_type = 'password'
    username = $username
    password = $password
} -ContentType 'application/x-www-form-urlencoded'

$access_token = $response.access_token

# Get user posts and comments
$userPosts = Invoke-RestMethod -Uri "https://oauth.reddit.com/user/$username/submitted" -Headers @{ 
    "Authorization" = "Bearer $access_token"; 
    "User-Agent" = $user_agent
}

$userComments = Invoke-RestMethod -Uri "https://oauth.reddit.com/user/$username/comments" -Headers @{ 
    "Authorization" = "Bearer $access_token"; 
    "User-Agent" = $user_agent
}

# Helper function to delete posts/comments
function Delete-RedditPostOrComment {
    param (
        [string]$thingId
    )
    $result = Invoke-RestMethod -Uri "https://oauth.reddit.com/api/del" -Method Post -Headers @{ 
        "Authorization" = "Bearer $access_token"; 
        "User-Agent" = $user_agent
    } -Body @{
        id = $thingId
    }

    return $result
}

# Helper function to check rate limit and pause if necessary
function Check-RateLimit {
    param (
        [Hashtable]$headers
    )

    $remainingRequests = $headers['X-Ratelimit-Remaining']
    $resetTime = $headers['X-Ratelimit-Reset']
    $limit = $headers['X-Ratelimit-Limit']

    if ($remainingRequests -eq 0) {
        $resetEpoch = [datetime]::ParseExact($resetTime, 'yyyy-MM-ddTHH:mm:ssZ', $null)
        $timeToWait = $resetEpoch - (Get-Date)
        Write-Host "Rate limit hit. Sleeping for $($timeToWait.TotalSeconds) seconds."
        Start-Sleep -Seconds $timeToWait.TotalSeconds
    }
}

# Get the current date and filter posts/comments by karma and age
$currentDate = Get-Date
$oneMonthAgo = $currentDate.AddMonths(-1)

# Check posts
foreach ($post in $userPosts.data.children) {
    $postDate = [System.DateTime]::ParseExact($post.data.created_utc, 'yyyy-MM-ddTHH:mm:ssZ', $null)
    if ($postDate -lt $oneMonthAgo -and $post.data.score -lt 0) {
        Write-Host "Deleting post: $($post.data.title)"
        $result = Delete-RedditPostOrComment -thingId $post.data.name

        # Check rate limit
        Check-RateLimit -headers $result.PSObject.Properties
    }
}

# Check comments
foreach ($comment in $userComments.data.children) {
    $commentDate = [System.DateTime]::ParseExact($comment.data.created_utc, 'yyyy-MM-ddTHH:mm:ssZ', $null)
    if ($commentDate -lt $oneMonthAgo -and $comment.data.score -lt 0) {
        Write-Host "Deleting comment: $($comment.data.body)"
        $result = Delete-RedditPostOrComment -thingId $comment.data.name

        # Check rate limit
        Check-RateLimit -headers $result.PSObject.Properties
    }
}

Write-Host "Script completed."
