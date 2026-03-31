"""
Platform detection and post extraction logic for the Blog Export MCP server.

Ported from the PowerShell script export-blog-posts-generic.ps1.
"""

import re
import logging
import xml.etree.ElementTree as ET
from datetime import datetime
from html import unescape
from typing import Optional
from urllib.parse import urljoin

import httpx

logger = logging.getLogger("blog-export-mcp")

# ---------------------------------------------------------------------------
# Category normalisation
# ---------------------------------------------------------------------------

CATEGORY_MAP: dict[str, str] = {
    "AI": "Artificial Intelligence",
    "MACHINE LEARNING": "Artificial Intelligence",
    "ML": "Artificial Intelligence",
    "LLM": "Artificial Intelligence",
    "GENERATIVE AI": "Artificial Intelligence",
    "COPILOT": "Artificial Intelligence",
    "SECURITY COPILOT": "Artificial Intelligence",
    "ARTIFICIAL INTELLIGENCE": "Artificial Intelligence",
    "AZURE": "Cloud",
    "CLOUD": "Cloud",
    "MICROSOFT AZURE": "Cloud",
    "AZURE SERVICES": "Cloud",
    "AZURE RESOURCE MANAGER": "Cloud",
    "ARM": "Cloud",
    "SECURITY": "Security",
    "AI SECURITY": "Security",
    "CLOUD SECURITY": "Security",
    "DATA SECURITY": "Security",
    "CYBERSECURITY": "Security",
    "M365 SECURITY": "Security",
    "DEFENDER": "Security",
    "DEFENDER FOR CLOUD": "Security",
    "MICROSOFT DEFENDER": "Security",
    "SENTINEL": "Security",
    "MICROSOFT SENTINEL": "Security",
    "INCIDENT RESPONSE": "Security",
    "THREAT MANAGEMENT": "Security",
    "COMPLIANCE": "Security",
    "MICROSOFT SECURITY UPDATES": "Security",
    "IDENTITY": "Identity",
    "ENTRA": "Identity",
    "ENTRA ID": "Identity",
    "MICROSOFT ENTRA": "Identity",
    "AZURE AD": "Identity",
    "AZURE ACTIVE DIRECTORY": "Identity",
    "IAM": "Identity",
    "ACCESS MANAGEMENT": "Identity",
    "CONDITIONAL ACCESS": "Identity",
    "MFA": "Identity",
    "AUTHENTICATION": "Identity",
    "ZERO TRUST": "Identity",
    "CROSS-TENANT ACCESS": "Identity",
    "ENTRA PRIVATE ACCESS": "Identity",
    "MANAGEMENT": "Management",
    "AUTOMATION": "Management",
    "INTUNE": "Management",
    "MDM": "Management",
    "ENDPOINT MANAGEMENT": "Management",
    "CONFIGURATION MANAGER": "Management",
    "GOVERNANCE": "Management",
    "POLICY": "Management",
    "MONITORING": "Management",
    "DEVELOPMENT": "Development",
    "DEVOPS": "Development",
    "CI/CD": "Development",
    "GITHUB": "Development",
    "DEVELOPER": "Development",
    "PROGRAMMING": "Development",
    "CODE": "Development",
    "SOFTWARE": "Development",
    "COLLABORATION": "Collaboration",
    "MICROSOFT 365": "Collaboration",
    "M365": "Collaboration",
    "TEAMS": "Collaboration",
    "MICROSOFT TEAMS": "Collaboration",
    "SHAREPOINT": "Collaboration",
    "EXCHANGE": "Collaboration",
    "OUTLOOK": "Collaboration",
    "OFFICE 365": "Collaboration",
    "OFFICE": "Collaboration",
    "DATA": "Data",
    "ANALYTICS": "Data",
    "BI": "Data",
    "BUSINESS INTELLIGENCE": "Data",
    "POWER BI": "Data",
    "SQL": "Data",
    "DATABASE": "Data",
    "KUSTO": "Data",
    "KQL": "Data",
    "LEARNING": "Learning",
    "TRAINING": "Learning",
    "CERTIFICATION": "Learning",
    "COURSE": "Learning",
    "EDUCATION": "Learning",
    "COMMUNITY": "Community",
    "MVP": "Community",
    "USER GROUP": "Community",
    "CONFERENCE": "Community",
    "EVENT": "Community",
    "COMPANY CULTURE": "Community",
    "UPDATES": "Updates",
    "NEWS": "Updates",
    "ANNOUNCEMENTS": "Updates",
    "RELEASE NOTES": "Updates",
    "AMA": "Updates",
}

_KEYWORD_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"SECURITY|DEFENDER|SENTINEL|THREAT|ATTACK|BREACH", re.I), "Security"),
    (re.compile(r"AZURE|CLOUD|AWS|GCP", re.I), "Cloud"),
    (re.compile(r"ENTRA|IDENTITY|AUTH|AAD|\bAD\b", re.I), "Identity"),
    (re.compile(r"AI|COPILOT|ML|LLM|ARTIFICIAL|MACHINE.LEARNING", re.I), "Artificial Intelligence"),
    (re.compile(r"TEAMS|SHAREPOINT|EXCHANGE|OUTLOOK|365|M365", re.I), "Collaboration"),
    (re.compile(r"INTUNE|MANAGEMENT|GOVERNANCE|POLICY|ENDPOINT", re.I), "Management"),
    (re.compile(r"DEVOPS|CI|CD|GITHUB|DEV|CODE", re.I), "Development"),
    (re.compile(r"DATA|ANALYTICS|BI|SQL|DATABASE", re.I), "Data"),
    (re.compile(r"TRAINING|LEARNING|EDUCATION|COURSE|CERT", re.I), "Learning"),
    (re.compile(r"UPDATE|NEWS|ANNOUNCEMENT|RELEASE|AMA", re.I), "Updates"),
]


def normalize_category(raw: str) -> str:
    if not raw or not raw.strip():
        return "Uncategorized"
    trimmed = raw.strip()
    upper = trimmed.upper()
    if upper in CATEGORY_MAP:
        return CATEGORY_MAP[upper]
    # Partial match
    for key, val in CATEGORY_MAP.items():
        if key in upper or upper in key:
            return val
    # Keyword match
    for pattern, category in _KEYWORD_PATTERNS:
        if pattern.search(upper):
            return category
    return trimmed


# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------


def detect_platform(content: str, blog_url: str) -> str:
    if "mvp.microsoft.com/" in blog_url:
        return "MVP-Profile"
    if re.search(r"wordpress\.com|jetpack|blog_id.*26086|data-blog", content):
        return "WordPress.com"
    if re.search(r"ghost|by-line\.|post-card-image|gh-card-wrapper", content):
        return "Ghost"
    if re.search(r"sqs|squarespace-|data-edit-lock", content):
        return "Squarespace"
    if "archive__item" in content:
        return "Jekyll"
    if re.search(r'class="listing-item".*?class="title"', content, re.S):
        return "DisplayPostsListing"
    if re.search(r"wix-essential-viewer-model|communities-blog-ooi", content):
        return "Wix"
    if re.search(r"wp-content|wp-admin|amphibious", content):
        return "WordPress"
    if re.search(r'class="[^"]*compact-card', content):
        return "Hugo"
    if "wpgb-card" in content:
        return "WP-GridBuilder"
    return "Unknown"


# ---------------------------------------------------------------------------
# RSS helpers
# ---------------------------------------------------------------------------


def discover_rss_feed(content: str, blog_url: str) -> list[str]:
    urls: list[str] = []
    for pat in [
        r'<link\s+rel="alternate"\s+type="application/rss\+xml"[^>]*href="([^"]+)"',
        r'<link[^>]*type="application/rss\+xml"[^>]*href="([^"]+)"',
        r'<link\s+rel="alternate"\s+type="application/atom\+xml"[^>]*href="([^"]+)"',
    ]:
        m = re.search(pat, content)
        if m:
            url = m.group(1)
            if not url.startswith("http"):
                url = urljoin(blog_url + "/", url)
            urls.append(url)
    return list(dict.fromkeys(urls))


def _parse_date_safe(text: str) -> Optional[datetime]:
    for fmt in (
        "%Y-%m-%d",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S%z",
        "%a, %d %b %Y %H:%M:%S %Z",
        "%a, %d %b %Y %H:%M:%S %z",
        "%d %b %Y",
        "%B %d, %Y",
        "%m/%d/%Y",
    ):
        try:
            return datetime.strptime(text.strip(), fmt).replace(tzinfo=None)
        except ValueError:
            continue
    # Last resort
    try:
        # Handle timezone offset like +0000
        cleaned = re.sub(r"\s*[+-]\d{4}$", "", text.strip())
        for fmt in ("%a, %d %b %Y %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
            try:
                return datetime.strptime(cleaned, fmt)
            except ValueError:
                continue
    except Exception:
        pass
    return None


def _in_range(dt: datetime, start: datetime, end: datetime) -> bool:
    return start <= dt <= end


def _make_post(date: datetime, title: str, url: str, category: str = "Uncategorized") -> dict:
    return {
        "date": date.strftime("%Y-%m-%d"),
        "title": unescape(re.sub(r"<[^>]+>", "", title)).strip(),
        "url": url.strip(),
        "category": normalize_category(category),
    }


async def _fetch(client: httpx.AsyncClient, url: str, timeout: float = 15.0) -> Optional[str]:
    try:
        resp = await client.get(url, follow_redirects=True, timeout=timeout)
        resp.raise_for_status()
        return resp.text
    except Exception:
        return None


# ---------------------------------------------------------------------------
# RSS generic extraction
# ---------------------------------------------------------------------------


async def extract_rss_posts(
    client: httpx.AsyncClient, feed_url: str, start: datetime, end: datetime
) -> list[dict]:
    content = await _fetch(client, feed_url)
    if not content:
        return []
    return _parse_rss_xml(content, start, end)


def _parse_rss_xml(content: str, start: datetime, end: datetime) -> list[dict]:
    posts: list[dict] = []
    try:
        root = ET.fromstring(content)
    except ET.ParseError:
        return posts

    # Handle RSS 2.0
    ns = {"atom": "http://www.w3.org/2005/Atom", "dc": "http://purl.org/dc/elements/1.1/"}
    items = root.findall(".//item")
    if not items:
        # Try Atom
        items = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    for item in items:
        try:
            title_el = item.find("title")
            if title_el is None:
                title_el = item.find("{http://www.w3.org/2005/Atom}title")
            title = (title_el.text or "") if title_el is not None else ""

            link_el = item.find("link")
            if link_el is None:
                link_el = item.find("{http://www.w3.org/2005/Atom}link")
            if link_el is not None:
                url = link_el.text or link_el.get("href", "")
            else:
                url = ""

            pub_el = item.find("pubDate")
            if pub_el is None:
                pub_el = item.find("{http://www.w3.org/2005/Atom}published")
            if pub_el is None:
                pub_el = item.find("{http://www.w3.org/2005/Atom}updated")
            date_text = (pub_el.text or "") if pub_el is not None else ""

            dt = _parse_date_safe(date_text.strip()) if date_text else None
            if not dt or not _in_range(dt, start, end):
                continue

            cat_el = item.find("category")
            if cat_el is None:
                cat_el = item.find("{http://purl.org/dc/elements/1.1/}subject")
            category = (cat_el.text or "Uncategorized") if cat_el is not None else "Uncategorized"

            posts.append(_make_post(dt, title, url, category))
        except Exception:
            continue
    return posts


# ---------------------------------------------------------------------------
# Hugo
# ---------------------------------------------------------------------------

_MONTH_MAP = {
    "january": 1, "february": 2, "march": 3, "april": 4,
    "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12,
}


def extract_hugo_posts(
    content: str, blog_url: str, start: datetime, end: datetime, *, menu_mode: bool = False
) -> list[dict]:
    posts: list[dict] = []

    if menu_mode:
        pattern = r'<article class="post-card"[^>]*>.*?<h3><a href="([^"]+)">([^<]+)</a></h3><time>(\d{1,2}/\d{1,2}/\d{4})</time>'
    else:
        # Try onclick pattern first
        pattern = r'<article[^>]*class="[^"]*compact-card[^"]*"[^>]*>.*?onclick="[^"]*([^\'"]+)[\'"].*?<h3[^>]*>([^<]+)</h3>.*?<span>(\d{1,2}/\d{1,2}/\d{4})</span>'

    matches = re.finditer(pattern, content, re.S)
    found_any = False
    for m in matches:
        found_any = True
        path, title, date_str = m.group(1), m.group(2), m.group(3)
        parts = date_str.split("/")
        if len(parts) == 3:
            try:
                dt = datetime(int(parts[2]), int(parts[1]), int(parts[0]))
            except ValueError:
                continue
            if _in_range(dt, start, end):
                full_url = _resolve_url(blog_url, path)
                posts.append(_make_post(dt, title, full_url))

    if not found_any and not menu_mode:
        # Simpler pattern
        pattern2 = r'<article[^>]*class="[^"]*compact-card[^"]*"[^>]*>.*?href="([^"]+)"[^>]*>.*?<h3[^>]*>([^<]+)</h3>.*?(\d{1,2}/\d{1,2}/\d{4})'
        for m in re.finditer(pattern2, content, re.S):
            path, title, date_str = m.group(1), m.group(2), m.group(3)
            parts = date_str.split("/")
            if len(parts) == 3:
                try:
                    dt = datetime(int(parts[2]), int(parts[1]), int(parts[0]))
                except ValueError:
                    continue
                if _in_range(dt, start, end):
                    full_url = _resolve_url(blog_url, path)
                    posts.append(_make_post(dt, title, full_url))

    return posts


def _resolve_url(blog_url: str, path: str) -> str:
    if path.startswith("http"):
        return path
    if path.startswith("/"):
        return f"{blog_url}{path}"
    return f"{blog_url}/{path}"


# ---------------------------------------------------------------------------
# WordPress (HTML)
# ---------------------------------------------------------------------------


def extract_wordpress_posts(
    content: str, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    posts: list[dict] = []
    pattern = r'<article[^>]*id="post-(\d+)"[^>]*>.*?<h\d[^>]*><a[^>]*href="([^"]+)"[^>]*>([^<]+)</a></h\d>'
    for m in re.finditer(pattern, content, re.S):
        url, title = m.group(2), m.group(3)
        ctx_start = max(0, m.start() - 300)
        ctx_end = min(len(content), m.end() + 800)
        ctx = content[ctx_start:ctx_end]

        dt = _extract_date_from_context(ctx)
        if dt and _in_range(dt, start, end):
            posts.append(_make_post(dt, title, url))

    return posts


def _extract_date_from_context(ctx: str) -> Optional[datetime]:
    # ISO in <time>
    m = re.search(r'<time[^>]*datetime="(\d{4})-(\d{2})-(\d{2})"', ctx)
    if m:
        try:
            return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    # Word format
    m = re.search(
        r"(January|February|March|April|May|June|July|August|September|October|November|December)"
        r"\s+(\d{1,2}),?\s+(\d{4})",
        ctx,
    )
    if m:
        month = _MONTH_MAP.get(m.group(1).lower())
        if month:
            try:
                return datetime(int(m.group(3)), month, int(m.group(2)))
            except ValueError:
                pass

    # YYYY-MM-DD
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", ctx)
    if m:
        try:
            return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    return None


# ---------------------------------------------------------------------------
# WordPress RSS
# ---------------------------------------------------------------------------


async def extract_wordpress_rss_posts(
    client: httpx.AsyncClient,
    content: str,
    blog_url: str,
    start: datetime,
    end: datetime,
) -> list[dict]:
    feed_urls = discover_rss_feed(content, blog_url)
    candidates = list(feed_urls) + [
        f"{blog_url}/feed/",
        f"{blog_url}/feed",
        f"{blog_url}/rss/",
        f"{blog_url}/?feed=rss2",
    ]
    seen = set()
    for url in candidates:
        if url in seen:
            continue
        seen.add(url)
        feed_content = await _fetch(client, url)
        if feed_content:
            posts = _parse_rss_xml(feed_content, start, end)
            if posts:
                return posts
    return []


# ---------------------------------------------------------------------------
# WordPress.com REST API
# ---------------------------------------------------------------------------


async def extract_wordpress_com_posts(
    client: httpx.AsyncClient, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    from urllib.parse import urlparse

    domain = urlparse(blog_url).netloc
    api_url = f"https://public-api.wordpress.com/rest/v1.1/sites/{domain}/posts?number=100&status=publish"

    posts: list[dict] = []
    try:
        resp = await client.get(api_url, timeout=15.0)
        if resp.status_code == 200:
            data = resp.json()
            for post in data.get("posts", []):
                title = re.sub(r"<[^>]+>", "", post.get("title", ""))
                url = post.get("URL", "")
                date_str = post.get("date", "")
                dt = _parse_date_safe(date_str)
                if not dt or not _in_range(dt, start, end):
                    continue

                category = "Uncategorized"
                cats = post.get("categories", {})
                if cats:
                    first_key = next(iter(cats))
                    category = cats[first_key].get("name", "Uncategorized")
                elif post.get("tags"):
                    tags = post["tags"]
                    first_key = next(iter(tags))
                    category = tags[first_key].get("name", "Uncategorized")

                posts.append(_make_post(dt, title, url, category))
    except Exception as e:
        logger.warning("WordPress.com API failed: %s — falling back to RSS", e)
        # Fallback to RSS
        for feed in [f"{blog_url}/feed/"]:
            rss_posts = await extract_rss_posts(client, feed, start, end)
            if rss_posts:
                return rss_posts

    return posts


# ---------------------------------------------------------------------------
# Jekyll
# ---------------------------------------------------------------------------


async def extract_jekyll_posts(
    client: httpx.AsyncClient,
    content: str,
    blog_url: str,
    start: datetime,
    end: datetime,
) -> list[dict]:
    posts: list[dict] = []
    pattern = r'<div class="archive__item"[^>]*>.*?<h2[^>]*class="archive__item-title[^"]*"[^>]*>([^<]+)</h2>.*?<a[^>]*href="([^"]+)"[^>]*class="btn'
    for m in re.finditer(pattern, content, re.S):
        title, path = m.group(1), m.group(2)
        url = path if path.startswith("http") else f"{blog_url}{path}"

        post_content = await _fetch(client, url)
        if post_content:
            dm = re.search(r'<time[^>]*datetime="(\d{4}-\d{2}-\d{2})[^"]*"', post_content)
            if dm:
                dt = _parse_date_safe(dm.group(1))
                if dt and _in_range(dt, start, end):
                    posts.append(_make_post(dt, title, url))
    return posts


# ---------------------------------------------------------------------------
# Wix
# ---------------------------------------------------------------------------


async def extract_wix_posts(
    client: httpx.AsyncClient, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    feed_candidates = [
        f"{blog_url}/blog-feed.xml",
        f"{blog_url}/blog/feed",
        f"{blog_url}/feed.xml",
        f"{blog_url}/feed",
    ]
    for feed_url in feed_candidates:
        content = await _fetch(client, feed_url)
        if content:
            # Wix uses CDATA in RSS
            posts = _parse_rss_xml(content, start, end)
            if posts:
                return posts
            # Try CDATA pattern manually
            posts = _parse_wix_rss_cdata(content, start, end)
            if posts:
                return posts
    return []


def _parse_wix_rss_cdata(content: str, start: datetime, end: datetime) -> list[dict]:
    posts: list[dict] = []
    pattern = r"<item>.*?<title><!\[CDATA\[(.*?)\]\]></title>.*?<link>(.*?)</link>.*?<pubDate>(.*?)</pubDate>"
    for m in re.finditer(pattern, content, re.S):
        title, url, date_str = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
        dt = _parse_date_safe(date_str)
        if dt and _in_range(dt, start, end):
            posts.append(_make_post(dt, title, url))
    return posts


# ---------------------------------------------------------------------------
# Display Posts Listing (WP plugin)
# ---------------------------------------------------------------------------


def extract_display_posts_listing(
    content: str, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    posts: list[dict] = []
    pattern = r'<li class="listing-item">.*?<a class="title" href="([^"]+)">([^<]+)</a>.*?<span class="date">([^<]+)</span>'
    for m in re.finditer(pattern, content, re.S):
        url, title, date_str = m.group(1), m.group(2), m.group(3)
        # Parse "Month Day, Year" format
        mm = re.search(
            r"(January|February|March|April|May|June|July|August|September|October|November|December)"
            r"\s+(\d{1,2}),\s+(\d{4})",
            date_str,
        )
        if mm:
            month = _MONTH_MAP.get(mm.group(1).lower())
            if month:
                try:
                    dt = datetime(int(mm.group(3)), month, int(mm.group(2)))
                except ValueError:
                    continue
                if _in_range(dt, start, end):
                    posts.append(_make_post(dt, title, url))
    return posts


# ---------------------------------------------------------------------------
# Ghost
# ---------------------------------------------------------------------------


async def extract_ghost_posts(
    client: httpx.AsyncClient, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    feed_candidates = [
        f"{blog_url}/rss/",
        f"{blog_url}/rss",
        f"{blog_url}/feed.xml",
        f"{blog_url}/feed/",
    ]
    for feed_url in feed_candidates:
        content = await _fetch(client, feed_url)
        if content:
            posts = _parse_rss_xml(content, start, end)
            if posts:
                return posts
    return []


# ---------------------------------------------------------------------------
# Squarespace
# ---------------------------------------------------------------------------


async def extract_squarespace_posts(
    client: httpx.AsyncClient, blog_url: str, start: datetime, end: datetime
) -> list[dict]:
    feed_candidates = [
        f"{blog_url}/blog?format=rss",
        f"{blog_url}/blog/feed",
        f"{blog_url}/feed.xml",
        f"{blog_url}/?format=rss",
    ]
    for feed_url in feed_candidates:
        content = await _fetch(client, feed_url)
        if content:
            posts = _parse_rss_xml(content, start, end)
            if posts:
                return posts
    return []


# ---------------------------------------------------------------------------
# Vanilla HTML (generic)
# ---------------------------------------------------------------------------


async def extract_vanilla_html_posts(
    client: httpx.AsyncClient,
    content: str,
    blog_url: str,
    start: datetime,
    end: datetime,
) -> list[dict]:
    posts: list[dict] = []
    skip_titles = {
        "home", "about", "contact", "posts", "articles", "blog", "services",
        "subscribe", "newsletter", "categories", "tags", "archive", "search",
        "all", "more",
    }

    # Try specific link patterns
    pattern = r'<a[^>]*href="(/[^/"]+)"[^>]*>([^<]{10,150})</a>'
    for m in re.finditer(pattern, content, re.I):
        href, title = m.group(1), m.group(2).strip()
        if title.lower() in skip_titles or len(title) < 5 or href == "/":
            continue

        post_url = f"{blog_url}{href}"
        post_content = await _fetch(client, post_url)
        if not post_content:
            continue

        dt = _extract_date_from_post_page(post_content)
        if dt and _in_range(dt, start, end):
            existing = {p["url"] for p in posts}
            if post_url not in existing:
                posts.append(_make_post(dt, title, post_url))

    return posts


def _extract_date_from_post_page(content: str) -> Optional[datetime]:
    # <time datetime="2024-12-05">
    m = re.search(r'<time[^>]*datetime="(\d{4}-\d{2}-\d{2})', content)
    if m:
        return _parse_date_safe(m.group(1))

    # <meta property="article:published_time" content="2024-12-05">
    m = re.search(r'<meta[^>]*property="article:published_time"[^>]*content="(\d{4}-\d{2}-\d{2})', content)
    if m:
        return _parse_date_safe(m.group(1))

    # JSON-LD datePublished
    m = re.search(r'"datePublished"\s*:\s*"(\d{4}-\d{2}-\d{2})', content)
    if m:
        return _parse_date_safe(m.group(1))

    # "Month Day, Year"
    m = re.search(
        r"(January|February|March|April|May|June|July|August|September|October|November|December)"
        r"\s+(\d{1,2}),?\s+(\d{4})",
        content,
    )
    if m:
        month = _MONTH_MAP.get(m.group(1).lower())
        if month:
            try:
                return datetime(int(m.group(3)), month, int(m.group(2)))
            except ValueError:
                pass

    return None
