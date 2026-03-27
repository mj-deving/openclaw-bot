#!/usr/bin/env bash
# Atlas Architecture Installer
# Creates the full agent operating system in your OpenClaw workspace.
# Never overwrites existing files — safe to run multiple times.

set -uo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../assets"

created=0
skipped=0

install_file() {
  local target="$WORKSPACE/$1"
  local source="$ASSETS_DIR/$1"
  
  if [ -f "$target" ]; then
    echo "  SKIP  $1 (already exists)"
    skipped=$((skipped + 1))
  else
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    echo "  CREATE $1"
    created=$((created + 1))
  fi
}

echo ""
echo "  Atlas Architecture Installer"
echo "  Workspace: $WORKSPACE"
echo ""

# Install all template files
install_file "SOUL.md"
install_file "AGENTS.md"
install_file "USER.md"
install_file "IDENTITY.md"
install_file "MEMORY.md"
install_file "SECURITY.md"
install_file "HEARTBEAT.md"
install_file "TOOLS.md"

# Create memory directory and first daily log
mkdir -p "$WORKSPACE/memory"
TODAY=$(date +%Y-%m-%d)
if [ ! -f "$WORKSPACE/memory/$TODAY.md" ]; then
  cat > "$WORKSPACE/memory/$TODAY.md" << EOF
# Daily Log — $TODAY

## Session Notes


## Next Actions
- [ ] Customize USER.md with your details
- [ ] Customize IDENTITY.md with your agent's name
- [ ] Review SECURITY.md trust boundaries
- [ ] Run a Claw Score audit
EOF
  echo "  CREATE memory/$TODAY.md"
  created=$((created + 1))
else
  echo "  SKIP  memory/$TODAY.md (already exists)"
  skipped=$((skipped + 1))
fi

echo ""
echo "  Done: $created created, $skipped skipped"
echo ""
echo "  Next steps:"
echo "  1. Edit USER.md — tell your agent who you are"
echo "  2. Edit IDENTITY.md — give your agent a name"
echo "  3. Review SECURITY.md — set your trust boundaries"
echo "  4. Ask your agent to run a Claw Score audit"
echo ""
