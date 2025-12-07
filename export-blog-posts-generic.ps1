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

# Category mapping - customize based on your blog structure
$categoryMapping = @{
    'AI Security'    = 'AI'
    'Cloud Security' = 'Cloud'
    'Data Security'  = 'Data'
    'Identity'       = 'Identity'
    'Zero Trust'     = 'Security'
    'Entra'          = 'Identity'
    'Azure'          = 'Cloud'
    'Microsoft'      = 'Cloud'
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

# Function to detect blog platform type
function Get-BlogPlatform {
    param([string]$Content, [string]$BlogURL)
    
    # Check for WordPress.com first (before generic WordPress check)
    if ($Content -match 'wordpress.com|jetpack|blog_id.*26086|data-blog') { return 'WordPress.com' }
    
    # Check for specific platform markers
    if ($Content -match 'archive__item') { return 'Jekyll' }
    if ($Content -match 'class="listing-item".*?class="title"') { return 'DisplayPostsListing' }
    if ($Content -match 'wix-essential-viewer-model|communities-blog-ooi') { return 'Wix' }
    if ($Content -match 'wp-content|wp-admin') { return 'WordPress' }
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
        if ($platform -eq 'WordPress.com') {
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
            Write-Host "Platform not specifically supported. Attempting generic extraction..." -ForegroundColor DarkGray
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
