#!/bin/bash

set -e

echo "======================================"
echo " Beer Wall TV Installer v1.02"
echo " Orange Pi + Armbian"
echo " Firefox ESR Kiosk"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom przez sudo"
    exit 1
fi

# -----------------------------------------------------
# Użytkownik & Autologowanie (Istniejące konto: lamus)
# -----------------------------------------------------
USER_NAME="lamus"

if ! id "$USER_NAME" &>/dev/null; then
    echo "BŁĄD: Użytkownik $USER_NAME nie istnieje w systemie!"
    exit 1
fi

echo "== Konfiguracja istniejącego konta: $USER_NAME =="

# Uprawnienia sudo bez pytania o hasło
echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/99-${USER_NAME}-nopasswd"
chmod 0440 "/etc/sudoers.d/99-${USER_NAME}-nopasswd"

USER_HOME=$(eval echo ~$USER_NAME)
echo "Katalog domowy: $USER_HOME"

# Autologowanie w getty / console (tty1)
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat >/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
Type=idle
EOF

# -----------------------------------------------------
# Pakiety systemowe
# -----------------------------------------------------
apt update

apt install -y \
apache2 \
libapache2-mod-fcgid \
php \
php-fpm \
php-cli \
php-mbstring \
php-curl \
php-xml \
php-zip \
firefox-esr \
xserver-xorg \
xinit \
openbox \
lightdm \
unclutter \
xdotool \
x11-xserver-utils \
curl \
tar \
watchdog

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

# -----------------------------------------------------
# Pobieranie Beer Wall TV (lamus1.tar.gz)
# -----------------------------------------------------
echo "== Pobieranie aplikacji =="

rm -rf /var/www/lamus
mkdir -p /var/www/lamus

cd /tmp
curl -fL -o lamus1.tar.gz https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus1.tar.gz
tar -xzf lamus1.tar.gz -C /var/www/lamus

if [ ! -f /var/www/lamus/index.php ]; then
    echo "Brak index.php - przerwanie instalacji"
    exit 1
fi

chown -R www-data:www-data /var/www/lamus
chmod -R 755 /var/www/lamus

# -----------------------------------------------------
# Konfiguracja Apache + PHP-FPM
# -----------------------------------------------------
a2enmod proxy_fcgi setenvif rewrite
a2enconf php${PHP_VERSION}-fpm

cat >/etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /var/www/lamus
    <Directory /var/www/lamus>
        AllowOverride All
        Require all granted
    </Directory>
    DirectoryIndex index.php index.html
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

systemctl enable apache2
systemctl restart apache2
systemctl enable php${PHP_VERSION}-fpm
systemctl restart php${PHP_VERSION}-fpm

# -----------------------------------------------------
# Openbox Autostart
# -----------------------------------------------------
mkdir -p $USER_HOME/.config/openbox

cat >$USER_HOME/.config/openbox/autostart <<EOF
#!/bin/bash
xset s off
xset s noblank
xset -dpms
xhost +local:$USER_NAME &
unclutter -idle 0.5 -root -jitter 2 &
EOF

chmod +x $USER_HOME/.config/openbox/autostart
chown -R $USER_NAME:$USER_NAME $USER_HOME/.config

# -----------------------------------------------------
# X11 - Wygaszanie
# -----------------------------------------------------
mkdir -p /etc/X11/xorg.conf.d

cat >/etc/X11/xorg.conf.d/10-monitor.conf <<EOF
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection

Section "Extensions"
    Option "DPMS" "Disable"
EndSection
EOF

# -----------------------------------------------------
# LightDM Autologin
# -----------------------------------------------------
mkdir -p /etc/lightdm/lightdm.conf.d

cat >/etc/lightdm/lightdm.conf.d/10-autologin.conf <<EOF
[Seat:*]
autologin-user=$USER_NAME
autologin-user-timeout=0
user-session=openbox
xserver-command=X -s 0 -dpms
EOF

systemctl enable lightdm

# -----------------------------------------------------
# Firefox Kiosk Skrypt & Usługa Systemd (POPRAWIONY PROFIL)
# -----------------------------------------------------
cat >/usr/local/bin/firefox-kiosk.sh <<EOF
#!/bin/bash

export DISPLAY=:0
export XAUTHORITY=$USER_HOME/.Xauthority

until xset q > /dev/null 2>&1; do
    sleep 1
done

xset s off
xset s noblank
xset -dpms

PROFILE_DIR="/tmp/ff-kiosk-profile"

while true
do
    # Czyszczenie i przygotowanie profilu przed uruchomieniem
    rm -rf "\$PROFILE_DIR"
    mkdir -p "\$PROFILE_DIR"
    chown -R $USER_NAME:$USER_NAME "\$PROFILE_DIR"

    firefox-esr \
        --kiosk \
        --private-window \
        --profile "\$PROFILE_DIR" \
        http://localhost/

    sleep 3
done
EOF

chmod 755 /usr/local/bin/firefox-kiosk.sh

# -----------------------------------------------------
# Skrypt aktualizacji (poprawiony plik lamus1.tar.gz)
# -----------------------------------------------------
cat >/usr/local/bin/update-beer-wall <<'EOF'
#!/bin/bash
set -e

DATE=$(date +%Y%m%d_%H%M)
mkdir -p /var/www/backup

if [ -d /var/www/lamus ]; then
    cp -a /var/www/lamus /var/www/backup/lamus_$DATE
fi

cd /tmp
curl -fL -o lamus1.tar.gz https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus1.tar.gz

rm -rf /var/www/lamus/*
tar -xzf lamus1.tar.gz -C /var/www/lamus

chown -R www-data:www-data /var/www/lamus
systemctl restart apache2
echo "Aktualizacja pliku lamus1.tar.gz zakończona pomyślnie!"
EOF

chmod +x /usr/local/bin/update-beer-wall

# -----------------------------------------------------
# Watchdog Orange Pi PC (Allwinner H3)
# -----------------------------------------------------
echo "== Watchdog =="

modprobe sunxi_wdt || true

cat >/etc/watchdog.conf <<EOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
interval = 10
priority = 0
EOF

mkdir -p /etc/systemd/system/watchdog.service.d

cat >/etc/systemd/system/watchdog.service.d/override.conf <<EOF
[Service]
Restart=always
RestartSec=5
LimitRTPRIO=infinity
LimitMEMLOCK=infinity
EOF

systemctl daemon-reload
systemctl enable watchdog.service
systemctl restart watchdog.service || echo "UWAGA: Sprzętowy Watchdog zostanie aktywowany przy restarcie."

# -----------------------------------------------------
# Blokada wygaszania / usypiania
# -----------------------------------------------------
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true

echo
echo "======================================"
echo " INSTALACJA ZAKOŃCZONA SUCCESS"
echo " Skonfigurowano autologowanie dla: $USER_NAME"
echo "======================================"
echo "Zrestartuj system: sudo reboot"
