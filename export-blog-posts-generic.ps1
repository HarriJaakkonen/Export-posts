# Generic Blog Post Export Script - Option 2 (Web-based)
# This script extracts blog post metadata WITHOUT requiring local HTML files
# Instead, it works with URLs and fetches content on-demand via HTTP requests

param(
    [string]$BlogURL = "https://cloudpartner.cloud/blog",
    [string]$PostsDirectory = "c:\Repos\cloudpartner\blog\src\posts",
    [string]$OutputFile = "blog-export.csv",
    [datetime]$StartDate = (Get-Date).AddYears(-5),
    [datetime]$EndDate = (Get-Date),
    [switch]$UseLocalFiles = $false,
    [int]$RequestTimeout = 10
)

# Category mapping - customize based on your blog structure
$categoryMapping = @{
    'AI Security' = 'AI'
    'Cloud Security' = 'Cloud'
    'Data Security' = 'Data'
    'Identity' = 'Identity'
    'Zero Trust' = 'Security'
    'Entra' = 'Identity'
    'Azure' = 'Cloud'
    'Microsoft' = 'Cloud'
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
                    Date = $date
                    Category = $reportingCategory
                    Title = $title
                    URL = $postURL
                    FileName = $file.Name
                }
                
                $exportCount++
            }
        }
    }
}

# Option 2: Fetch from web (requires blog to have an API or index)
# Example: if your blog has a JSON API endpoint
if (-not $UseLocalFiles -and $exportCount -eq 0) {
    Write-Host "Option 2 Mode: Fetching from web API" -ForegroundColor Yellow
    Write-Host "Note: This requires an API endpoint or JSON feed from your blog" -ForegroundColor Yellow
    Write-Host ""
    
    # Example: Try to fetch from a blog API endpoint
    $apiUrl = "$BlogURL/api/posts"
    Write-Host "Attempting to fetch from: $apiUrl" -ForegroundColor Gray
    
    try {
        $apiResponse = Invoke-WebRequest -Uri $apiUrl -TimeoutSec $RequestTimeout -ErrorAction Stop
        $apiPosts = $apiResponse.Content | ConvertFrom-Json
        
        foreach ($post in $apiPosts) {
            if ($post.date -and [datetime]$post.date -ge $StartDate -and [datetime]$post.date -le $EndDate) {
                $posts += [PSCustomObject]@{
                    Date = [datetime]$post.date
                    Category = Get-ReportingCategory -Category $post.category
                    Title = $post.title
                    URL = $post.url
                    FileName = $post.slug
                }
                $exportCount++
            }
        }
    }
    catch {
        Write-Host "API endpoint not available. Falling back to local file scanning..." -ForegroundColor Yellow
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
Write-Host "Output file: $(Resolve-Path $OutputFile)" -ForegroundColor Cyan
