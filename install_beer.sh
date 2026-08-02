#!/bin/bash

set -e

echo "======================================"
echo " Beer Wall TV Installer v0.95"
echo " Orange Pi + Armbian"
echo " Firefox ESR Kiosk"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom przez sudo."
    exit 1
fi


# =====================================================
# Wykrycie użytkownika
# =====================================================

if [ -n "$SUDO_USER" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$USER"
fi


if ! id "$USER_NAME" >/dev/null 2>&1; then
    echo "Brak użytkownika $USER_NAME"
    exit 1
fi


USER_HOME=$(eval echo ~$USER_NAME)


echo "Użytkownik: $USER_NAME"
echo "HOME: $USER_HOME"



# =====================================================
# Pakiety
# =====================================================

echo "== Pakiety =="

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
x11-xserver-utils \
curl \
wget \
tar \
watchdog



PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')



# =====================================================
# WWW
# =====================================================

echo "== Beer Wall TV =="


rm -rf /var/www/lamus

mkdir -p /var/www/lamus


cd /tmp


curl -fL \
-o lamus.tar.gz \
https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus.tar.gz


tar -xzf lamus.tar.gz -C /var/www/lamus


test -f /var/www/lamus/index.php || {
echo "Brak index.php"
exit 1
}


chown -R www-data:www-data /var/www/lamus

chmod -R 755 /var/www/lamus



# =====================================================
# Apache
# =====================================================

echo "== Apache =="


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



# =====================================================
# Loading screen
# =====================================================

cat >/var/www/lamus/loading.html <<EOF

<html>

<head>

<style>

body{
background:#111;
color:white;
display:flex;
height:100vh;
align-items:center;
justify-content:center;
font-family:Arial;
text-align:center;
}

h1{
font-size:70px;
}

</style>

</head>


<body>

<h1>
🍺<br>
Beer Wall TV<br>
Ładowanie...
</h1>

</body>

</html>

EOF



# =====================================================
# Openbox
# =====================================================

echo "== Openbox =="


mkdir -p $USER_HOME/.config/openbox


cat >$USER_HOME/.config/openbox/autostart <<EOF

#!/bin/bash


# blokada wygaszania

xset s off

xset s noblank

xset -dpms



# ukrycie kursora

unclutter -idle 0.5 -root -jitter 2 &

EOF


chmod +x $USER_HOME/.config/openbox/autostart

chown -R $USER_NAME:$USER_NAME $USER_HOME/.config



# =====================================================
# X11 blokada ekranu
# =====================================================

echo "== X11 display =="


mkdir -p /etc/X11/xorg.conf.d


cat >/etc/X11/xorg.conf.d/10-monitor.conf <<EOF

Section "Monitor"

Identifier "HDMI"

Option "DPMS" "false"

EndSection


Section "ServerFlags"

Option "BlankTime" "0"

Option "StandbyTime" "0"

Option "SuspendTime" "0"

Option "OffTime" "0"

EndSection

EOF



# =====================================================
# LightDM
# =====================================================

echo "== LightDM =="


mkdir -p /etc/lightdm/lightdm.conf.d


cat >/etc/lightdm/lightdm.conf.d/10-autologin.conf <<EOF

[Seat:*]

autologin-user=$USER_NAME

autologin-user-timeout=0

user-session=openbox

EOF



cat >/etc/lightdm/lightdm.conf.d/20-display.conf <<EOF

[Seat:*]

xserver-command=X -s 0 -dpms

EOF



systemctl enable lightdm



# =====================================================
# Firefox kiosk service
# =====================================================

echo "== Firefox kiosk =="


cat >/usr/local/bin/firefox-kiosk.sh <<EOF

#!/bin/bash


export DISPLAY=:0


sleep 8


while true

do


firefox-esr \
--kiosk \
--private-window \
http://localhost/loading.html


sleep 5


done

EOF


chmod +x /usr/local/bin/firefox-kiosk.sh



cat >/etc/systemd/system/firefox-kiosk.service <<EOF

[Unit]

Description=Beer Wall Firefox Kiosk

After=graphical.target


[Service]

User=$USER_NAME

Environment=DISPLAY=:0

ExecStart=/usr/local/bin/firefox-kiosk.sh

Restart=always

RestartSec=5


[Install]

WantedBy=graphical.target

EOF



systemctl daemon-reload

systemctl enable firefox-kiosk.service



# =====================================================
# Update Beer Wall
# =====================================================

echo "== Update =="


cat >/usr/local/bin/update-beer-wall <<'EOF'

#!/bin/bash

DATE=$(date +%Y%m%d_%H%M)

mkdir -p /var/www/backup

cp -a /var/www/lamus /var/www/backup/lamus_$DATE


cd /tmp

curl -fL \
-o lamus.tar.gz \
https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus.tar.gz


rm -rf /var/www/lamus/*


tar -xzf lamus.tar.gz -C /var/www/lamus


chown -R www-data:www-data /var/www/lamus


systemctl restart apache2

EOF


chmod +x /usr/local/bin/update-beer-wall



# =====================================================
# Watchdog
# =====================================================

echo "== Watchdog =="


cat >/etc/watchdog.conf <<EOF
watchdog-device = /dev/watchdog
watchdog-timeout = 15
interval = 10
priority = 0
EOF

systemctl daemon-reload
systemctl enable watchdog

systemctl restart watchdog



# =====================================================
# Boot
# =====================================================

echo "== Boot =="


if [ -f /boot/armbianEnv.txt ]; then

grep -q "consoleblank=0" /boot/armbianEnv.txt || \
echo "extraargs=quiet loglevel=0 consoleblank=0" >> /boot/armbianEnv.txt

fi



# =====================================================
# Sleep OFF
# =====================================================

systemctl mask sleep.target || true
systemctl mask suspend.target || true
systemctl mask hibernate.target || true
systemctl mask hybrid-sleep.target || true



echo
echo "======================================"
echo " INSTALACJA ZAKOŃCZONA"
echo "======================================"

echo
echo "Użytkownik: $USER_NAME"
echo
echo "WWW:"
echo "http://localhost"
echo
echo "Aktualizacja:"
echo "sudo update-beer-wall"
echo
echo "Restart:"
echo "sudo reboot"
