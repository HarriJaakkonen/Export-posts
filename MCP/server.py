"""
Blog Post Export MCP Server

An MCP (Model Context Protocol) server that extracts blog post metadata
from 12+ different blog platforms. Supports Hugo, WordPress, Jekyll, Wix,
Ghost, Squarespace, and more.
"""

import re
import logging
from datetime import datetime, timedelta
from typing import Optional
from urllib.parse import urlparse, urljoin

import httpx
from mcp.server.fastmcp import FastMCP

from platforms import (
    detect_platform,
    discover_rss_feed,
    normalize_category,
    extract_hugo_posts,
    extract_wordpress_posts,
    extract_wordpress_rss_posts,
    extract_wordpress_com_posts,
    extract_jekyll_posts,
    extract_wix_posts,
    extract_display_posts_listing,
    extract_ghost_posts,
    extract_squarespace_posts,
    extract_vanilla_html_posts,
    extract_rss_posts,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("blog-export-mcp")

mcp = FastMCP(
    "blog-export",
    instructions="Export blog post metadata from 12+ platforms (Hugo, WordPress, Jekyll, Wix, Ghost, Squarespace, etc.)",
)

HTTP_TIMEOUT = 15.0


async def fetch_url(client: httpx.AsyncClient, url: str) -> Optional[str]:
    """Fetch content from a URL, returning None on failure."""
    try:
        resp = await client.get(url, follow_redirects=True, timeout=HTTP_TIMEOUT)
        resp.raise_for_status()
        return resp.text
    except Exception as e:
        logger.warning("Failed to fetch %s: %s", url, e)
        return None


@mcp.tool()
async def export_blog_posts(
    blog_url: str,
    start_date: str = "",
    end_date: str = "",
) -> str:
    """Export blog post metadata (date, title, category, URL) from a blog.

    Automatically detects the blog platform and extracts posts accordingly.
    Supports Hugo, WordPress (self-hosted & .com), Jekyll, Wix, Ghost,
    Squarespace, vanilla HTML, and RSS feeds.

    Args:
        blog_url: The blog homepage URL (e.g. "https://example-blog.com")
        start_date: Filter posts from this date (YYYY-MM-DD). Default: 5 years ago.
        end_date: Filter posts until this date (YYYY-MM-DD). Default: today.

    Returns:
        CSV-formatted text with columns: Date, Category, Title, URL
    """
    # Normalize URL
    if not blog_url.startswith(("http://", "https://")):
        blog_url = f"https://{blog_url}"
    blog_url = blog_url.rstrip("/")

    # Parse dates
    try:
        dt_start = datetime.strptime(start_date, "%Y-%m-%d") if start_date else datetime.now() - timedelta(days=5 * 365)
    except ValueError:
        return f"Invalid start_date format: '{start_date}'. Use YYYY-MM-DD."

    try:
        dt_end = datetime.strptime(end_date, "%Y-%m-%d") if end_date else datetime.now()
    except ValueError:
        return f"Invalid end_date format: '{end_date}'. Use YYYY-MM-DD."

    posts: list[dict] = []

    async with httpx.AsyncClient(
        headers={"User-Agent": "BlogExportMCP/1.0"},
        follow_redirects=True,
        timeout=HTTP_TIMEOUT,
    ) as client:
        content = await fetch_url(client, blog_url)
        if not content:
            return f"Failed to fetch blog at {blog_url}. Check the URL and try again."

        platform = detect_platform(content, blog_url)

        if platform == "Hugo":
            posts = extract_hugo_posts(content, blog_url, dt_start, dt_end)
            # Try menu page for more posts
            if len(posts) < 20:
                menu_content = await fetch_url(client, f"{blog_url}/posts/menu.html")
                if menu_content:
                    menu_posts = extract_hugo_posts(menu_content, blog_url, dt_start, dt_end, menu_mode=True)
                    existing_titles = {p["title"] for p in posts}
                    for p in menu_posts:
                        if p["title"] not in existing_titles:
                            posts.append(p)

        elif platform == "WordPress.com":
            posts = await extract_wordpress_com_posts(client, blog_url, dt_start, dt_end)

        elif platform == "WordPress":
            # Try RSS first
            posts = await extract_wordpress_rss_posts(client, content, blog_url, dt_start, dt_end)
            if not posts:
                # Try /blog page for Display Posts Listing
                blog_page = await fetch_url(client, f"{blog_url}/blog")
                if blog_page and "listing-item" in blog_page:
                    posts = extract_display_posts_listing(blog_page, blog_url, dt_start, dt_end)
                else:
                    posts = extract_wordpress_posts(content, blog_url, dt_start, dt_end)

        elif platform == "DisplayPostsListing":
            posts = extract_display_posts_listing(content, blog_url, dt_start, dt_end)

        elif platform == "Jekyll":
            posts = await extract_jekyll_posts(client, content, blog_url, dt_start, dt_end)

        elif platform == "Wix":
            posts = await extract_wix_posts(client, blog_url, dt_start, dt_end)

        elif platform == "Ghost":
            posts = await extract_ghost_posts(client, blog_url, dt_start, dt_end)

        elif platform == "Squarespace":
            posts = await extract_squarespace_posts(client, blog_url, dt_start, dt_end)

        else:
            # Try RSS auto-discovery first
            feed_urls = discover_rss_feed(content, blog_url)
            if feed_urls:
                for feed_url in feed_urls:
                    posts = await extract_rss_posts(client, feed_url, dt_start, dt_end)
                    if posts:
                        break
            if not posts:
                posts = await extract_vanilla_html_posts(client, content, blog_url, dt_start, dt_end)

    if not posts:
        return f"No posts found at {blog_url} in range {dt_start.strftime('%Y-%m-%d')} to {dt_end.strftime('%Y-%m-%d')}.\nDetected platform: {platform}"

    # Sort by date descending
    posts.sort(key=lambda p: p["date"], reverse=True)

    # Build CSV output
    lines = ["Date;Category;Title;URL"]
    for p in posts:
        # Escape semicolons in title
        title = p["title"].replace(";", ",")
        lines.append(f"{p['date']};{p['category']};{title};{p['url']}")

    # Summary
    from collections import Counter
    cat_counts = Counter(p["category"] for p in posts)
    summary_parts = [f"\nPlatform detected: {platform}", f"Total posts: {len(posts)}", "\nPosts by category:"]
    for cat, count in cat_counts.most_common():
        summary_parts.append(f"  {cat}: {count}")

    return "\n".join(lines) + "\n" + "\n".join(summary_parts)


@mcp.tool()
async def detect_blog_platform(blog_url: str) -> str:
    """Detect which blogging platform a URL is using.

    Args:
        blog_url: The blog homepage URL to analyze.

    Returns:
        The detected platform name and details.
    """
    if not blog_url.startswith(("http://", "https://")):
        blog_url = f"https://{blog_url}"
    blog_url = blog_url.rstrip("/")

    async with httpx.AsyncClient(
        headers={"User-Agent": "BlogExportMCP/1.0"},
        follow_redirects=True,
        timeout=HTTP_TIMEOUT,
    ) as client:
        content = await fetch_url(client, blog_url)
        if not content:
            return f"Failed to fetch {blog_url}. Check the URL and try again."

        platform = detect_platform(content, blog_url)
        feed_urls = discover_rss_feed(content, blog_url)

        result = f"URL: {blog_url}\nDetected Platform: {platform}"
        if feed_urls:
            result += f"\nRSS Feeds Found: {', '.join(feed_urls)}"
        else:
            result += "\nNo RSS feeds discovered in page HTML."

        return result


@mcp.tool()
async def list_supported_platforms() -> str:
    """List all blog platforms supported by the export tool.

    Returns:
        A table of supported platforms with detection methods and capabilities.
    """
    platforms = [
        ("Hugo", "CSS class 'compact-card'", "Full archive extraction"),
        ("WordPress (self-hosted)", "'wp-content' markers", "RSS feed + HTML parsing"),
        ("WordPress (RSS)", "RSS feed auto-discovery", "Full archive via RSS"),
        ("WordPress + Display Posts Listing", "'listing-item' elements", "Full pagination support"),
        ("WordPress + WP Grid Builder", "'wpgb-card' elements", "Per-post fetching"),
        ("WordPress.com", "REST API detection", "All published posts via API"),
        ("Jekyll", "'archive__item' divs", "Featured posts with per-post fetch"),
        ("Wix", "RSS feed '/blog-feed.xml'", "All posts via RSS"),
        ("Ghost CMS", "Ghost markers + RSS", "All posts via RSS"),
        ("Squarespace", "Squarespace markers", "All posts via RSS"),
        ("Vanilla HTML", "Generic link extraction", "Post-level fetching"),
    ]

    lines = ["Platform | Detection Method | Capability"]
    lines.append("--- | --- | ---")
    for name, detection, capability in platforms:
        lines.append(f"{name} | {detection} | {capability}")

    return "\n".join(lines)


if __name__ == "__main__":
    import os
    import sys

    transport = "stdio"
    # Use streamable-http when running in a container or when --http flag is passed
    if "--http" in sys.argv or "MCP_TRANSPORT" in os.environ:
        transport = "streamable-http"
        mcp.settings.host = "0.0.0.0"  # noqa: S104 – bind all interfaces in container
        mcp.settings.port = int(os.environ.get("MCP_PORT", "8000"))

    mcp.run(transport=transport)
