#!/bin/bash
# Install csr and notification hooks to ~/.local/bin/
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/bin/csr" "$SCRIPT_DIR/bin/notify-attention.sh" "$SCRIPT_DIR/bin/notify-error.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/csr" "$INSTALL_DIR/notify-attention.sh" "$INSTALL_DIR/notify-error.sh"

printf 'Installed to %s:\n' "$INSTALL_DIR"
printf '  csr\n  notify-attention.sh\n  notify-error.sh\n\n'

# Check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  printf 'WARNING: %s is not on your PATH. Add it:\n' "$INSTALL_DIR"
  printf '  export PATH="%s:$PATH"\n\n' "$INSTALL_DIR"
fi

printf 'Add the following to the "hooks" object in ~/.claude/settings.json:\n\n'
cat <<EOF
    "Notification": [{
      "matcher": "permission_prompt",
      "hooks": [{
        "type": "command",
        "command": "bash $INSTALL_DIR/notify-attention.sh",
        "timeout": 5,
        "async": true
      }]
    }],
    "PostToolUseFailure": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "bash $INSTALL_DIR/notify-error.sh",
        "timeout": 5,
        "async": true
      }]
    }]
EOF
