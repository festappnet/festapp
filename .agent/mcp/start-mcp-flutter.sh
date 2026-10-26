#!/bin/bash

# Navigate to the project root
cd "$(dirname "$0")/../.."

# Check for fvm
if ! command -v fvm &> /dev/null; then
  echo "Error: fvm is not installed or not in PATH." >&2
  exit 1
fi

# Activate the server (quietly, to stderr, to avoid breaking MCP handshake)
# We use the official dart-lang/ai MCP server
echo "Ensuring matching dart_mcp_server is active..." >&2
fvm dart pub global activate -s git https://github.com/dart-lang/ai.git --git-path pkgs/dart_mcp_server/ >&2

# Execute the MCP server
# We use 'exec' to replace the shell process
exec fvm dart pub global run dart_mcp_server
