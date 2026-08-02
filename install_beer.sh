#!/bin/bash

set -e

echo "======================================"
echo " Beer Wall TV Installer v0.98"
echo " Orange Pi + Armbian"
echo " Firefox ESR Kiosk"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom przez sudo"
    exit 1
fi


# -----------------------------------------------------
# użytkownik
# -----------------------------------------------------

if [ -n "$SUDO_USER" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME=$(logname)
fi


USER_HOME=$(eval echo ~$USER_NAME)

echo "Użytkownik: $USER_NAME"



# -----------------------------------------------------
# pakiety
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
# Beer Wall TV
# -----------------------------------------------------

echo "== Pobieranie strony =="


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
# Apache
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
# Openbox
# -----------------------------------------------------

mkdir -p $USER_HOME/.config/openbox


cat >$USER_HOME/.config/openbox/autostart <<EOF

#!/bin/bash


xset s off

xset s noblank

xset -dpms


unclutter -idle 0.5 -root -jitter 2 &

EOF


chmod +x $USER_HOME/.config/openbox/autostart

chown -R $USER_NAME:$USER_NAME $USER_HOME/.config



# -----------------------------------------------------
# X11 - brak wygaszania
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
# LightDM autologin
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
# Firefox kiosk
# -----------------------------------------------------

cat >/usr/local/bin/firefox-kiosk.sh <<EOF
#!/bin/bash

export DISPLAY=:0

sleep 15


while true
do

firefox-esr \
--kiosk \
--private-window \
http://localhost/


sleep 5

done

EOF


chmod 755 /usr/local/bin/firefox-kiosk.sh



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
# Update Beer Wall
# -----------------------------------------------------

cat >/usr/local/bin/update-beer-wall <<'EOF'

#!/bin/bash

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

EOF


chmod +x /usr/local/bin/update-beer-wall



# -----------------------------------------------------
# Watchdog Orange Pi PC
# -----------------------------------------------------

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

LimitRTPRIO=infinity

LimitMEMLOCK=infinity

EOF


systemctl daemon-reload

systemctl enable watchdog

systemctl restart watchdog || true



# -----------------------------------------------------
# blokada sleep
# -----------------------------------------------------

systemctl mask sleep.target || true
systemctl mask suspend.target || true
systemctl mask hibernate.target || true
systemctl mask hybrid-sleep.target || true



echo
echo "======================================"
echo " INSTALACJA ZAKOŃCZONA"
echo "======================================"

echo

echo "Start:"
echo "sudo reboot"

echo

echo "Strona:"
echo "http://localhost"

echo

echo "Aktualizacja:"
echo "sudo update-beer-wall"
