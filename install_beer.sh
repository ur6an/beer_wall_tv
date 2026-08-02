#!/bin/bash

set -e

echo "======================================"
echo " Beer Wall TV Installer"
echo " Orange Pi PC + Armbian"
echo "======================================"

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom skrypt jako root."
    exit 1
fi


echo
read -p "Podaj nazwę użytkownika systemowego: " USER_NAME


if ! id "$USER_NAME" >/dev/null 2>&1; then
    echo "Użytkownik $USER_NAME nie istnieje."
    echo "Tworzę użytkownika..."

    adduser --disabled-password --gecos "" "$USER_NAME"
    usermod -aG sudo "$USER_NAME"
fi


echo
echo "== Aktualizacja systemu =="

apt update
apt -y upgrade


echo
echo "== Instalacja pakietów =="

DEBIAN_FRONTEND=noninteractive apt install -y \
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
    wget \
    curl \
    tar


PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')


echo
echo "== Pobieranie Beer Wall TV =="

rm -rf /var/www/lamus

mkdir -p /var/www


cd /tmp

wget -O lamus.tar.gz \
https://raw.githubusercontent.com/ur6an/beer_wall_tv/main/lamus.tar.gz


echo
echo "== Rozpakowanie strony =="

tar -xzf lamus.tar.gz -C /var/www


if [ ! -d "/var/www/lamus" ]; then
    echo "Błąd: brak katalogu /var/www/lamus"
    exit 1
fi


chown -R www-data:www-data /var/www/lamus
chmod -R 755 /var/www/lamus



echo
echo "== Konfiguracja Apache =="


a2enmod proxy_fcgi setenvif rewrite

a2enconf php${PHP_VERSION}-fpm


cat >/etc/apache2/sites-available/000-default.conf <<EOF

<VirtualHost *:80>

ServerAdmin webmaster@localhost

DocumentRoot /var/www/lamus


<Directory /var/www/lamus>

Options FollowSymLinks

AllowOverride All

Require all granted

</Directory>


DirectoryIndex index.php index.html


ErrorLog \${APACHE_LOG_DIR}/error.log

CustomLog \${APACHE_LOG_DIR}/access.log combined


</VirtualHost>

EOF



systemctl enable php${PHP_VERSION}-fpm
systemctl restart php${PHP_VERSION}-fpm

systemctl enable apache2
systemctl restart apache2



echo
echo "== Konfiguracja Openbox =="


mkdir -p /home/$USER_NAME/.config/openbox


cat >/home/$USER_NAME/.config/openbox/autostart <<'EOF'

#!/bin/bash


xset s off

xset -dpms

xset s noblank


unclutter -idle 1 &


sleep 5


while true
do

firefox-esr \
 --kiosk \
 --private-window \
 http://localhost


sleep 5

done

EOF


chmod +x /home/$USER_NAME/.config/openbox/autostart


chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.config



echo
echo "== Konfiguracja LightDM =="


mkdir -p /etc/lightdm/lightdm.conf.d


cat >/etc/lightdm/lightdm.conf.d/10-autologin.conf <<EOF

[Seat:*]

autologin-user=$USER_NAME

autologin-user-timeout=0

user-session=openbox

EOF


systemctl enable lightdm



echo
echo "== Wyłączenie wygaszania konsoli =="


if grep -q "consoleblank=0" /boot/armbianEnv.txt; then

echo "consoleblank już ustawiony"

else

echo "extraargs=consoleblank=0" >> /boot/armbianEnv.txt

fi



echo
echo "== Czyszczenie =="


apt autoremove -y
apt autoclean



echo
echo "======================================"
echo " Instalacja zakończona"
echo "======================================"

echo
echo "Użytkownik: $USER_NAME"
echo "WWW: http://localhost"
echo "Pliki: /var/www/lamus"
echo
echo "Po restarcie:"
echo "- automatyczne logowanie"
echo "- Openbox"
echo "- Firefox ESR kiosk"
echo "- Beer Wall TV"
echo

echo "Wykonaj:"
echo "reboot"
