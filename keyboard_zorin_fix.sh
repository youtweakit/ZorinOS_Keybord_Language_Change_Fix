#!/bin/bash
set -euo pipefail

echo "[1/7] Проверка утилит..."
for bin in dconf gsettings dbus-run-session; do
  command -v "$bin" >/dev/null || { echo "Нужна утилита: $bin"; exit 1; }
done

echo "[2/7] Готовим dconf-профиль и системные дефолты..."
sudo mkdir -p /etc/dconf/db/local.d /etc/dconf/profile

# Профиль, чтобы читать system-db:local
if [ ! -f /etc/dconf/profile/user ]; then
  echo -e "user-db:user\nsystem-db:local" | sudo tee /etc/dconf/profile/user >/dev/null
fi

# Системные дефолты — через cat <<'EOF' (одинарные кавычки, чтобы bash не трогал содержимое)
sudo bash -c "cat <<'EOF' > /etc/dconf/db/local.d/00-input-alt-shift
[org/gnome/desktop/input-sources]
sources=[('xkb','us'),('xkb','ru')]
xkb-options=@as []

[org/gnome/desktop/wm/keybindings]
switch-input-source=['<Alt>Shift_L','<Alt>Shift_R']
switch-input-source-backward=['<Shift>Alt_L','<Shift>Alt_R']
EOF"

echo "[3/7] Компилируем системные дефолты dconf..."
sudo dconf update

echo "[4/7] Чистим /etc/default/keyboard от старых XKB-тогглов..."
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

echo "[5/7] Применяем для ТЕКУЩЕГО пользователя..."
dconf write /org/gnome/desktop/input-sources/xkb-options "@as []"
dconf write /org/gnome/desktop/input-sources/sources "[('xkb','us'),('xkb','ru')]"
dconf write /org/gnome/desktop/wm/keybindings/switch-input-source "['<Alt>Shift_L','<Alt>Shift_R']"
dconf write /org/gnome/desktop/wm/keybindings/switch-input-source-backward "['<Shift>Alt_L','<Shift>Alt_R']"

echo "[6/7] Прокатываем по всем существующим пользователям..."
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

echo "[7/7] Готово."
echo "Перелогиньтесь в GNOME (выйти/войти), чтобы горячие клавиши подхватились."
