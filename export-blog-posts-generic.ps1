# Generic Blog Post Export Script - Option 2 (Web-based)
# This script extracts blog post metadata WITHOUT requiring local HTML files
# Instead, it works with URLs and fetches content on-demand via HTTP requests

param(
    [string]$BlogURL = "https://example-blog.com",
    [string]$PostsDirectory = "c:\blog\src\posts",
    [string]$OutputFile = "blog-export.csv",
    [datetime]$StartDate = (Get-Date).AddYears(-5),
    [datetime]$EndDate = (Get-Date),
    [switch]$UseLocalFiles = $false,
    [int]$RequestTimeout = 10
)

# Normalize BlogURL - add https:// if protocol is missing
if ($BlogURL -notmatch '^https?://') {
    $BlogURL = "https://$BlogURL"
}

# Load required assemblies
Add-Type -AssemblyName "System.Web"

# Category mapping - normalize raw categories to standard groups
# Uses uppercase keys only to avoid case sensitivity issues in PowerShell hash tables
$categoryMapping = @{
    'AI'                         = 'Artificial Intelligence'
    'MACHINE LEARNING'           = 'Artificial Intelligence'
    'ML'                         = 'Artificial Intelligence'
    'LLM'                        = 'Artificial Intelligence'
    'GENERATIVE AI'              = 'Artificial Intelligence'
    'COPILOT'                    = 'Artificial Intelligence'
    'SECURITY COPILOT'           = 'Artificial Intelligence'
    'ARTIFICIAL INTELLIGENCE'    = 'Artificial Intelligence'
    'AZURE'                      = 'Cloud'
    'CLOUD'                      = 'Cloud'
    'MICROSOFT AZURE'            = 'Cloud'
    'AZURE SERVICES'             = 'Cloud'
    'AZURE RESOURCE MANAGER'     = 'Cloud'
    'ARM'                        = 'Cloud'
    'SECURITY'                   = 'Security'
    'AI SECURITY'                = 'Security'
    'CLOUD SECURITY'             = 'Security'
    'DATA SECURITY'              = 'Security'
    'CYBERSECURITY'              = 'Security'
    'M365 SECURITY'              = 'Security'
    'DEFENDER'                   = 'Security'
    'DEFENDER FOR CLOUD'         = 'Security'
    'MICROSOFT DEFENDER'         = 'Security'
    'SENTINEL'                   = 'Security'
    'MICROSOFT SENTINEL'         = 'Security'
    'INCIDENT RESPONSE'          = 'Security'
    'THREAT MANAGEMENT'          = 'Security'
    'COMPLIANCE'                 = 'Security'
    'MICROSOFT SECURITY UPDATES' = 'Security'
    'IDENTITY'                   = 'Identity'
    'ENTRA'                      = 'Identity'
    'ENTRA ID'                   = 'Identity'
    'MICROSOFT ENTRA'            = 'Identity'
    'AZURE AD'                   = 'Identity'
    'AZURE ACTIVE DIRECTORY'     = 'Identity'
    'IAM'                        = 'Identity'
    'ACCESS MANAGEMENT'          = 'Identity'
    'CONDITIONAL ACCESS'         = 'Identity'
    'MFA'                        = 'Identity'
    'AUTHENTICATION'             = 'Identity'
    'ZERO TRUST'                 = 'Identity'
    'CROSS-TENANT ACCESS'        = 'Identity'
    'ENTRA PRIVATE ACCESS'       = 'Identity'
    'MANAGEMENT'                 = 'Management'
    'AUTOMATION'                 = 'Management'
    'INTUNE'                     = 'Management'
    'MDM'                        = 'Management'
    'ENDPOINT MANAGEMENT'        = 'Management'
    'CONFIGURATION MANAGER'      = 'Management'
    'GOVERNANCE'                 = 'Management'
    'POLICY'                     = 'Management'
    'MONITORING'                 = 'Management'
    'DEVELOPMENT'                = 'Development'
    'DEVOPS'                     = 'Development'
    'CI/CD'                      = 'Development'
    'GITHUB'                     = 'Development'
    'DEVELOPER'                  = 'Development'
    'PROGRAMMING'                = 'Development'
    'CODE'                       = 'Development'
    'SOFTWARE'                   = 'Development'
    'COLLABORATION'              = 'Collaboration'
    'MICROSOFT 365'              = 'Collaboration'
    'M365'                       = 'Collaboration'
    'TEAMS'                      = 'Collaboration'
    'MICROSOFT TEAMS'            = 'Collaboration'
    'SHAREPOINT'                 = 'Collaboration'
    'EXCHANGE'                   = 'Collaboration'
    'OUTLOOK'                    = 'Collaboration'
    'OFFICE 365'                 = 'Collaboration'
    'OFFICE'                     = 'Collaboration'
    'DATA'                       = 'Data'
    'ANALYTICS'                  = 'Data'
    'BI'                         = 'Data'
    'BUSINESS INTELLIGENCE'      = 'Data'
    'POWER BI'                   = 'Data'
    'SQL'                        = 'Data'
    'DATABASE'                   = 'Data'
    'KUSTO'                      = 'Data'
    'KQL'                        = 'Data'
    'LEARNING'                   = 'Learning'
    'TRAINING'                   = 'Learning'
    'CERTIFICATION'              = 'Learning'
    'COURSE'                     = 'Learning'
    'EDUCATION'                  = 'Learning'
    'COMMUNITY'                  = 'Community'
    'MVP'                        = 'Community'
    'USER GROUP'                 = 'Community'
    'CONFERENCE'                 = 'Community'
    'EVENT'                      = 'Community'
    'COMPANY CULTURE'            = 'Community'
    'UPDATES'                    = 'Updates'
    'NEWS'                       = 'Updates'
    'ANNOUNCEMENTS'              = 'Updates'
    'RELEASE NOTES'              = 'Updates'
    'AMA'                        = 'Updates'
    'DISPLAY'                    = 'Development'
}

# Function to normalize category using smart matching
function Normalize-Category {
    param(
        [string]$RawCategory
    )
    
    if (-not $RawCategory -or $RawCategory.Trim() -eq '') {
        return 'Uncategorized'
    }
    
    $trimmed = $RawCategory.Trim()
    
    # Direct mapping
    if ($categoryMapping.ContainsKey($trimmed)) {
        return $categoryMapping[$trimmed]
    }
    
    # Case-insensitive exact match
    $upperCat = $trimmed.ToUpper()
    if ($categoryMapping.ContainsKey($upperCat)) {
        return $categoryMapping[$upperCat]
    }
    
    # Partial matching - find if category contains or is contained in a mapping key
    foreach ($key in $categoryMapping.Keys) {
        if ($upperCat.Contains($key.ToUpper()) -or $key.ToUpper().Contains($upperCat)) {
            return $categoryMapping[$key]
        }
    }
    
    # Keyword-based matching for complex cases
    if ($upperCat -match '(SECURITY|DEFENDER|SENTINEL|THREAT|ATTACK|BREACH)') {
        return 'Security'
    }
    if ($upperCat -match '(AZURE|CLOUD|AWS|GCP)') {
        return 'Cloud'
    }
    if ($upperCat -match '(ENTRA|IDENTITY|AUTH|AAD|AD)') {
        return 'Identity'
    }
    if ($upperCat -match '(AI|COPILOT|ML|LLM|ARTIFICIAL|MACHINE LEARNING)') {
        return 'Artificial Intelligence'
    }
    if ($upperCat -match '(TEAMS|SHAREPOINT|EXCHANGE|OUTLOOK|365|M365)') {
        return 'Collaboration'
    }
    if ($upperCat -match '(INTUNE|MANAGEMENT|GOVERNANCE|POLICY|ENDPOINT)') {
        return 'Management'
    }
    if ($upperCat -match '(DEVOPS|CI|CD|GITHUB|DEV|CODE)') {
        return 'Development'
    }
    if ($upperCat -match '(DATA|ANALYTICS|BI|SQL|DATABASE)') {
        return 'Data'
    }
    if ($upperCat -match '(TRAINING|LEARNING|EDUCATION|COURSE|CERT)') {
        return 'Learning'
    }
    if ($upperCat -match '(UPDATE|NEWS|ANNOUNCEMENT|RELEASE|AMA)') {
        return 'Updates'
    }
    
    # Default: use original category if no match found
    return $trimmed
}

# Function to get post date from metadata
function Get-PostDateFromMetadata {
    param(
        [string]$Content,
        [string]$FilePath
    )
    
    # Try to extract from front matter (YAML/TOML)
    if ($Content -match '(?s)(---|\+\+\+)(.*?)\1') {
        $frontMatter = $matches[2]
        
        if ($frontMatter -match '(?i)date\s*[:=]\s*[''"]?(\d{4}-\d{2}-\d{2})') {
            return [datetime]::Parse($matches[1])
        }
        if ($frontMatter -match '(?i)published\s*[:=]\s*[''"]?(\d{4}-\d{2}-\d{2})') {
            return [datetime]::Parse($matches[1])
        }
    }
    
    # Try to extract from HTML time tag
    if ($Content -match '<time[^>]*datetime=[''"]?(\d{4}-\d{2}-\d{2})[''"]?') {
        return [datetime]::Parse($matches[1])
    }
    
    # Fallback to file creation date
    if (Test-Path $FilePath) {
        return (Get-Item $FilePath).CreationTime
    }
    
    return (Get-Date)
}

# Function to get post title
function Get-PostTitleFromMetadata {
    param(
        [string]$Content
    )
    
    # Try front matter first
    if ($Content -match '(?s)(---|\+\+\+)(.*?)\1') {
        $frontMatter = $matches[2]
        
        if ($frontMatter -match '(?i)title\s*[:=]\s*[''"]?([^''"]+)[''"]?') {
            return $matches[1].Trim()
        }
    }
    
    # Try markdown h1
    if ($Content -match '(?s)^#\s+(.+?)$') {
        return $matches[1].Trim()
    }
    
    # Try HTML h1
    if ($Content -match '(?s)<h1[^>]*>(.*?)</h1>') {
        $title = $matches[1] -replace '<[^>]+>', ''
        return $title.Trim()
    }
    
    return "Unknown Title"
}

# Function to get categories from metadata
function Get-CategoriesFromMetadata {
    param(
        [string]$Content
    )
    
    $categories = @()
    
    # Try front matter
    if ($Content -match '(?s)(---|\+\+\+)(.*?)\1') {
        $frontMatter = $matches[2]
        
        if ($frontMatter -match '(?i)categories?\s*[:=]\s*\[(.*?)\]') {
            $cats = $matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"''') }
            $categories += $cats
        }
        elseif ($frontMatter -match '(?i)tags?\s*[:=]\s*\[(.*?)\]') {
            $tags = $matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"''') }
            $categories += $tags
        }
    }
    
    # Try HTML data attributes or span/a tags
    if ($Content -match '(?s)<(span|a)[^>]*class=[''"]category[''"][^>]*>([^<]+)<') {
        $categories += $matches[2]
    }
    
    return $categories
}

# Function to fetch content from URL
function Get-ContentFromURL {
    param(
        [string]$URL
    )
    
    try {
        $response = Invoke-WebRequest -Uri $URL -TimeoutSec $RequestTimeout -ErrorAction Stop
        return $response.Content
    }
    catch {
        Write-Warning "Failed to fetch $URL : $_"
        return $null
    }
}

# Function to get content (URL or local file)
function Get-PostContent {
    param(
        [string]$FilePath,
        [string]$URL
    )
    
    if ($UseLocalFiles -and (Test-Path $FilePath)) {
        return Get-Content -Path $FilePath -Raw -ErrorAction SilentlyContinue
    }
    
    if ($URL) {
        return Get-ContentFromURL -URL $URL
    }
    
    return $null
}

# Function to map category to reporting category
function Get-ReportingCategory {
    param(
        [string]$Category
    )
    
    foreach ($key in $categoryMapping.Keys) {
        if ($Category -match $key) {
            return $categoryMapping[$key]
        }
    }
    
    return $Category
}

# Function to auto-discover RSS feed URL from HTML head section
function Get-RSSFeedURL {
    param([string]$Content, [string]$BlogURL)
    
    $rssUrls = @()
    
    # Pattern 1: Look for RSS link in HTML head
    if ($Content -match '<link\s+rel="alternate"\s+type="application/rss\+xml"[^>]*href="([^"]+)"') {
        $rssUrls += $matches[1]
    }
    
    # Pattern 2: Alternative order of attributes
    if ($Content -match '<link[^>]*type="application/rss\+xml"[^>]*href="([^"]+)"') {
        $rssUrls += $matches[1]
    }
    
    # Pattern 3: Atom feed
    if ($Content -match '<link\s+rel="alternate"\s+type="application/atom\+xml"[^>]*href="([^"]+)"') {
        $rssUrls += $matches[1]
    }
    
    # Return unique URLs
    return $rssUrls | Select-Object -Unique
}

# Function to detect blog platform type
function Get-BlogPlatform {
    param([string]$Content, [string]$BlogURL)
    
    # Check for MVP profile first
    if ($BlogURL -match 'mvp\.microsoft\.com/') { return 'MVP-Profile' }
    
    # Check for WordPress.com first (before generic WordPress check)
    if ($Content -match 'wordpress.com|jetpack|blog_id.*26086|data-blog') { return 'WordPress.com' }
    
    # Check for Ghost CMS
    if ($Content -match 'ghost|by-line\.|post-card-image|gh-card-wrapper') { return 'Ghost' }
    
    # Check for Squarespace
    if ($Content -match 'sqs|squarespace-|data-edit-lock') { return 'Squarespace' }
    
    # Check for specific platform markers
    if ($Content -match 'archive__item') { return 'Jekyll' }
    if ($Content -match 'class="listing-item".*?class="title"') { return 'DisplayPostsListing' }
    if ($Content -match 'wix-essential-viewer-model|communities-blog-ooi') { return 'Wix' }
    if ($Content -match 'wp-content|wp-admin|amphibious') { return 'WordPress' }
    if ($Content -match 'class="[^"]*compact-card') { return 'Hugo' }
    if ($Content -match 'class="post-card"') { return 'Custom-PostCard' }
    if ($Content -match 'class="post-' -and $Content -match 'article') { return 'WordPress' }
    if ($Content -match 'wpgb-card') { return 'WP-GridBuilder' }
    
    return 'Unknown'
}

# Function to extract WP Grid Builder posts (used by WP Grid Builder plugin)
function Get-WPGridBuilderPosts {
    param(
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL,
        [string]$PageURL
    )
    
    $posts = @()
    
    # Pattern: <article class="wpgb-card wpgb-post-XXXXX">...<h3>...<a href="...">Title</a></h3>
    $articlePattern = '<article class="wpgb-card[^"]*wpgb-post-(\d+)"[^>]*>.*?<h3[^>]*><a[^>]*href="([^"]+)"[^>]*>([^<]+)</a></h3>'
    $matches = [regex]::Matches($Content, $articlePattern, 'Singleline')
    
    foreach ($match in $matches) {
        try {
            $postId = $match.Groups[1].Value
            $url = $match.Groups[2].Value
            $title = $match.Groups[3].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
            
            # Fetch individual post page to get the date from JSON-LD schema
            Write-Host "  Fetching date for: $title" -ForegroundColor Gray
            $postContent = Get-ContentFromURL -URL $url
            
            if ($postContent -match '"datePublished"\s*:\s*"(\d{4}-\d{2}-\d{2})') {
                $date = [datetime]::Parse($matches[1])
                
                if ($date -ge $StartDate -and $date -le $EndDate) {
                    $posts += [PSCustomObject]@{
                        Date     = $date.ToString('yyyy-MM-dd')
                        Category = "Uncategorized"
                        Title    = $title
                        URL      = $url
                        FileName = (Split-Path -Leaf $url)
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to parse WP Grid Builder article: $_"
        }
    }
    
    return $posts
}

# Function to extract WordPress.com REST API posts
function Get-WordPressCOMPosts {
    param(
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Extract domain from URL (WordPress.com uses REST API)
    $domain = ([System.Uri]$BlogURL).Host
    $restUrl = "https://public-api.wordpress.com/rest/v1.1/sites/$domain/posts?number=100&status=publish"
    
    try {
        Write-Host "  Fetching from WordPress.com REST API: $restUrl" -ForegroundColor Gray
        $response = Invoke-WebRequest -Uri $restUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
        
        if ($response -and $response.StatusCode -eq 200) {
            $jsonContent = $response.Content | ConvertFrom-Json
            
            if ($jsonContent.posts -and $jsonContent.posts.Count -gt 0) {
                Write-Host "  Found $($jsonContent.posts.Count) posts from REST API" -ForegroundColor Gray
                
                foreach ($post in $jsonContent.posts) {
                    try {
                        $title = $post.title -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
                        $url = $post.URL
                        $dateStr = $post.date
                        
                        if ($dateStr) {
                            try {
                                # WordPress.com returns dates in various formats: MM/DD/YYYY HH:MM:SS format
                                # Extract just the date part if it contains time
                                if ($dateStr -match '(\d{1,2})/(\d{1,2})/(\d{4})') {
                                    $month = [int]$matches[1]
                                    $day = [int]$matches[2]
                                    $year = [int]$matches[3]
                                    $date = [datetime]::new($year, $month, $day)
                                }
                                else {
                                    $date = [datetime]::Parse($dateStr)
                                }
                                if ($date -ge $StartDate -and $date -le $EndDate) {
                                    # Extract category from WordPress.com API
                                    # Categories are returned as a hashtable/object, not an array
                                    $rawCategory = "Uncategorized"
                                    if ($post.categories -and ($post.categories | Measure-Object).Count -gt 0) {
                                        $categoryObj = $post.categories | Get-Member -MemberType NoteProperty | Select-Object -First 1
                                        if ($categoryObj) {
                                            $rawCategory = $post.categories.($categoryObj.Name).name
                                        }
                                    }
                                    elseif ($post.tags -and ($post.tags | Measure-Object).Count -gt 0) {
                                        $tagObj = $post.tags | Get-Member -MemberType NoteProperty | Select-Object -First 1
                                        if ($tagObj) {
                                            $rawCategory = $post.tags.($tagObj.Name).name
                                        }
                                    }
                                    
                                    # Normalize category to standard format
                                    $category = Normalize-Category -RawCategory $rawCategory
                                    
                                    $posts += [PSCustomObject]@{
                                        Date     = $date.ToString('yyyy-MM-dd')
                                        Category = $category
                                        Title    = $title
                                        URL      = $url
                                        FileName = (Split-Path -Leaf $url)
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Failed to parse date '$dateStr': $_"
                            }
                        }
                    }
                    catch {
                        Write-Warning "Failed to parse WordPress.com post: $_"
                    }
                }
            }
        }
    }
    catch {
        Write-Host "  REST API failed, trying RSS feed..." -ForegroundColor Gray
        
        # Fallback to RSS feed
        try {
            $rssUrl = "$BlogURL/feed/"
            $response = Invoke-WebRequest -Uri $rssUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
            
            if ($response -and $response.StatusCode -eq 200) {
                $rssContent = $response.Content
                
                # Extract items from RSS
                $itemPattern = '<item>.*?<title>([^<]+)</title>.*?<link>([^<]+)</link>.*?<pubDate>([^<]+)</pubDate>'
                $matches = [regex]::Matches($rssContent, $itemPattern, 'Singleline')
                
                Write-Host "  Found $($matches.Count) posts from RSS feed" -ForegroundColor Gray
                
                foreach ($match in $matches) {
                    try {
                        $title = $match.Groups[1].Value | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
                        $url = $match.Groups[2].Value
                        $pubDateStr = $match.Groups[3].Value
                        
                        # Parse RSS date format
                        $date = [datetime]::Parse($pubDateStr)
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            $posts += [PSCustomObject]@{
                                Date     = $date.ToString('yyyy-MM-dd')
                                Category = "Uncategorized"
                                Title    = $title
                                URL      = $url
                                FileName = (Split-Path -Leaf $url)
                            }
                        }
                    }
                    catch {
                        Write-Warning "Failed to parse RSS item: $_"
                    }
                }
            }
        }
        catch {
            Write-Warning "WordPress.com RSS feed also failed: $_"
        }
    }
    
    return $posts
}

# Function to extract WordPress posts
function Get-WordPressPosts {
    param(
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Try pattern: WordPress with id="post-XXXX" (flexible heading and date formats)
    $pattern = '<article[^>]*id="post-(\d+)"[^>]*>.*?<h\d[^>]*(?:class="[^"]*[^"]*")?[^>]*><a[^>]*href="([^"]+)"[^>]*>([^<]+)</a></h\d>'
    $matches = [regex]::Matches($Content, $pattern, 'Singleline')
    
    foreach ($match in $matches) {
        try {
            $url = $match.Groups[2].Value
            $title = $match.Groups[3].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
            
            # Extract context around the post to find date
            $contextStart = [Math]::Max(0, $match.Index - 300)
            $contextEnd = [Math]::Min($Content.Length, $match.Index + $match.Length + 800)
            $context = $Content.Substring($contextStart, $contextEnd - $contextStart)
            
            $date = $null
            
            # Try ISO format: <time datetime="YYYY-MM-DD"> or similar
            if ($context -match '<time[^>]*datetime="(\d{4})-(\d{2})-(\d{2})"') {
                try { $date = [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) }
                catch { }
            }
            
            # Try word format: "Month Day, Year"
            if (-not $date -and $context -match '(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(\d{4})') {
                try {
                    $monthName = $matches[1]
                    $monthMap = @{
                        'January' = 1; 'February' = 2; 'March' = 3; 'April' = 4; 'May' = 5; 'June' = 6
                        'July' = 7; 'August' = 8; 'September' = 9; 'October' = 10; 'November' = 11; 'December' = 12
                    }
                    $date = [datetime]::new([int]$matches[3], $monthMap[$monthName], [int]$matches[2])
                }
                catch { }
            }
            
            # Try simple numeric format: YYYY-MM-DD
            if (-not $date -and $context -match '(\d{4})-(\d{2})-(\d{2})') {
                try { $date = [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3]) }
                catch { }
            }
            
            if ($date -and $date -ge $StartDate -and $date -le $EndDate) {
                $posts += [PSCustomObject]@{
                    Date     = $date.ToString('yyyy-MM-dd')
                    Category = "Uncategorized"
                    Title    = $title
                    URL      = $url
                    FileName = (Split-Path -Leaf $url)
                }
            }
        }
        catch {
            Write-Warning "Failed to parse WordPress article: $_"
        }
    }
    
    return $posts
}

# Function to extract Jekyll blog posts (cloud-architekt.net style)
function Get-JekyllPosts {
    param(
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Pattern: <div class="archive__item">...<h2 class="archive__item-title">Title</h2>...<a href="...">Read More</a>...<time datetime="YYYY-MM-DD">
    $articlePattern = '<div class="archive__item"[^>]*>.*?<h2[^>]*class="archive__item-title[^"]*"[^>]*>([^<]+)</h2>.*?<a[^>]*href="([^"]+)"[^>]*class="btn'
    $matches = [regex]::Matches($Content, $articlePattern, 'Singleline')
    
    foreach ($match in $matches) {
        try {
            $title = $match.Groups[1].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
            $url = $match.Groups[2].Value
            
            # Make absolute URL if needed
            if ($url -notlike 'http*') {
                $url = "$BlogURL$url"
            }
            
            # Fetch post page to get date and categories
            Write-Host "  Fetching: $title" -ForegroundColor Gray
            $postContent = Get-ContentFromURL -URL $url
            
            if ($postContent) {
                if ($postContent -match '<time[^>]*datetime="(\d{4}-\d{2}-\d{2})[^"]*"') {
                    $dateStr = $matches[1]
                    $date = [datetime]::Parse($dateStr)
                    
                    if ($date -ge $StartDate -and $date -le $EndDate) {
                        $posts += [PSCustomObject]@{
                            Date     = $date.ToString('yyyy-MM-dd')
                            Category = "Uncategorized"
                            Title    = $title
                            URL      = $url
                            FileName = (Split-Path -Leaf $url)
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to parse Jekyll article: $_"
        }
    }
    
    return $posts
}

# Function to extract posts from Wix blog (via RSS feed)
function Get-WixBlogPosts {
    param(
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Try common Wix RSS feed URLs
    $rssUrls = @(
        "$BlogURL/blog-feed.xml",
        "$BlogURL/blog/feed",
        "$BlogURL/feed.xml",
        "$BlogURL/feed"
    )
    
    foreach ($rssUrl in $rssUrls) {
        try {
            Write-Host "  Trying RSS feed: $rssUrl" -ForegroundColor Gray
            $response = Invoke-WebRequest -Uri $rssUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
            
            if ($response -and $response.StatusCode -eq 200) {
                $rssContent = $response.Content
                
                # Extract items from RSS with CDATA handling
                $itemPattern = '<item>.*?<title><!\[CDATA\[(.*?)\]\]></title>.*?<description><!\[CDATA\[(.*?)\]\]></description>.*?<link>(.*?)</link>.*?<pubDate>(.*?)</pubDate>'
                $matches = [regex]::Matches($rssContent, $itemPattern, 'Singleline')
                
                if ($matches.Count -gt 0) {
                    Write-Host "  Found $($matches.Count) posts in RSS feed" -ForegroundColor Gray
                    
                    foreach ($match in $matches) {
                        try {
                            $title = $match.Groups[1].Value.Trim()
                            $description = $match.Groups[2].Value.Trim()
                            $url = $match.Groups[3].Value.Trim()
                            $pubDateStr = $match.Groups[4].Value.Trim()
                            
                            # Parse RSS date format like "Tue, 11 Nov 2025 18:05:27 GMT"
                            try {
                                $date = [datetime]::Parse($pubDateStr)
                                
                                if ($date -ge $StartDate -and $date -le $EndDate) {
                                    $posts += [PSCustomObject]@{
                                        Date     = $date.ToString('yyyy-MM-dd')
                                        Category = "Uncategorized"
                                        Title    = $title
                                        URL      = $url
                                        FileName = (Split-Path -Leaf $url)
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Failed to parse date '$pubDateStr': $_"
                            }
                        }
                        catch {
                            Write-Warning "Failed to parse Wix RSS item: $_"
                        }
                    }
                    
                    # Found valid RSS feed, return posts
                    return $posts
                }
            }
        }
        catch {
            # Try next URL
        }
    }
    
    return $posts
}

# Function to extract posts from Display Posts Listing plugin (WordPress)
function Get-DisplayPostsListingPosts {
    param(
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Pattern: <li class="listing-item">...<a class="title" href="...">Title</a>...<span class="date">Date</span>
    $pattern = '<li class="listing-item">.*?<a class="title" href="([^"]+)">([^<]+)</a>.*?<span class="date">([^<]+)</span>'
    $matches = [regex]::Matches($Content, $pattern, 'Singleline')
    
    foreach ($match in $matches) {
        try {
            $url = $match.Groups[1].Value
            $title = $match.Groups[2].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
            $dateStr = $match.Groups[3].Value
            
            # Parse date format like "December 5, 2025 7:00 am"
            if ($dateStr -match '(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})') {
                $monthName = $matches[1]
                $day = [int]$matches[2]
                $year = [int]$matches[3]
                
                $monthMap = @{
                    'January' = 1; 'February' = 2; 'March' = 3; 'April' = 4; 'May' = 5; 'June' = 6
                    'July' = 7; 'August' = 8; 'September' = 9; 'October' = 10; 'November' = 11; 'December' = 12
                }
                $month = $monthMap[$monthName]
                $date = [datetime]::new($year, $month, $day)
                
                if ($date -ge $StartDate -and $date -le $EndDate) {
                    $posts += [PSCustomObject]@{
                        Date     = $date.ToString('yyyy-MM-dd')
                        Category = "Uncategorized"
                        Title    = $title
                        URL      = $url
                        FileName = (Split-Path -Leaf $url)
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to parse Display Posts Listing item: $_"
        }
    }
    
    return $posts
}

# Function to extract categories from post pages (universal WordPress & Jekyll)
function Get-PostCategoriesFromContent {
    param([string]$Content)
    
    $categories = @()
    
    # Pattern 1: <span class="post-category">...Category links...</span>
    if ($Content -match '<span class="post-category">([^<]*(?:<a[^>]*>([^<]+)</a>[^<]*)*)</span>') {
        $categorySection = $matches[1]
        # Extract all links from category section
        $categoryMatches = [regex]::Matches($categorySection, '<a[^>]*>([^<]+)</a>')
        foreach ($catMatch in $categoryMatches) {
            $cat = $catMatch.Groups[1].Value.Trim()
            if ($cat -and $cat.Length -gt 0 -and $cat -notlike '*<*') {
                $categories += $cat
            }
        }
    }
    
    # Pattern 2: <span class="page__meta-category">...Category tags...</span>
    if ($Content -match '<span class="page__meta-category">(.*?)</span>') {
        $categorySection = $matches[1]
        $categoryMatches = [regex]::Matches($categorySection, '<a[^>]*>([^<]+)</a>')
        foreach ($catMatch in $categoryMatches) {
            $cat = $catMatch.Groups[1].Value.Trim()
            if ($cat -and $cat.Length -gt 0) {
                $categories += $cat
            }
        }
    }
    
    # Pattern 3: data-category or data-tag attributes
    if ($Content -match 'data-category="([^"]+)"') {
        $categories += $matches[1] -split '\s*,\s*'
    }
    
    # Pattern 4: Schema.org ArticleBody with keywords
    if ($Content -match '"keywords"\s*:\s*"([^"]+)"') {
        $categories += $matches[1] -split '\s*,\s*'
    }
    
    return $categories | Select-Object -Unique
}

# Function to extract vanilla HTML blog posts (generic extractor)
function Get-VanillaHTMLPosts {
    param(
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$BlogURL
    )
    
    $posts = @()
    
    # Pattern 1: Simple links in Recent Posts section (like justinjackson.ca)
    # Look for <a href="/post-slug">Post Title</a> patterns within a blog or posts section
    $linkPattern = '<a[^>]*href="([^"]+)"[^>]*class="[^"]*(?:post|article|link)[^"]*"[^>]*>([^<]+)</a>'
    $matches = [regex]::Matches($Content, $linkPattern, 'IgnoreCase')
    
    if ($matches.Count -eq 0) {
        # Pattern 2: Generic article link pattern
        $linkPattern = '<a[^>]*href="(/[^/"]+)"[^>]*>([^<]{10,150})</a>'
        $matches = [regex]::Matches($Content, $linkPattern, 'IgnoreCase')
    }
    
    foreach ($match in $matches) {
        try {
            $href = $match.Groups[1].Value.Trim()
            $title = $match.Groups[2].Value.Trim() | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
            
            # Skip common navigation items
            if ($title -match '^(Home|About|Contact|Posts|Articles|Blog|Services|Subscribe|Newsletter|Categories|Tags|Archive|Search|All|More)$' -or $href -eq '/') {
                continue
            }
            
            # Skip if title too short or looks like nav
            if ($title.Length -lt 5) {
                continue
            }
            
            # Construct full URL
            if ($href -match '^https?://') {
                $postURL = $href
            }
            elseif ($href -match '^/') {
                $postURL = "$BlogURL$href"
            }
            else {
                $postURL = "$BlogURL/$href"
            }
            
            # Try to fetch the post page to get date
            Write-Host "  Fetching: $title" -ForegroundColor Gray
            $postContent = Get-ContentFromURL -URL $postURL
            
            if ($postContent) {
                $date = $null
                
                # Pattern 1: <time datetime="2024-12-05T...">
                if ($postContent -match '<time[^>]*datetime="(\d{4}-\d{2}-\d{2})') {
                    $date = [datetime]::Parse($matches[1])
                }
                # Pattern 2: Published on Month Day(st/nd/rd/th), Year
                elseif ($postContent -match 'Published\s+on\s+([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})') {
                    try {
                        $monthName = $matches[1]
                        $day = [int]$matches[2]
                        $year = [int]$matches[3]
                        
                        $monthMap = @{
                            'January' = 1; 'February' = 2; 'March' = 3; 'April' = 4; 'May' = 5; 'June' = 6
                            'July' = 7; 'August' = 8; 'September' = 9; 'October' = 10; 'November' = 11; 'December' = 12
                        }
                        if ($monthMap[$monthName]) {
                            $month = $monthMap[$monthName]
                            $date = [datetime]::new($year, $month, $day)
                        }
                    }
                    catch {}
                }
                # Pattern 3: <span>December 5, 2024</span> or similar
                elseif ($postContent -match '<span>([^<]*?(January|February|March|April|May|June|July|August|September|October|November|December)[^<]*?\d{4})[^<]*</span>') {
                    try {
                        $date = [datetime]::Parse($matches[1])
                    }
                    catch {}
                }
                # Pattern 4: Meta tags like <meta property="article:published_time" content="2024-12-05">
                elseif ($postContent -match '<meta[^>]*property="article:published_time"[^>]*content="(\d{4}-\d{2}-\d{2})') {
                    $date = [datetime]::Parse($matches[1])
                }
                # Pattern 5: JSON-LD datePublished
                elseif ($postContent -match '"datePublished"\s*:\s*"(\d{4}-\d{2}-\d{2})') {
                    $date = [datetime]::Parse($matches[1])
                }
                # Pattern 6: Posted on or Updated formats
                elseif ($postContent -match '(?:Posted|Updated|Published)\s+(?:on\s+)?(?:the\s+)?(\d{1,2})?[\s\w]*(\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4}|[A-Za-z]+\s+\d{1,2},?\s+\d{4})') {
                    try {
                        $dateStr = $matches[2]
                        $date = [datetime]::Parse($dateStr)
                    }
                    catch {}
                }
                
                # If we found a date and it's in range, add it
                if ($date -and ($date -ge $StartDate -and $date -le $EndDate)) {
                    # Check if already exists (by URL)
                    $exists = $posts | Where-Object { $_.URL -eq $postURL }
                    if (-not $exists) {
                        $posts += [PSCustomObject]@{
                            Date     = $date.ToString('yyyy-MM-dd')
                            Category = "Uncategorized"
                            Title    = $title
                            URL      = $postURL
                            FileName = (Split-Path -Leaf $postURL)
                        }
                    }
                }
            }
        }
        catch {
            # Silently skip on error
        }
    }
    
    return $posts
}

# Function to extract posts from WordPress blogs using RSS feed auto-discovery
function Get-WordPressRSSPosts {
    param(
        [string]$BlogURL,
        [string]$Content,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    $posts = @()
    
    # Try to find RSS feed URL from HTML head
    $discoveredFeeds = Get-RSSFeedURL -Content $Content -BlogURL $BlogURL
    
    # Standard WordPress RSS feed URLs to try
    $feedUrls = @()
    if ($discoveredFeeds) {
        $feedUrls += $discoveredFeeds
    }
    
    # Add standard WordPress locations
    $feedUrls += @(
        "$BlogURL/feed/",
        "$BlogURL/feed",
        "$BlogURL/rss/",
        "$BlogURL/rss",
        "$BlogURL/feed/rss/",
        "$BlogURL/?feed=rss2",
        "$BlogURL/index.php/feed/"
    )
    
    foreach ($feedUrl in $feedUrls) {
        try {
            $response = Invoke-WebRequest -Uri $feedUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
            
            if ($response.StatusCode -eq 200) {
                $feed = $response.Content
                [xml]$rssContent = $feed
                
                foreach ($item in $rssContent.rss.channel.item) {
                    try {
                        $date = [datetime]::Parse($item.pubDate)
                        $title = if ($item.title -is [string]) { $item.title } else { $item.title.InnerText }
                        $url = if ($item.link -is [string]) { $item.link } else { $item.link.InnerText }
                        $category = "Uncategorized"
                        
                        # Try to extract category
                        if ($item.category) {
                            $categories = @($item.category)
                            if ($categories.Count -gt 0) {
                                $catText = if ($categories[0] -is [string]) { $categories[0] } else { $categories[0].InnerText }
                                if ($catText -and $catText.Length -gt 0) {
                                    $category = Normalize-Category -Category $catText
                                }
                            }
                        }
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            $posts += [PSCustomObject]@{
                                Date     = $date.ToString('yyyy-MM-dd')
                                Category = $category
                                Title    = $title
                                URL      = $url
                                FileName = (Split-Path -Leaf $url)
                            }
                        }
                    }
                    catch {
                        # Skip items that fail to parse
                    }
                }
                
                if ($posts.Count -gt 0) {
                    return $posts
                }
            }
        }
        catch {
            # Try next feed URL
        }
    }
    
    return $posts
}

# Function to extract posts from Ghost CMS
function Get-GhostPosts {
    param(
        [string]$BlogURL,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    $posts = @()
    
    # Ghost has a standard RSS feed endpoint
    $feedUrls = @(
        "$BlogURL/rss/",
        "$BlogURL/rss",
        "$BlogURL/feed.xml",
        "$BlogURL/feed/"
    )
    
    foreach ($feedUrl in $feedUrls) {
        try {
            $response = Invoke-WebRequest -Uri $feedUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
            $feed = $response.Content
            
            if ($feed) {
                # Parse RSS feed
                [xml]$rssContent = $feed
                
                foreach ($item in $rssContent.rss.channel.item) {
                    try {
                        $date = [datetime]::Parse($item.pubDate)
                        # Handle both element and text nodes
                        $title = if ($item.title -is [string]) { $item.title } else { $item.title.InnerText }
                        $url = if ($item.link -is [string]) { $item.link } else { $item.link.InnerText }
                        $category = "Uncategorized"
                        
                        # Try to extract category from category elements
                        if ($item.category) {
                            $categories = @($item.category)
                            if ($categories.Count -gt 0) {
                                $firstCat = $categories[0]
                                $catText = if ($firstCat -is [string]) { $firstCat } else { $firstCat.InnerText }
                                if ($catText -and $catText.Length -gt 0) {
                                    $category = Normalize-Category -Category $catText
                                }
                            }
                        }
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            $posts += [PSCustomObject]@{
                                Date     = $date.ToString('yyyy-MM-dd')
                                Category = $category
                                Title    = $title
                                URL      = $url
                                FileName = (Split-Path -Leaf $url)
                            }
                        }
                    }
                    catch {
                        # Skip items that fail to parse
                    }
                }
                
                if ($posts.Count -gt 0) {
                    return $posts
                }
            }
        }
        catch {
            # Try next feed URL
        }
    }
    
    return $posts
}

# Function to extract posts from Squarespace
function Get-SquarespacePosts {
    param(
        [string]$BlogURL,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    $posts = @()
    
    # Squarespace often has RSS feed
    $feedUrls = @(
        "$BlogURL/blog?format=rss",
        "$BlogURL/blog/feed",
        "$BlogURL/feed.xml",
        "$BlogURL/?format=rss"
    )
    
    foreach ($feedUrl in $feedUrls) {
        try {
            $response = Invoke-WebRequest -Uri $feedUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
            $feed = $response.Content
            
            if ($feed) {
                [xml]$rssContent = $feed
                
                foreach ($item in $rssContent.rss.channel.item) {
                    try {
                        $date = [datetime]::Parse($item.pubDate)
                        $title = $item.title
                        $url = $item.link
                        $category = "Uncategorized"
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            $posts += [PSCustomObject]@{
                                Date     = $date.ToString('yyyy-MM-dd')
                                Category = $category
                                Title    = $title
                                URL      = $url
                                FileName = (Split-Path -Leaf $url)
                            }
                        }
                    }
                    catch {
                        # Skip items that fail to parse
                    }
                }
                
                if ($posts.Count -gt 0) {
                    return $posts
                }
            }
        }
        catch {
            # Try next feed URL
        }
    }
    
    return $posts
}

# Function to get blog URL from MVP profile ID (uses MVP profile ID to look up blog)
function Get-MVPBlogURLFromProfile {
    param(
        [string]$MVPProfileURL
    )
    
    # MVP profiles are React SPAs, so static extraction won't work
    # This would require Selenium or Playwright integration to execute JavaScript
    # For now, return null and let the user provide blog URL separately
    return $null
}

# Function to extract blog URL from MVP profile
function Get-MVPBlogURL {
    param(
        [string]$MVPProfileURL
    )
    
    # First try API approach
    $blogUrl = Get-MVPBlogURLFromProfile -MVPProfileURL $MVPProfileURL
    if ($blogUrl) {
        return $blogUrl
    }
    
    # Fallback: try web scraping (for static MVP profiles or older pages)
    try {
        $response = Invoke-WebRequest -Uri $MVPProfileURL -TimeoutSec 10 -ErrorAction SilentlyContinue
        
        if ($response.StatusCode -eq 200) {
            $content = $response.Content
            
            # Look for blog/website links in the profile
            if ($content -match 'href="(https?://[^"]*(?:blog|website|\.com|\.io)[^"]*)"\s*(?:target="_blank"|[^>])*>.*?(?:Blog|Website|Personal)') {
                return $matches[1]
            }
            
            # Try generic external link extraction
            $allLinks = [regex]::Matches($content, 'href="(https?://[^"]+)"')
            $socialDomains = @('twitter.com', 'linkedin.com', 'github.com', 'facebook.com', 'instagram.com', 'youtube.com', 'reddit.com', 'microsoft.com', 'mvp.microsoft.com')
            
            foreach ($link in $allLinks) {
                $url = $link.Groups[1].Value
                
                if ($socialDomains | Where-Object { $url -like "*$_*" }) {
                    continue
                }
                
                if ($url -match '(?:blog|post|article|page)') {
                    return $url
                }
            }
        }
    }
    catch {
        # Silently fail
    }
    
    return $null
}

# Function to extract blog posts from MVP profile by discovering blog URL
function Get-MVPBlogPosts {
    param(
        [string]$MVPProfileURL,
        [datetime]$StartDate,
        [datetime]$EndDate
    )
    
    $posts = @()
    
    # MVP profiles are React Single Page Applications loaded via JavaScript
    # Static HTML extraction doesn't reveal blog links
    # Check if there's a common blog convention or known blog URL pattern
    
    # Try to detect MVP ID and suggest looking for known blog patterns
    if ($MVPProfileURL -match '/PublicProfile/(\d+)') {
        $mvpId = $matches[1]
        Write-Host "Note: MVP profiles are dynamic (React SPA). Blog link extraction requires JavaScript execution." -ForegroundColor DarkYellow
        Write-Host "Common alternatives:" -ForegroundColor DarkYellow
        Write-Host "  1. Check MVP's blog link from their profile page directly" -ForegroundColor DarkYellow
        Write-Host "  2. If you know their blog URL, use that directly instead" -ForegroundColor DarkYellow
    }
    
    # Try generic blog URL extraction with common domains
    $commonBlogDomains = @(
        'wordpress.com',
        'medium.com', 
        'dev.to',
        'hashnode.com',
        'substack.com',
        'ghost.io'
    )
    
    # Extract potential blog URL from MVP profile page content
    try {
        $response = Invoke-WebRequest -Uri $MVPProfileURL -TimeoutSec 10 -ErrorAction SilentlyContinue
        
        if ($response.StatusCode -eq 200) {
            $content = $response.Content
            
            # Look for any blog URLs in the HTML
            foreach ($domain in $commonBlogDomains) {
                if ($content -match "(https?://[^/]*$domain[^""'`s]+)") {
                    $blogUrl = $matches[1] -replace "[""'>`s]+$", ""
                    
                    if ($blogUrl -like 'http*') {
                        Write-Host "Found potential blog URL: $blogUrl" -ForegroundColor Gray
                        
                        # Try to extract posts from discovered blog
                        try {
                            $blogResponse = Invoke-WebRequest -Uri $blogUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
                            if ($blogResponse.StatusCode -eq 200) {
                                $blogContent = $blogResponse.Content
                                
                                # Detect platform and extract
                                $platform = Get-BlogPlatform -Content $blogContent -BlogURL $blogUrl
                                
                                if ($platform -eq 'WordPress.com') {
                                    $wpcomPosts = Get-WordPressCOMPosts -StartDate $StartDate -EndDate $EndDate -BlogURL $blogUrl
                                    if ($wpcomPosts.Count -gt 0) {
                                        return $wpcomPosts
                                    }
                                }
                                elseif ($platform -eq 'Ghost') {
                                    $ghostPosts = Get-GhostPosts -StartDate $StartDate -EndDate $EndDate -BlogURL $blogUrl
                                    if ($ghostPosts.Count -gt 0) {
                                        return $ghostPosts
                                    }
                                }
                                elseif ($platform -eq 'WordPress') {
                                    $wpPosts = Get-WordPressRSSPosts -Content $blogContent -StartDate $StartDate -EndDate $EndDate -BlogURL $blogUrl
                                    if ($wpPosts.Count -gt 0) {
                                        return $wpPosts
                                    }
                                }
                                
                                # Try generic RSS
                                $discoveredFeeds = Get-RSSFeedURL -Content $blogContent -BlogURL $blogUrl
                                if ($discoveredFeeds) {
                                    foreach ($feedUrl in $discoveredFeeds) {
                                        try {
                                            $feedResponse = Invoke-WebRequest -Uri $feedUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
                                            if ($feedResponse.StatusCode -eq 200) {
                                                [xml]$rssContent = $feedResponse.Content
                                                foreach ($item in $rssContent.rss.channel.item) {
                                                    try {
                                                        $date = [datetime]::Parse($item.pubDate)
                                                        $title = if ($item.title -is [string]) { $item.title } else { $item.title.InnerText }
                                                        $url = if ($item.link -is [string]) { $item.link } else { $item.link.InnerText }
                                                        $category = "Uncategorized"
                                                        
                                                        if ($item.category) {
                                                            $categories = @($item.category)
                                                            if ($categories.Count -gt 0) {
                                                                $catText = if ($categories[0] -is [string]) { $categories[0] } else { $categories[0].InnerText }
                                                                if ($catText -and $catText.Length -gt 0) {
                                                                    $category = Normalize-Category -Category $catText
                                                                }
                                                            }
                                                        }
                                                        
                                                        if ($date -ge $StartDate -and $date -le $EndDate) {
                                                            $posts += [PSCustomObject]@{
                                                                Date     = $date.ToString('yyyy-MM-dd')
                                                                Category = $category
                                                                Title    = $title
                                                                URL      = $url
                                                                FileName = (Split-Path -Leaf $url)
                                                            }
                                                        }
                                                    }
                                                    catch {
                                                        # Skip items that fail
                                                    }
                                                }
                                            }
                                        }
                                        catch {
                                            # Try next feed
                                        }
                                    }
                                }
                                
                                if ($posts.Count -gt 0) {
                                    return $posts
                                }
                            }
                        }
                        catch {
                            # Failed to fetch blog, try next
                        }
                    }
                }
            }
        }
    }
    catch {
        # Failed to fetch MVP profile
    }
    
    return $posts
}

# Main script logic
Write-Host "Blog Post Export - Option 2 (Web-based)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Blog URL: $BlogURL"
Write-Host "Date Range: $($StartDate.ToShortDateString()) to $($EndDate.ToShortDateString())"
Write-Host "Output: $OutputFile"
Write-Host ""

$posts = @()
$exportCount = 0

# If using local markdown files
if (Test-Path $PostsDirectory -PathType Container) {
    Write-Host "Reading from local markdown files: $PostsDirectory" -ForegroundColor Green
    
    $mdFiles = Get-ChildItem -Path $PostsDirectory -Filter "*.md" -ErrorAction SilentlyContinue
    Write-Host "Found $($mdFiles.Count) markdown files"
    
    foreach ($file in $mdFiles) {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        
        if ($content) {
            $date = Get-PostDateFromMetadata -Content $content -FilePath $file.FullName
            
            if ($date -ge $StartDate -and $date -le $EndDate) {
                $title = Get-PostTitleFromMetadata -Content $content
                $categories = Get-CategoriesFromMetadata -Content $content
                $reportingCategory = if ($categories) { Get-ReportingCategory -Category $categories[0] } else { "Uncategorized" }
                
                # Build URL from slug or filename
                $slug = $file.BaseName
                $postURL = "$BlogURL/posts/$slug"
                
                $posts += [PSCustomObject]@{
                    Date     = $date
                    Category = $reportingCategory
                    Title    = $title
                    URL      = $postURL
                    FileName = $file.Name
                }
                
                $exportCount++
            }
        }
    }
}

# Option 2: Fetch from web (requires blog to have an API or index)
# Example: if your blog has a JSON API endpoint
if ($exportCount -eq 0) {
    Write-Host "Option 2 Mode: Fetching from web HTML" -ForegroundColor Yellow
    Write-Host "Note: Scraping blog posts from HTML structure" -ForegroundColor Yellow
    Write-Host ""
    
    # Try to fetch from blog homepage
    $homeUrl = $BlogURL
    Write-Host "Attempting to fetch posts from: $homeUrl" -ForegroundColor Gray
    
    # Try to fetch from blog homepage first
    try {
        $response = Invoke-WebRequest -Uri $homeUrl -TimeoutSec $RequestTimeout -ErrorAction Stop
        $content = $response.Content
        
        # Detect blog platform
        $platform = Get-BlogPlatform -Content $content -BlogURL $BlogURL
        Write-Host "Detected platform: $platform" -ForegroundColor Gray
        
        # Extract posts based on detected platform
        if ($platform -eq 'MVP-Profile') {
            # MVP Microsoft profile - extract blog URL and posts
            Write-Host "Detected MVP Microsoft profile" -ForegroundColor Gray
            $mvpBlogPosts = Get-MVPBlogPosts -MVPProfileURL $BlogURL -StartDate $StartDate -EndDate $EndDate
            if ($mvpBlogPosts.Count -gt 0) {
                $posts += $mvpBlogPosts
                $exportCount += $mvpBlogPosts.Count
                Write-Host "Found $($mvpBlogPosts.Count) posts from MVP's blog"
            }
            else {
                Write-Host "No blog found or no posts extracted from MVP profile"
            }
        }
        elseif ($platform -eq 'WordPress.com') {
            # WordPress.com hosted blog (REST API)
            Write-Host "Detected WordPress.com blog" -ForegroundColor Gray
            $wpcomPosts = Get-WordPressCOMPosts -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $wpcomPosts
            $exportCount += $wpcomPosts.Count
            Write-Host "Found $($wpcomPosts.Count) posts"
        }
        elseif ($platform -eq 'Jekyll') {
            # Jekyll can be on homepage or /blog/ page
            Write-Host "Detected Jekyll blog" -ForegroundColor Gray
            $jekyllPosts = Get-JekyllPosts -Content $content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $jekyllPosts
            $exportCount += $jekyllPosts.Count
            Write-Host "Found $($jekyllPosts.Count) posts"
        }
        elseif ($platform -eq 'Wix') {
            # Wix blog (uses RSS feed)
            Write-Host "Detected Wix blog" -ForegroundColor Gray
            $wixPosts = Get-WixBlogPosts -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $wixPosts
            $exportCount += $wixPosts.Count
            Write-Host "Found $($wixPosts.Count) posts from Wix RSS feed"
        }
        elseif ($platform -eq 'DisplayPostsListing') {
            # Display Posts Listing plugin for WordPress
            Write-Host "Detected Display Posts Listing plugin" -ForegroundColor Gray
            $dplPosts = Get-DisplayPostsListingPosts -Content $content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $dplPosts
            $exportCount += $dplPosts.Count
            Write-Host "Found $($dplPosts.Count) posts"
        }
        elseif ($platform -eq 'WordPress') {
            # Try WordPress RSS feed auto-discovery first
            Write-Host "Attempting WordPress RSS feed auto-discovery..." -ForegroundColor Gray
            $wpRSSPosts = Get-WordPressRSSPosts -Content $content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            
            if ($wpRSSPosts.Count -gt 0) {
                $posts += $wpRSSPosts
                $exportCount += $wpRSSPosts.Count
                Write-Host "Found $($wpRSSPosts.Count) posts via RSS feed"
            }
            else {
                # Fallback to traditional WordPress extraction
                # First, try to fetch from /blog page if homepage didn't work
                $blogPageUrl = "$BlogURL/blog"
                $blogPageResponse = Invoke-WebRequest -Uri $blogPageUrl -TimeoutSec $RequestTimeout -ErrorAction SilentlyContinue
                
                # Check if blog page has Display Posts Listing
                if ($blogPageResponse -and ($blogPageResponse.Content -match 'class="listing-item".*?class="title"')) {
                    Write-Host "Found Display Posts Listing on /blog page" -ForegroundColor Gray
                    $dplPosts = Get-DisplayPostsListingPosts -Content $blogPageResponse.Content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
                    $posts += $dplPosts
                    $exportCount += $dplPosts.Count
                    Write-Host "Found $($dplPosts.Count) posts on /blog page"
                }
                else {
                    # Check if it's WP Grid Builder (check for /tutorials/ page)
                    $tutorialsUrl = "$BlogURL/tutorials/"
                    $tutorialsResponse = Invoke-WebRequest -Uri $tutorialsUrl -TimeoutSec $RequestTimeout -ErrorAction SilentlyContinue
                    
                    if ($tutorialsResponse -and $tutorialsResponse.Content -like "*wpgb-card*") {
                        Write-Host "Detected WP Grid Builder plugin, using /tutorials/ page" -ForegroundColor Gray
                        $wpgbPosts = Get-WPGridBuilderPosts -Content $tutorialsResponse.Content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL -PageURL $tutorialsUrl
                        $posts += $wpgbPosts
                        $exportCount += $wpgbPosts.Count
                        Write-Host "Found $($wpgbPosts.Count) posts on WP Grid Builder /tutorials/ page"
                    }
                    else {
                        # Use standard WordPress extraction
                        $wpPosts = Get-WordPressPosts -Content $content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
                        $posts += $wpPosts
                        $exportCount += $wpPosts.Count
                        Write-Host "Found $($wpPosts.Count) posts on WordPress homepage"
                    }
                }
            }
        }
        elseif ($platform -eq 'Ghost') {
            # Ghost CMS
            Write-Host "Detected Ghost CMS blog" -ForegroundColor Gray
            $ghostPosts = Get-GhostPosts -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $ghostPosts
            $exportCount += $ghostPosts.Count
            Write-Host "Found $($ghostPosts.Count) posts from Ghost"
        }
        elseif ($platform -eq 'Squarespace') {
            # Squarespace
            Write-Host "Detected Squarespace blog" -ForegroundColor Gray
            $sqPosts = Get-SquarespacePosts -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $sqPosts
            $exportCount += $sqPosts.Count
            Write-Host "Found $($sqPosts.Count) posts from Squarespace"
        }
        elseif ($platform -eq 'Hugo') {
            # Parse HTML articles - look for compact-card articles with flexible patterns
            # Try pattern with onclick handler
            $articlePattern = '<article[^>]*class="[^"]*compact-card[^"]*"[^>]*>.*?onclick="[^"]*([^'']+)[''"].*?<h3[^>]*>([^<]+)</h3>.*?<span>(\d{1,2}/\d{1,2}/\d{4})</span>'
            
            $matches = [regex]::Matches($content, $articlePattern, 'Singleline')
            
            # If no matches, try simpler pattern
            if ($matches.Count -eq 0) {
                $articlePattern = '<article[^>]*class="[^"]*compact-card[^"]*"[^>]*>.*?href="([^"]+)"[^>]*>.*?<h3[^>]*>([^<]+)</h3>.*?(\d{1,2}/\d{1,2}/\d{4})'
                $matches = [regex]::Matches($content, $articlePattern, 'Singleline')
            }
            
            Write-Host "Found $($matches.Count) posts on homepage"
            
            foreach ($match in $matches) {
                try {
                    $postPath = $match.Groups[1].Value.Trim()
                    $title = $match.Groups[2].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
                    $dateStr = $match.Groups[3].Value.Trim()
                    
                    # Parse date in format "DD/MM/YYYY"
                    $dateParts = $dateStr -split '/'
                    if ($dateParts.Count -eq 3) {
                        $date = [datetime]::new([int]$dateParts[2], [int]$dateParts[1], [int]$dateParts[0])
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            # Construct the full URL
                            if ($postPath -match '^/') {
                                $postURL = "$BlogURL$postPath"
                            }
                            elseif ($postPath -match '^posts/') {
                                $postURL = "$BlogURL/$postPath"
                            }
                            else {
                                $postURL = "$BlogURL/posts/$postPath"
                            }
                            
                            $posts += [PSCustomObject]@{
                                Date     = $date.ToString('yyyy-MM-dd')
                                Category = "Uncategorized"
                                Title    = $title
                                URL      = $postURL
                                FileName = Split-Path -Leaf $postPath
                            }
                            $exportCount++
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to parse Hugo article: $_"
                }
            }
        }
        else {
            Write-Host "Platform not specifically supported. Attempting generic vanilla HTML extraction..." -ForegroundColor DarkGray
            $vanillaPost = Get-VanillaHTMLPosts -Content $content -StartDate $StartDate -EndDate $EndDate -BlogURL $BlogURL
            $posts += $vanillaPost
            $exportCount += $vanillaPost.Count
            Write-Host "Found $($vanillaPost.Count) posts from vanilla HTML"
        }
    }
    catch {
        Write-Host "Failed to fetch blog homepage: $_" -ForegroundColor Yellow
    }
    
    # If not enough posts found, try scraping posts/menu.html (if it exists) which has all posts
    if ($exportCount -eq 0 -or $exportCount -lt 20) {
        Write-Host ""
        Write-Host "Attempting to fetch complete post list from: $BlogURL/posts/menu.html" -ForegroundColor Gray
        
        try {
            $menuUrl = "$BlogURL/posts/menu.html"
            $response = Invoke-WebRequest -Uri $menuUrl -TimeoutSec $RequestTimeout -ErrorAction Stop
            $content = $response.Content
            
            # Parse HTML articles in menu (different structure: <article class="post-card">)
            # Pattern: <article class="post-card"...><h3><a href="...">Title</a></h3><time>06/12/2025</time>...
            $articlePattern = '<article class="post-card"[^>]*>.*?<h3><a href="([^"]+)">([^<]+)</a></h3><time>(\d{1,2}/\d{1,2}/\d{4})</time>'
            
            $matches = [regex]::Matches($content, $articlePattern, 'Singleline')
            
            Write-Host "Found $($matches.Count) posts in menu"
            
            $newCount = 0
            foreach ($match in $matches) {
                try {
                    $postPath = $match.Groups[1].Value
                    $title = $match.Groups[2].Value -replace '<[^>]+>', '' | ForEach-Object { [System.Web.HttpUtility]::HtmlDecode($_) }
                    $dateStr = $match.Groups[3].Value
                    
                    # Parse date in format "DD/MM/YYYY"
                    $dateParts = $dateStr -split '/'
                    if ($dateParts.Count -eq 3) {
                        $date = [datetime]::new([int]$dateParts[2], [int]$dateParts[1], [int]$dateParts[0])
                        
                        if ($date -ge $StartDate -and $date -le $EndDate) {
                            # Construct full URL
                            $postURL = "$BlogURL/posts/$postPath"
                            
                            # Skip if title is just "Archive" or "Menu"
                            if ($title -notmatch '^(Archive|Menu|All Posts)$') {
                                # Check if already added from homepage
                                $exists = $posts | Where-Object { $_.Title -eq $title }
                                if (-not $exists) {
                                    $posts += [PSCustomObject]@{
                                        Date     = $date.ToString('yyyy-MM-dd')
                                        Category = "Uncategorized"
                                        Title    = $title
                                        URL      = $postURL
                                        FileName = (Split-Path -Leaf $postPath)
                                    }
                                    $newCount++
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to parse menu article: $_"
                }
            }
            
            Write-Host "Added $newCount new posts from menu"
            $exportCount += $newCount
        }
        catch {
            Write-Host "No posts menu found. Proceeding with homepage posts only." -ForegroundColor DarkGray
        }
    }
}

# Sort by date descending
$posts = $posts | Sort-Object -Property Date -Descending

# Export to CSV
if ($posts.Count -gt 0) {
    $posts | Export-Csv -Path $OutputFile -Encoding UTF8 -NoTypeInformation -Delimiter ";"
    Write-Host ""
    Write-Host "✅ Export complete!" -ForegroundColor Green
    Write-Host "Total posts exported: $($posts.Count)"
    
    # Summary by category
    $summary = $posts | Group-Object -Property Category | Select-Object Name, Count
    Write-Host ""
    Write-Host "Posts by Category:"
    $summary | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }
    
    # Show first 5 entries
    Write-Host ""
    Write-Host "First 5 entries:" -ForegroundColor Cyan
    $posts | Select-Object -First 5 | Format-Table -AutoSize
}
else {
    Write-Host "❌ No posts found in the specified date range" -ForegroundColor Red
}

Write-Host ""
if ($posts.Count -gt 0) {
    Write-Host "Output file: $(Resolve-Path $OutputFile)" -ForegroundColor Cyan
}
else {
    Write-Host "Output file: $OutputFile (not created - no posts found)" -ForegroundColor Yellow
}
