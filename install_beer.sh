#!/bin/bash

set -e

echo "======================================"
echo " Beer Wall TV Installer v0.92"
echo " Orange Pi + Armbian"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom przez sudo."
    exit 1
fi


# -----------------------------------------------------
# Użytkownik
# -----------------------------------------------------

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



# -----------------------------------------------------
# Pakiety
# -----------------------------------------------------

echo "== Instalacja pakietów =="

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



# -----------------------------------------------------
# Beer Wall WWW
# -----------------------------------------------------

echo "== Instalacja strony =="


rm -rf /var/www/lamus

mkdir -p /var/www/lamus


cd /tmp


curl -fL \
-o lamus.tar.gz \
https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus.tar.gz



tar -xzf lamus.tar.gz -C /var/www/lamus


if [ ! -f /var/www/lamus/index.php ]; then

echo "Brak index.php"

exit 1

fi


chown -R www-data:www-data /var/www/lamus

chmod -R 755 /var/www/lamus



# -----------------------------------------------------
# Apache PHP
# -----------------------------------------------------

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




# -----------------------------------------------------
# Ekran startowy
# -----------------------------------------------------

echo "== Loading screen =="


cat >/var/www/lamus/loading.html <<EOF

<!DOCTYPE html>

<html>

<head>

<meta charset="utf-8">

<style>

body{

background:#111;

color:white;

height:100vh;

display:flex;

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




# -----------------------------------------------------
# Openbox
# -----------------------------------------------------

echo "== Openbox =="


mkdir -p $USER_HOME/.config/openbox


cat >$USER_HOME/.config/openbox/autostart <<EOF

#!/bin/bash


xset s off

xset -dpms

xset s noblank


unclutter -idle 0.5 -root -jitter 2 &

EOF


chmod +x $USER_HOME/.config/openbox/autostart

chown -R $USER_NAME:$USER_NAME $USER_HOME/.config




# -----------------------------------------------------
# Firefox systemd kiosk
# -----------------------------------------------------

echo "== Firefox kiosk service =="


mkdir -p /var/log/firefox-kiosk


cat >/usr/local/bin/firefox-kiosk.sh <<EOF

#!/bin/bash


export DISPLAY=:0


sleep 8


while true

do


firefox-esr \
--kiosk \
--private-window \
http://localhost/loading.html >> /var/log/firefox-kiosk/firefox.log 2>&1


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




# -----------------------------------------------------
# Aktualizator
# -----------------------------------------------------

echo "== Update script =="


cat >/usr/local/bin/update-beer-wall <<'EOF'

#!/bin/bash

set -e


DATE=$(date +%Y%m%d_%H%M)


mkdir -p /var/www/backup


cp -a /var/www/lamus \
/var/www/backup/lamus_$DATE


cd /tmp


curl -fL \
-o lamus.tar.gz \
https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus.tar.gz


rm -rf /var/www/lamus/*


tar -xzf lamus.tar.gz \
-C /var/www/lamus


chown -R www-data:www-data /var/www/lamus


systemctl restart apache2


echo "Beer Wall TV updated"

EOF


chmod +x /usr/local/bin/update-beer-wall




# -----------------------------------------------------
# Watchdog
# -----------------------------------------------------

echo "== Watchdog =="


cat >/etc/watchdog.conf <<EOF

watchdog-device = /dev/watchdog

interval = 10

EOF


systemctl enable watchdog

systemctl restart watchdog




# -----------------------------------------------------
# Cichy start
# -----------------------------------------------------

echo "== Boot settings =="


if [ -f /boot/armbianEnv.txt ]; then


grep -q "consoleblank=0" /boot/armbianEnv.txt || \
echo "extraargs=quiet loglevel=0 consoleblank=0" >> /boot/armbianEnv.txt


fi



# -----------------------------------------------------
# LightDM
# -----------------------------------------------------

echo "== Autologin =="


mkdir -p /etc/lightdm/lightdm.conf.d


cat >/etc/lightdm/lightm.conf.d/10-autologin.conf <<EOF

[Seat:*]

autologin-user=$USER_NAME

autologin-user-timeout=0

user-session=openbox

EOF


systemctl enable lightdm



# -----------------------------------------------------
# Blokada sleep
# -----------------------------------------------------

systemctl mask sleep.target || true
systemctl mask suspend.target || true
systemctl mask hibernate.target || true
systemctl mask hybrid-sleep.target || true



echo
echo "======================================"
echo " GOTOWE"
echo "======================================"

echo
echo "Uruchom:"
echo "sudo reboot"

echo
echo "Po starcie:"
echo "- LightDM autologin"
echo "- Openbox"
echo "- Firefox ESR kiosk"
echo "- Beer Wall TV"
echo
echo "Aktualizacja:"
echo "sudo update-beer-wall"
