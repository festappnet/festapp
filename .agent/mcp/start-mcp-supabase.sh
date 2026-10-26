#!/bin/bash

# Navigate to the project root
cd "$(dirname "$0")/../.."

# Load environment variables from .env.local if it exists
if [ -f .env.local ]; then
  set -o allexport
  source .env.local
  set +o allexport
fi

# Check for SUPABASE_ACCESS_TOKEN
if [ -z "$SUPABASE_ACCESS_TOKEN" ]; then
  echo "Error: SUPABASE_ACCESS_TOKEN is not set in .env.local"
  echo "Please generate one at: https://supabase.com/dashboard/account/tokens"
  echo "And add it to your .env.local file: SUPABASE_ACCESS_TOKEN=sbBp_..."
  exit 1
fi

# Execute the Supabase MCP server
exec npx -y @supabase/mcp-server-supabase
