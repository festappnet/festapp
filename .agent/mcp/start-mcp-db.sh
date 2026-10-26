#!/bin/bash

# Navigate to the project root
cd "$(dirname "$0")/../.."

# Load environment variables from .env.local if it exists
if [ -f .env.local ]; then
  set -o allexport
  source .env.local
  set +o allexport
fi

# Run the Postgres MCP server
# We use the DATABASE_URL from .env.local
if [ -z "$DATABASE_URL" ]; then
  echo "Error: DATABASE_URL is not set in .env.local"
  exit 1
fi

# Execute the MCP server using npx
exec npx -y @modelcontextprotocol/server-postgres "$DATABASE_URL"
