# Blog Export MCP Server

An MCP (Model Context Protocol) server that extracts blog post metadata from **12+ different blog platforms** automatically. This is the MCP server version of the [Export-posts PowerShell script](../readme.md).

**Container image:** `ghcr.io/harrijaakkonen/export-posts/blog-export-mcp:latest`

## Tools

### `export_blog_posts`

Export blog post metadata (date, title, category, URL) from a blog. Automatically detects the platform.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `blog_url` | string | *(required)* | Blog homepage URL |
| `start_date` | string | 5 years ago | Filter from date (YYYY-MM-DD) |
| `end_date` | string | today | Filter until date (YYYY-MM-DD) |

Returns CSV text: `Date;Category;Title;URL` with a summary of total posts and categories.

### `detect_blog_platform`

| Parameter | Type | Description |
|-----------|------|-------------|
| `blog_url` | string | Blog homepage URL to analyze |

Returns the detected platform name and any discovered RSS feeds.

### `list_supported_platforms`

No parameters. Returns a table of all supported platforms with detection methods and capabilities.

## Supported Platforms

Hugo, WordPress (self-hosted + .com), WordPress with RSS, WordPress + Display Posts Listing, WordPress + WP Grid Builder, Jekyll, Wix, Ghost CMS, Squarespace, and vanilla HTML blogs.

## Running Locally (stdio)

Requires **Python 3.12+**.

```bash
cd MCP
pip install -r requirements.txt
python server.py
```

## Running as Container (HTTP)

```bash
# Build locally
docker build -t blog-export-mcp ./MCP

# Run with HTTP transport
docker run -p 8000:8000 blog-export-mcp
```

Or pull from GitHub Container Registry:

```bash
docker run -p 8000:8000 ghcr.io/harrijaakkonen/export-posts/blog-export-mcp:latest
```

The container defaults to HTTP transport on port 8000. Override the port with `MCP_PORT`:

```bash
docker run -p 9000:9000 -e MCP_PORT=9000 ghcr.io/harrijaakkonen/export-posts/blog-export-mcp:latest
```

For stdio mode in a container (e.g. VS Code Docker config), unset `MCP_TRANSPORT`:

```bash
docker run -i --rm -e MCP_TRANSPORT= ghcr.io/harrijaakkonen/export-posts/blog-export-mcp:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_TRANSPORT` | *(unset)* | Set to any value to use HTTP transport instead of stdio. Set in container by default. |
| `MCP_PORT` | `8000` | HTTP port when running in HTTP transport mode |

You can also pass `--http` as a CLI argument to `server.py` to enable HTTP transport without setting `MCP_TRANSPORT`.

## VS Code / Copilot Configuration

### Stdio (local)

Add to your `.vscode/mcp.json`:

```json
{
  "servers": {
    "blog-export": {
      "command": "python",
      "args": ["${workspaceFolder}/MCP/server.py"]
    }
  }
}
```

### Docker (container)

```json
{
  "servers": {
    "blog-export": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "ghcr.io/harrijaakkonen/export-posts/blog-export-mcp:latest"
      ]
    }
  }
}
```

### HTTP (remote/hosted)

```json
{
  "servers": {
    "blog-export": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

## Example Usage

Once configured, ask your AI assistant:

> "Export all blog posts from https://example-blog.com from the last year"

> "What blogging platform does https://example-blog.com use?"
