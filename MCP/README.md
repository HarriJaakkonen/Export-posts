# Blog Export MCP Server

An MCP (Model Context Protocol) server that extracts blog post metadata from **12+ different blog platforms** automatically. This is the MCP server version of the [Export-posts PowerShell script](../readme.md).

## Tools

| Tool | Description |
|------|-------------|
| `export_blog_posts` | Export blog post metadata (date, title, category, URL) from any supported blog |
| `detect_blog_platform` | Detect which blogging platform a URL is using |
| `list_supported_platforms` | List all supported blog platforms |

## Supported Platforms

Hugo, WordPress (self-hosted + .com), WordPress with RSS, WordPress + Display Posts Listing, WordPress + WP Grid Builder, Jekyll, Wix, Ghost CMS, Squarespace, and vanilla HTML blogs.

## Running Locally (stdio)

```bash
cd MCP
pip install -r requirements.txt
python server.py
```

## Running as Container (HTTP)

```bash
# Build
docker build -t blog-export-mcp ./MCP

# Run with HTTP transport
docker run -p 8000:8000 -e MCP_TRANSPORT=1 blog-export-mcp
```

Or pull from GitHub Container Registry:

```bash
docker run -p 8000:8000 -e MCP_TRANSPORT=1 ghcr.io/<your-username>/export-posts/blog-export-mcp:latest
```

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
        "ghcr.io/<your-username>/export-posts/blog-export-mcp:latest"
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

## GitHub Container Registry (Free Tier)

This image is published to `ghcr.io` via GitHub Actions. For **public repositories**, this is completely free:

- **GitHub Container Registry**: Free unlimited storage for public packages
- **GitHub Actions**: 2,000 free minutes/month for public repos
- No credit card required

The workflow at `.github/workflows/docker-publish.yml` automatically builds and pushes the image on every push to `main` that changes files in `MCP/`.

## Example Usage

Once configured, ask your AI assistant:

> "Export all blog posts from https://example-blog.com from the last year"

> "What blogging platform does https://example-blog.com use?"
