# Blog Post Export Script

## Overview

`export-blog-posts-generic.ps1` is a flexible, reusable PowerShell script that exports blog post metadata from **any blog platform or markdown collection**. It works by extracting data from markdown front matter, JSON APIs, or web requests—without requiring direct access to local HTML files.

Key Features:
- **Decoupled from file system** - Works with URLs, APIs, and local files
- **Portable** - Can run from any location
- **Scalable** - Supports multiple data sources
- **Flexible** - Adapts to different blog architectures
- **Zero dependencies** - Pure PowerShell, no external tools needed

## Why Use This Script?

### Use Cases

1. **Portfolio Auditing** - Track what you've published over time
2. **Content Migration** - Export posts before migrating to a new platform
3. **Analytics** - Analyze publishing patterns, categories, and timing
4. **Backup Verification** - Ensure all posts are captured with correct metadata
5. **Integration** - Feed data into external tools or dashboards

## How It Works

### Data Sources (In Order of Priority)

1. **Markdown Front Matter** (Primary)
   - Extracts YAML or TOML front matter from `.md` files
   - Reads: `date`, `title`, `categories`, `tags`
   - Location: Local `/blog/src/posts/` directory

2. **Blog API Endpoint** (Secondary)
   - Calls your blog's JSON API if available
   - Expected format: `/api/posts` returning JSON array
   - Fields: `date`, `title`, `category`, `url`, `slug`

3. **HTML Elements** (Fallback)
   - Parses `<time>` tags for dates
   - Parses `<h1>` tags for titles
   - Parses `<span class="category">` for categories

### Processing Steps

```
1. Initialize parameters (URLs, date ranges, output file)
2. Load category mapping configuration
3. Read markdown files from local directory OR fetch from API
4. For each post:
   - Extract date from front matter
   - Filter by date range (StartDate to EndDate)
   - Extract title from metadata
   - Extract categories and map to reporting categories
   - Build post URL from slug
5. Sort posts by date (newest first)
6. Export to CSV format
7. Display summary statistics
```

## Usage

### Basic Usage (Default - Local Markdown)

```powershell
.\export-blog-posts-generic.ps1
```

**Output:** `blog-export.csv` with all posts from the last 5 years

### Custom Date Range

```powershell
.\export-blog-posts-generic.ps1 `
  -StartDate "2024-01-01" `
  -EndDate "2024-12-31"
```

### Web API Mode (No Local Files)

```powershell
.\export-blog-posts-generic.ps1 `
  -BlogURL "https://yourblog.com/api" `
  -UseLocalFiles $false
```

### Custom Output File

```powershell
.\export-blog-posts-generic.ps1 `
  -OutputFile "exported-posts-2024.csv"
```

### Specify Custom Posts Directory

```powershell
.\export-blog-posts-generic.ps1 `
  -PostsDirectory "D:\my-blog\posts"
```

### Increase Request Timeout for Large Blogs

```powershell
.\export-blog-posts-generic.ps1 `
  -RequestTimeout 30 `
  -UseLocalFiles $false
```

### Combined Parameters Example

```powershell
.\export-blog-posts-generic.ps1 `
  -PostsDirectory "C:\blog\markdown" `
  -OutputFile "posts-export.csv" `
  -StartDate "2024-06-01" `
  -EndDate "2024-12-31"
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BlogURL` | `https://yourblog.com` | Base URL of your blog or API endpoint |
| `PostsDirectory` | `./posts` | Path to local markdown files directory |
| `OutputFile` | `blog-export.csv` | Name of output CSV file |
| `StartDate` | 5 years ago | Filter posts from this date onward |
| `EndDate` | Today | Filter posts until this date |
| `UseLocalFiles` | `$false` | Try web API first, fall back to local files |
| `RequestTimeout` | `10` seconds | HTTP request timeout for API calls |

## Output Format

### CSV Structure

```
Date;Category;Title;URL;FileName
2024-12-06;Identity;Enterprise Identity Management;https://yourblog.com/posts/identity-mgmt;identity-management.md
2024-12-05;Cloud;Cloud Architecture Best Practices;https://yourblog.com/posts/cloud-arch;cloud-architecture.md
2024-12-01;Security;Security Hardening Guide;https://yourblog.com/posts/security;security-hardening.md
```

### Console Output Example

```
Blog Post Export - Option 2 (Web-based)
========================================
Blog URL: https://yourblog.com
Date Range: 12/1/2024 to 12/7/2024
Output: blog-export.csv

Reading from local markdown files: ./posts
Found 150 markdown files

✅ Export complete!
Total posts exported: 45

Posts by Category:
  Identity: 20
  Cloud: 15
  Security: 10

First 5 entries:
Date      Category     Title                          URL                           FileName
----      --------     -----                          ---                           --------
12/6/2024 Identity     Enterprise Identity Mgmt       https://.../identity-mgmt     identity-management.md
12/5/2024 Cloud        Cloud Architecture             https://.../cloud-arch        cloud-architecture.md
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
    'Custom Tag' = 'Reporting Category'
}
```

### Option 2: Modify Front Matter Extraction

Update `Get-PostDateFromMetadata` or `Get-PostTitleFromMetadata` functions to match your front matter format:

```powershell
# Example: If your front matter uses 'created' instead of 'date'
if ($frontMatter -match '(?i)created\s*[:=]\s*[''"]?(\d{4}-\d{2}-\d{2})') {
    return [datetime]::Parse($matches[1])
}
```

### Option 3: Connect to Blog API

If your blog exposes an API, modify the API URL and response handling:

```powershell
$apiUrl = "$BlogURL/api/v1/posts"  # Update endpoint
# Adjust the JSON parsing based on your API response structure
```

### Option 4: Add Additional Metadata Fields

Extend the output CSV by adding properties to the `$posts` object:

```powershell
$posts += [PSCustomObject]@{
    Date = $date
    Category = $reportingCategory
    Title = $title
    URL = $postURL
    FileName = $file.Name
    WordCount = (($content -split '\s+').Count)  # New field
    Author = "Your Name"                          # New field
}
```

## Troubleshooting

### Issue: "No posts found in the specified date range"

**Cause:** Date range is too narrow or date extraction failed.

**Solution:**
```powershell
# Check actual dates in your markdown files
Get-ChildItem -Path "./posts" -Filter "*.md" | 
  Select-Object Name, CreationTime, LastWriteTime | 
  Format-Table -AutoSize
```

### Issue: "Unknown Title" in output

**Cause:** Title extraction regex doesn't match your format.

**Solution:** Check your front matter format and adjust the regex in `Get-PostTitleFromMetadata`.

### Issue: API endpoint not found

**Cause:** Your blog doesn't have an API endpoint.

**Solution:** Use local files mode (default) or create a JSON feed endpoint.

```powershell
.\export-blog-posts-generic.ps1  # Uses local markdown by default
```

### Issue: Slow execution with many posts

**Cause:** Reading large files or slow API responses.

**Solution:**
- Increase `RequestTimeout` parameter
- Use smaller date range with `-StartDate` and `-EndDate`
- Filter directory before processing

### Issue: Permission denied errors

**Cause:** Insufficient permissions to read markdown files.

**Solution:**
```powershell
# Run PowerShell as Administrator
Start-Process pwsh -Verb RunAs
```

### Issue: Special characters causing CSV import errors

**Cause:** Semicolon delimiter conflicts with content.

**Solution:** Modify the export line to use different delimiter:

```powershell
$posts | Export-Csv -Path $OutputFile -Encoding UTF8 -NoTypeInformation -Delimiter ","
```

## Advanced Customization

### Filter by Category

```powershell
# Export only Identity posts
.\export-blog-posts-generic.ps1 | Where-Object { $_.Category -eq "Identity" }
```

### Add Word Count and Reading Time

Extend the script to calculate reading metrics:

```powershell
$wordCount = ($content -split '\s+').Count
$readingTime = [Math]::Ceiling($wordCount / 200)  # Assuming 200 words/minute
```

### Integrate with External Tools

The CSV output can be imported into:
- **Excel** - For pivot tables and charts
- **Power BI** - For dashboards
- **Google Sheets** - For cloud-based tracking
- **Database** - Via `Import-CSV | Invoke-Sqlcmd`

### Schedule as Automated Task

```powershell
# Create a scheduled task to export posts weekly
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
  -Argument "-File './export-blog-posts-generic.ps1'"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "BlogExport"
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

- **PowerShell** 5.0 or higher (any OS: Windows, macOS, Linux)
- **Local access** to markdown files directory (for markdown mode) OR
- **Network access** to blog URL/API (for web API mode)
- **Read permissions** on markdown files
- **Internet connection** (for web API mode)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2024-12-07 | Generic release: added Option 2 (web-based approach), API support, metadata extraction from multiple sources |
| 1.0 | 2024-12-01 | Initial release with HTML parsing |

## Contributing

Contributions are welcome! Areas for improvement:
- Additional blog platform support (WordPress, Ghost, Hugo, etc.)
- More metadata fields (author, reading time, word count)
- Database export options
- Performance optimizations for large blogs
- API auto-discovery

## License

This project is open source and available under the MIT License.

## Support

For issues, feature requests, or questions:
1. Check the Troubleshooting section
2. Review the Customization Guide
3. Verify your front matter format matches expected structure
4. Open an issue with:
   - Your blog platform/structure
   - Front matter example
   - Error message (if any)

## Acknowledgments

Built to simplify blog post metadata extraction across multiple platforms and architectures.
