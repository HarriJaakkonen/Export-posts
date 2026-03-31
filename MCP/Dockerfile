FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py platforms.py ./

EXPOSE 8000

# Set HTTP transport by default in container
ENV MCP_TRANSPORT=1

# Default: run with streamable-http transport for hosted/container usage
# For stdio: docker run -i --rm -e MCP_TRANSPORT= blog-export-mcp
ENTRYPOINT ["python", "server.py"]
