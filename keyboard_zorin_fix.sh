#!/bin/bash
set -euo pipefail

echo "[1/7] Checking utilities..."
for bin in dconf gsettings dbus-run-session; do
  command -v "$bin" >/dev/null || { echo "Required utility: $bin"; exit 1; }
done

echo "[2/7] Preparing dconf profile and system defaults..."
sudo mkdir -p /etc/dconf/db/local.d /etc/dconf/profile

# Profile to read system-db:local
if [ ! -f /etc/dconf/profile/user ]; then
  echo -e "user-db:user\nsystem-db:local" | sudo tee /etc/dconf/profile/user >/dev/null
fi

# System defaults - using cat <<'EOF' (single quotes to prevent bash from interpreting contents)
sudo bash -c "cat <<'EOF' > /etc/dconf/db/local.d/00-input-alt-shift
[org/gnome/desktop/input-sources]
sources=[('xkb','us'),('xkb','ru')]
xkb-options=@as []

[org/gnome/desktop/wm/keybindings]
switch-input-source=['<Alt>Shift_L','<Alt>Shift_R']
switch-input-source-backward=['<Shift>Alt_L','<Shift>Alt_R']
EOF"

echo "[3/7] Compiling dconf system defaults..."
sudo dconf update

echo "[4/7] Cleaning /etc/default/keyboard from old XKB toggles..."
if [ -f /etc/default/keyboard ]; then
  sudo sed -i 's/^XKBOPTIONS=.*/XKBOPTIONS=""/' /etc/default/keyboard || true
else
  echo 'XKBMODEL="pc105"
XKBLAYOUT="us,ru"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"' | sudo tee /etc/default/keyboard >/dev/null
fi
sudo dpkg-reconfigure -f noninteractive keyboard-configuration || true
sudo systemctl restart keyboard-setup || true

echo "[5/7] Applying for CURRENT user..."
dconf write /org/gnome/desktop/input-sources/xkb-options "@as []"
dconf write /org/gnome/desktop/input-sources/sources "[('xkb','us'),('xkb','ru')]"
dconf write /org/gnome/desktop/wm/keybindings/switch-input-source "['<Alt>Shift_L','<Alt>Shift_R']"
dconf write /org/gnome/desktop/wm/keybindings/switch-input-source-backward "['<Shift>Alt_L','<Shift>Alt_R']"

echo "[6/7] Applying for all existing users..."
for home in /home/*; do
  [ -d "$home" ] || continue
  user=$(basename "$home")
  id -u "$user" >/dev/null 2>&1 || continue
  echo "  -> $user"
  sudo -u "$user" dbus-run-session -- bash -lc \
    "dconf write /org/gnome/desktop/input-sources/xkb-options '@as []' && \
     dconf write /org/gnome/desktop/input-sources/sources \"[('xkb','us'),('xkb','ru')]\" && \
     dconf write /org/gnome/desktop/wm/keybindings/switch-input-source \"['<Alt>Shift_L','<Alt>Shift_R']\" && \
     dconf write /org/gnome/desktop/wm/keybindings/switch-input-source-backward \"['<Shift>Alt_L','<Shift>Alt_R']\""
done

echo "[7/7] Done."
echo "Please relogin to GNOME (log out and back in) for hotkeys to take effect."
