#!/bin/bash

# Navigate to the project root
cd "$(dirname "$0")/../.."

# Load environment variables from .env.local if it exists
if [ -f .env.local ]; then
  set -o allexport
  source .env.local
  set +o allexport
fi

# Execute the Puppeteer MCP server
# This server allows MCP clients to control a headless Chrome instance
exec npx -y @modelcontextprotocol/server-puppeteer
