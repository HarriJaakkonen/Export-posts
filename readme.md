# Blog Post Export Script

A flexible PowerShell script that extracts blog post metadata from **8 different blog platforms** automatically. Export dates, titles, categories, and URLs in seconds—no manual work required.

## What This Does

- ✅ **Detects blog platform automatically** - Identifies which CMS/platform your blog uses
- ✅ **Exports all post metadata** - Date, title, category, URL in CSV format
- ✅ **Filters by date range** - Extract only posts from a specific time period
- ✅ **Works with live blogs** - Scrapes URLs directly, no need for local files
- ✅ **Zero dependencies** - Pure PowerShell, built-in cmdlets only

## Supported Blog Platforms

| Platform | Detection Method | Capability | Example |
|----------|------------------|-----------|---------|
| **Hugo** | CSS class `compact-card` | Full archive extraction | Static site generator |
| **WordPress (self-hosted)** | `wp-content` markers | Homepage posts | Standard theme |
| **WordPress (alt theme)** | `<time>` datetime tags | Homepage posts | Alternative theme |
| **WordPress + Display Posts Listing** | `listing-item` elements | Full pagination support | Plugin-enhanced |
| **WordPress + WP Grid Builder** | `wpgb-card` elements | Per-post fetching | Plugin-enhanced |
| **WordPress.com** | REST API detection | All published posts | Automattic-hosted |
| **Jekyll** | `archive__item` divs | Featured posts | Static site generator |
| **Wix** | RSS feed `/blog-feed.xml` | All posts via RSS | Wix CMS |

## Quick Start

### Basic Usage

```powershell
.\export-blog-posts-generic.ps1 -BlogURL "https://example-blog.com"
```

Outputs: `blog-export.csv` with all posts from the last 5 years

### Custom Date Range

```powershell
.\export-blog-posts-generic.ps1 -BlogURL "https://example-blog.com" `
  -StartDate "2025-06-01" `
  -EndDate "2025-12-31"
```

### Custom Output File

```powershell
.\export-blog-posts-generic.ps1 -BlogURL "https://example-blog.com" `
  -OutputFile "my-posts.csv"
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-BlogURL` | `https://example-blog.com` | Blog homepage URL |
| `-OutputFile` | `blog-export.csv` | Name of output CSV file |
| `-StartDate` | 5 years ago | Filter from this date (YYYY-MM-DD) |
| `-EndDate` | Today | Filter until this date (YYYY-MM-DD) |
| `-PostsDirectory` | `c:\blog\src\posts` | Local markdown directory (optional) |
| `-RequestTimeout` | `10` seconds | HTTP request timeout |

## Output Format

### CSV File

```
Date;Category;Title;URL;FileName
2025-12-07;Technology;How to Export Blog Posts;https://example-blog.com/posts/export-posts;export-posts
2025-12-05;Cloud;Cloud Architecture Guide;https://example-blog.com/posts/cloud-guide;cloud-guide
2025-12-01;Tutorial;PowerShell Tips;https://example-blog.com/posts/powershell-tips;powershell-tips
```

### Console Output

```
Blog Post Export
================
Blog URL: https://example-blog.com
Date Range: 06/01/2025 to 12/31/2025
Output: my-posts.csv

Reading from local markdown files...
Found 0 markdown files
Option 2 Mode: Fetching from web HTML...
Attempting to fetch posts from: https://example-blog.com

Detected platform: WordPress
Found 47 posts

✅ Export complete!
Total posts exported: 47

Posts by Category:
  Cloud: 23
  Tutorial: 15
  DevOps: 9

Output file: C:\my-posts.csv
```

## How It Works

### Detection Process

The script checks for platform-specific HTML markers in this order:

1. **Jekyll** - Look for `<div class="archive__item">` elements
2. **Display Posts Listing** - Look for `<li class="listing-item">` with `<a class="title">`
3. **Wix** - Look for `wix-essential-viewer-model` or try `/blog-feed.xml`
4. **WordPress** - Look for `wp-content` or `WordPress` markers
5. **Hugo** - Look for `<article class="compact-card">` elements
6. **WP Grid Builder** - Look for `<article class="wpgb-card">` elements

Once detected, the appropriate extraction function is called.

### Extraction Methods

#### Server-Rendered Blogs (Hugo, WordPress, Jekyll)
- Fetches HTML from blog URL
- Parses DOM structure with regex patterns
- Extracts: date, title, category, URL
- No JavaScript execution needed

#### WordPress with Plugins (Display Posts Listing, WP Grid Builder)
- Detects plugin-specific HTML patterns
- Handles pagination for full post extraction
- Fetches individual posts for metadata if needed

#### Wix (JavaScript SPA)
- Attempts RSS feed at `/blog-feed.xml`
- Parses standard RSS/Atom XML format
- Works because Wix generates RSS feeds even though frontend is JavaScript
- Extracts posts without needing JavaScript execution

### Date Parsing

Supports multiple date formats automatically:

| Format | Example | Platform |
|--------|---------|----------|
| DD/MM/YYYY | `05/12/2025` | Hugo |
| Month Day, Year | `December 5, 2025` | WordPress standard |
| YYYY-MM-DD | `2025-12-05` | Hugo, Jekyll |
| ISO+Time | `2025-12-05T18:05:27` | WordPress alt, Jekyll |
| RFC 2822 | `Tue, 05 Dec 2025 18:05:27 GMT` | Wix (RSS) |

## Examples by Platform

### WordPress Blog

```powershell
# Export all posts
.\export-blog-posts-generic.ps1 -BlogURL "https://my-wordpress.example.com"

# Result: Detects WordPress, extracts posts from homepage
# Output: blog-export.csv with 10-50 posts depending on pagination
```

### Wix Blog

```powershell
# Wix blog with RSS feed
.\export-blog-posts-generic.ps1 -BlogURL "https://my-wix-site.example.com"

# Result: Detects Wix, fetches /blog-feed.xml
# Output: blog-export.csv with all posts in RSS feed
```

### Hugo Static Site

```powershell
# Hugo blog with archive
.\export-blog-posts-generic.ps1 -BlogURL "https://my-hugo-site.example.com"

# Result: Detects Hugo, extracts from homepage + archive page
# Output: blog-export.csv with 100+ posts
```

### WordPress with Display Posts Listing Plugin

```powershell
# WordPress with DPL plugin showing full archive
.\export-blog-posts-generic.ps1 -BlogURL "https://wordpress-with-dpl.example.com"

# Result: Detects Display Posts Listing, extracts full archive
# Output: blog-export.csv with 50-300+ posts
```

## What Gets Extracted

For each blog post, the script captures:

- **Date** - Publication date (parsed from multiple formats)
- **Title** - Post title (HTML-decoded)
- **Category** - Primary category (mapped to reporting categories if configured)
- **URL** - Full post URL
- **FileName** - URL slug (used as filename if needed)

## Limitations & Notes

### Pagination
- Most platforms extract only homepage posts
- Display Posts Listing plugin handles full pagination automatically
- Wix extracts all posts available in RSS feed

### Categories
- Some platforms don't include categories in RSS/homepage
- Individual post fetching can retrieve categories but is slower
- Script defaults to "Uncategorized" when not available

### JavaScript-Heavy Sites
- Wix works via RSS feed (special case)
- Other JavaScript SPAs may not work
- For unsupported platforms, consider using browser automation tools

### Date Range Filtering
- Applied after extraction, not during scraping
- Large date ranges are faster (fewer filter operations)
- Filters are inclusive: StartDate ≤ post date ≤ EndDate

## Customization

### Category Mapping

Edit the `$categoryMapping` hashtable in the script:

```powershell
$categoryMapping = @{
    'MyCategory1'    = 'ReportingCategory1'
    'MyCategory2'    = 'ReportingCategory2'
}
```

### Default Parameters

Edit the `param()` section for your preferred defaults:

```powershell
param(
    [string]$BlogURL = "https://your-default-blog.com",
    [string]$OutputFile = "your-default-name.csv",
    [datetime]$StartDate = (Get-Date).AddYears(-1),  # Default to 1 year
    ...
)
```

## Troubleshooting

### "Platform: Unknown"
- Blog uses unsupported CMS/platform
- Try checking the HTML source to identify unique patterns
- Consider adding custom detection patterns to the script

### No Posts Found
- Homepage may not display posts
- Try `/blog` or `/posts/` URL paths
- For pagination-heavy sites, may need manual adjustment

### Dates Parsing Incorrectly
- Multiple date formats on same blog
- Check if dates match expected patterns in Date Format Reference
- May need custom date parsing function

### Too Many/Too Few Posts
- Check date range filters are correct
- Verify URL is blog homepage, not category/archive page
- Some platforms paginate - only homepage posts extracted by default

## Technical Details

### Architecture

The script follows this flow:

```
Input Parameters
       ↓
Check for local markdown files
       ↓
If no files found, proceed to web mode
       ↓
Fetch blog homepage HTML
       ↓
Detect platform type
       ↓
Call appropriate extraction function
       ↓
Filter by date range
       ↓
Sort by date (newest first)
       ↓
Export to CSV
       ↓
Display summary statistics
```

### Performance

- Homepage-only extraction: **< 5 seconds**
- Full archive extraction: **2-5 minutes** (depends on site size)
- Per-post metadata fetching: **1-2 minutes per 10 posts** (slowest)

### Dependencies

- **None** - Uses only built-in PowerShell cmdlets
- Requires PowerShell 5.0 or later
- Requires `System.Web` assembly (loaded automatically)

## Future Platform Support

Potential candidates for future support:

- **Ghost** - Has public API, relatively easy
- **Blogger/Blogspot** - Has blog archive feeds
- **Medium/Dev.to/Hashnode** - Have public APIs
- **Statamic, Craft CMS** - Custom implementations possible
- **Strapi, Sanity** - Headless CMS with APIs

To add support for a new platform, document the HTML markers and detection patterns, then create an extraction function following existing patterns.

## License & Usage

This script is provided as-is for blog content management and auditing purposes. Respect `robots.txt` and site terms of service when scraping.

---

**Last Updated:** December 7, 2025  
**Supported Platforms:** 7  
**Status:** ✅ Production Ready

2025-12-06 Technology  Example Blog Post Title
2025-12-03 Technology  Another Blog Post
2025-11-27 Category1   Third Blog Post Title

Output file: C:\Repos\Export-posts\recent-posts.csv
```

## Customization Guide

### Option 1: Change Category Mapping

Edit the `$categoryMapping` hashtable to match your blog structure:

```powershell
$categoryMapping = @{
    'AI Security' = 'AI'
    'Cloud Security' = 'Cloud'
    'Data Security' = 'Data'
    'Identity' = 'Identity'
    'Zero Trust' = 'Security'
    'entra' = 'Identity'
    'security' = 'Security'
    'Custom Tag' = 'Reporting Category'
}
```

### Option 2: Modify HTML Scraping Pattern

If your blog uses different HTML structure, update the regex pattern in the "Option 2 Mode" section:

```powershell
# Example: If your articles use <div class="post"> instead of <article class="compact-card">
$articlePattern = '<div[^>]*class="[^"]*post[^"]*".*?<h2>([^<]+)</h2>.*?<span class="date">(\d{4}-\d{2}-\d{2})</span>'
```

### Option 3: Modify Front Matter Extraction

Update `Get-PostDateFromMetadata` or `Get-PostTitleFromMetadata` functions to match your front matter format:

```powershell
# Example: If your front matter uses 'created' instead of 'date'
## Real-World Test Results

### Example 1: Hugo-based Blog

```
Blog URL: https://example-hugo-blog.com
Date Range: 5 years
Platform Detected: Hugo
Results:
  - Homepage posts: 14
  - Archive posts: 297
  - Total exported: 311 posts
  - Date format: DD/MM/YYYY
  - Categories: Technology, Business, Tutorial, etc.
Status: ✅ Success
```

**CSV Output Sample:**
```
Date;Category;Title;URL;FileName
2025-12-07;Technology;Latest post title;https://example-hugo-blog.com/posts/latest/;latest
2025-11-20;Business;Business post title;https://example-hugo-blog.com/posts/business/;business
...
```

### Example 2: WordPress - Standard Theme

```
Blog URL: https://example-wordpress-blog.com
Date Range: 5 years
Platform Detected: WordPress
Results:
  - Homepage posts: 10 (WordPress shows 10 per page by default)
  - Archive: Pagination not supported
  - Total exported: 10 posts (limitation: homepage only)
  - Date format: "Month Day, Year" (May 4, 2024)
  - Categories: Technology, Updates, Guides
Status: ⚠️ Partial (homepage only, may miss older/paginated posts)
```

### Example 3: WordPress - Alternative Theme

```
Blog URL: https://example-wp-alt-blog.com
Date Range: 5 years
Platform Detected: WordPress
Results:
  - Homepage posts: 8 (theme shows 8 per page)
  - Archive: Pagination not supported
  - Total exported: 8 posts (limitation: homepage only)
  - Date format: ISO (2022-05-15) via <time datetime="...">
  - Categories: Technology, Updates, Tutorials
Status: ⚠️ Partial (homepage only, may miss older/paginated posts)
```

### Example 4: WordPress - WP Grid Builder Plugin

```
Blog URL: https://example-wpgb-blog.com
Date Range: 5 years
Platform Detected: WordPress + WP Grid Builder
Results:
  - Grid Builder index page: 9 posts
  - Archive: Custom grid builder index
  - Total exported: 9 posts
  - Date format: ISO via JSON-LD schema (2025-12-02T06:53:39+00:00)
  - Categories: Technology, Updates, Tutorials (extracted from pages)
Status: ✅ Success (WP Grid Builder detected and used)
```

**CSV Output Sample:**
```
Date;Category;Title;URL;FileName
2025-12-02;Technology;Example Grid Builder Post;https://example-wpgb-blog.com/example-post/;example-post
2025-11-26;Updates;Another Grid Post;https://example-wpgb-blog.com/another-post/;another-post
...
```

## Platform Support Matrix

| Platform | Detection | Extraction | Date Parsing | Archives | Status |
|----------|-----------|-----------|---|---|---|
| Hugo | ✅ `class="compact-card"` | ✅ HTML regex | ✅ DD/MM/YYYY | ✅ `/posts/menu.html` | **Full Support** |
| WordPress (standard) | ✅ `wp-content` markers | ✅ `id="post-XXXX"` | ✅ "Month Day, Year" | ❌ Pagination not supported | **Partial** |
| WordPress (alt theme) | ✅ `WordPress` in markup | ✅ `<h1 class="title">` | ✅ ISO datetime | ❌ Pagination not supported | **Partial** |
| WordPress + Display Posts Listing | ✅ `class="listing-item"` | ✅ Listing pattern | ✅ "Month Day, Year" | ✅ Plugin pagination | **Full Support** |
| WordPress + WP Grid Builder | ✅ `wpgb-card` elements | ✅ Grid index pages | ✅ JSON-LD schema | ✅ Plugin index pages | **Full Support** |
| Jekyll | ✅ `archive__item` divs | ✅ Archive structure | ✅ ISO datetime | ❌ Full archive not supported | **Partial** |
| Wix | ✅ RSS feed `/blog-feed.xml` OR `wix-essential-viewer-model` | ✅ RSS parsing with CDATA | ✅ ISO datetime | ✅ RSS pagination | **Full Support** |

## Limitations

1. **WordPress Pagination:** Script only captures posts visible on homepage/first page. To get all posts:
   - Look for `/page/2`, `/page/3` etc. URLs
   - Or request access to WordPress REST API: `/wp-json/wp/v2/posts`
   - Or use WordPress admin export feature

2. **WP Grid Builder:** Script auto-detects and uses `/tutorials/` page if available. If your site uses a different page slug for the grid builder, update the `$tutorialsUrl` in the script.

3. **Jekyll Blogs:** Currently extracts homepage featured posts. Full archive would require `/blog/` page support with pagination.

4. **Archive Detection:** Currently looks for:
   - `/posts/menu.html` (Hugo standard)
   - `/tutorials/` (WP Grid Builder)
   - WordPress uses pagination instead

5. **Date Parsing:** Supports common formats:
    - DD/MM/YYYY (Hugo)
   - "Month Day, Year" (WordPress standard)
   - ISO datetime (WordPress alt themes, Jekyll)
   - JSON-LD schema (WordPress + WP Grid Builder)
   - Custom formats may require pattern updates

6. **Category Extraction:** Universal support for:
   - `<span class="post-category">` with category links
   - `<span class="page__meta-category">` with category links
   - `data-category` attributes
   - JSON-LD keywords
   - Direct extraction from post pages (slower but accurate)

## Future Enhancements

To improve multi-platform support, planned additions:
- [ ] WordPress REST API support (`/wp-json/wp/v2/posts`) for complete pagination
- [ ] Ghost platform detection and extraction
- [ ] Pagination follow for WordPress posts
- [ ] Automatic date format detection
- [ ] Category standardization across platforms
- [ ] Author extraction and export

```

### Option 4: Add Additional Metadata Fields

Extend the output CSV by adding properties to the `$posts` object:

```powershell
$posts += [PSCustomObject]@{
    Date = $date.ToString('yyyy-MM-dd')
    Category = $reportingCategory
    Title = $title
    URL = $postURL
    FileName = Split-Path -Leaf $postPath
    WordCount = (($content -split '\s+').Count)  # New field
    Author = "Your Name"                          # New field
}
```

## Troubleshooting

### Issue: "No posts found in the specified date range"

**Cause:** Date range is too narrow, date extraction failed, or blog structure is different.

**Solution:**
```powershell
# Run without date range to see all posts
.\export-blog-posts-generic.ps1 -BlogURL "https://your-blog.com"

# Check if dates are being parsed correctly
# Review the CSV output to see what dates were found
```

### Issue: "Unknown Title" in output

**Cause:** Title extraction didn't match your blog's HTML structure.

**Solution:** Check your blog's HTML source and update the regex pattern in the "Option 2 Mode: Fetching from web HTML" section.

### Issue: Wrong categories are being captured

**Cause:** Category mapping doesn't match your tags/categories.

**Solution:** Update the `$categoryMapping` hashtable to match your actual category names:

```powershell
# View what categories were found
Get-Content blog-export.csv | ConvertFrom-Csv -Delimiter ";" | Group-Object Category | Select-Object Name, Count
```

### Issue: Slow execution with many posts

**Cause:** Slow network connection or large blog.

**Solution:**
- Increase `RequestTimeout` parameter
- Use smaller date range with `-StartDate` and `-EndDate`

### Issue: Special characters causing CSV import errors

**Cause:** Semicolon delimiter conflicts with content, or encoding issue.

**Solution:** Modify the export line to use different delimiter:

```powershell
$posts | Export-Csv -Path $OutputFile -Encoding UTF8 -NoTypeInformation -Delimiter ","
```

## Advanced Usage

### Filter by Category

```powershell
# Export and view only Identity posts
$posts = Import-Csv blog-export.csv -Delimiter ";"
$posts | Where-Object { $_.Category -eq "Identity" } | Export-Csv identity-posts.csv -Delimiter ";"
```

### Analyze Post Distribution

```powershell
# Count posts per category
$posts = Import-Csv blog-export.csv -Delimiter ";"
$posts | Group-Object Category | Select-Object Name, Count | Sort-Object Count -Descending
```

### Integrate with External Tools

The CSV output can be imported into:
- **Excel** - For pivot tables and charts
- **Power BI** - For dashboards
- **Google Sheets** - For cloud-based tracking
- **Database** - Via `Import-Csv | ConvertTo-Json | Invoke-SqlCmd`

### Schedule as Automated Task

```powershell
# Create a scheduled task to export posts daily
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
  -Argument "-File 'C:\Scripts\export-blog-posts-generic.ps1' -BlogURL 'https://example-blog.com' -OutputFile 'daily-export.csv'"
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "BlogPostExport"
```

## Installation

1. Clone or download this repository
2. Place both `export-blog-posts-generic.ps1` and this README in your project
3. Update the parameters in the script to match your blog structure
4. Run the script:
   ```powershell
   .\export-blog-posts-generic.ps1
   ```

## Requirements

- **PowerShell** 5.0 or higher (Windows, macOS, or Linux)
- **Internet connection** (for web scraping)
- **Network access** to your blog URL

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.0 | 2025-12-07 | **Major:** Added Wix platform support via RSS feed extraction. Added WordPress /blog fallback for DPL plugin. Now supports 7 platforms total with comprehensive documentation. |
| 3.0 | 2025-12-06 | **Major:** Added multi-platform support - Hugo, WordPress (3 variants), WP Grid Builder, Jekyll. Implemented universal category extraction. Tested with 5 different blog types. |
| 2.0 | 2024-12-07 | Generic release: added web-based approach, metadata extraction from multiple sources |
| 1.0 | 2024-12-01 | Initial release with HTML parsing |

## Contributing

Contributions are welcome! Areas for improvement:

**High Priority:**
- [ ] WordPress REST API support (`/wp-json/wp/v2/posts`) for paginated posts
- [ ] Ghost platform detection and extraction
- [ ] Automatic archive page discovery
- [ ] Full Jekyll archive support (`/blog/` pagination)

**Medium Priority:**
- [ ] GitHub Pages Jekyll site support
- [ ] Medium.com / Hashnode / Dev.to platforms
- [ ] Pagination follow-through (posts beyond page 1)
- [ ] Author extraction and export
- [ ] Reading time calculation

**Low Priority:**
- [ ] Database export options (SQL, MongoDB)
- [ ] Performance optimizations for very large blogs (1000+ posts)
- [ ] HTML structure auto-detection
- [ ] More metadata fields (word count, featured image, etc.)

## Platform Roadmap

**Currently Supported (8 Platforms):**
- ✅ Hugo
- ✅ WordPress (3+ theme variants)
- ✅ WordPress + Display Posts Listing plugin
- ✅ WordPress + WP Grid Builder plugin
- ✅ WordPress.com
- ✅ Jekyll
- ✅ Wix

**Planned Support:**
- ⏳ WordPress REST API (`/wp-json/wp/v2/posts`) for unlimited pagination
- ⏳ Ghost
- ⏳ Medium / Hashnode / Dev.to
- ⏳ Custom static site generators
- ⏳ GitHub Pages (Jekyll)

## License

This project is open source and available under the MIT License.

## Support

For issues, feature requests, or questions:

1. **Check the Troubleshooting section** - Most common issues are covered
2. **Review the Customization Guide** - To adapt for your blog structure
3. **Verify your blog's HTML** - Right-click → Inspect Element to see the structure
4. **Check the CSV output** - Verify dates, titles, and URLs are being captured correctly
5. **Open an issue with:**
   - Your blog URL
   - Blog platform/structure description
   - HTML snippet of a blog post element
   - Any error messages received

## Acknowledgments

Built to simplify blog post metadata extraction across multiple platforms and architectures. Successfully tested with multiple blogs running:
- Hugo static site generator
- WordPress with standard themes
- WordPress with alternative themes
- WordPress with WP Grid Builder plugin
- Jekyll static site generator
