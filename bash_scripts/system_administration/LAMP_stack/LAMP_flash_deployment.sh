#!/bin/bash

#  Copyright 2023 Felix Di Nezza
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License along
#  with this program. If not, see <https://www.gnu.org/licenses/>. 

# INFO
# this script deploys a simple LAMP stack on apt based distros
# PLEASE DO REMEMBER TO SET YOUR USERS AND PASSWORD !!!!!

# error handlers
set -o errexit
set -o nounset
set -o pipefail

# BEGIN CONSTANTS
## PLEASE DO REMEMBER TO SET YOUR USERS AND PASSWORD !!!!!

#sleep delay
LN_TIME=3;
# apache's low level user name
APACHE_USER_NAME="apacheuser"
# apache's low level user password
APACHE_USER_PSWD="myapachepass"
# mariadb default data folder
MDB_DEFAULT_DF="/\[mysqld\]/a datadir                 = ";
#mariadb new data folder
MDB_NEW_DF="/data/maria_db_data";
# mariadb admin user
MDB_AD_USER="root";
# mariadb admin user password
MDB_AD_USER_PSWD="root";
# phpmyadmin password
PHP_MYADM_PSWD="root";
# phpmyadmin initial setup password 
PHP_MYADM_ISET_PSWD="root";

# END CONSTANTS



# BEGIN FUNCTIONS

disclaimer () {
    echo -e "
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program. If not, see <https://www.gnu.org/licenses/>.

    "
}

# END FUNCTIONS


#error trap
trap 'echo -e "User interruption with ^C"; exit' SIGINT SIGTERM SIGHUP


#BEGIN

# LAMP STACK AUTOMATION
# Apache 2 installation and configuration
apt-get install -y apache2 ufw vim openssh-server
ufw allow 80/tcp
ufw allow 443/tcp

# hardening Apache2
#create backup copy of the config file
cp /etc/apache2/apache2.conf /etc/apache2/apache2.bak

# disable Trace HTTP request
echo -e '\n# Disable Trace HTTP Requests - FDN
TraceEnable Off' >> /etc/apache2/apache2.conf

# Hide Server Tokens and Signature
echo -e '\n# Hide Server Tokens and Signatures - FDN
ServerTokens Prod
ServerSignature Off\n
<IfModule mod_headers.c>
Header unset Server
Header unset X-Powered-By
</IfModule>' >> /etc/apache2/apache2.conf

#create apache group
groupadd apachegroup


#create low privilege user for Apache

sudo useradd $APACHE_USER_NAME -g apachegroup -s /usr/sbin/nologin
echo $APACHE_USER_NAME:$APACHE_USER_PSWD | sudo chpasswd

# change APACHE_RUN to match user and group
sed -i 's/APACHE_RUN_USER=www-data/APACHE_RUN_USER=apacheuser/g' /etc/apache2/envvars
sed -i 's/APACHE_RUN_GROUP=www-data/APACHE_RUN_GROUP=apachegroup/g' /etc/apache2/envvars

systemctl restart apache2

echo -e 'APACHE INSTALLED AND CONFIGURED'
sleep "$LN_TIME"

# PHP installation
apt-get install -y php

echo -e 'PHP INSTALLED'
sleep "$LN_TIME"

# install and configure mariadb

# preseed mariadb installation
debconf-set-selections <<<"mariadb-server mariadb-server/root_password password $MDB_AD_USER"
debconf-set-selections <<<"mariadb-server mariadb-server/root_password_again password $MDB_AD_USER_PSWD"
apt-get install mariadb-server -y

# stop database for maintenance
systemctl stop mariadb.service

# create new data directory
mkdir -p "$MDB_NEW_DF"

# change default data directory
chown -R mysql:mysql "$MDB_NEW_DF"

# move content of the default folder
cp -ar /var/lib/mysql/* "$MDB_NEW_DF"/

# rename the old folder to preserve it
mv /var/lib/mysql /var/lib/mysql.bak

#replece default string in config file
sed -ir "$MDB_DEFAULT_DF $MDB_NEW_DF" /etc/mysql/mariadb.conf.d/50-server.cnf

#restart and enable database
systemctl enable mariadb.service
systemctl restart mariadb.service


# install ACL
apt-get install -y acl

echo -e "ACL installed"
sleep "$LN_TIME"

#phpMyAdmin installation
# preseed phpmyadmin installation
debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
# username for the admin user of the MySQL database used by phpMyAdmin
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-user string $MDB_AD_USER"
# password for the admin user of the MySQL database used by phpMyAdmin
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MDB_AD_USER_PSWD"
# password for the application user of the MySQL database used by phpMyAdmin
debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $PHP_MYADM_PSWD"
# confirm the password set for the application user of the MySQL database used by phpMyAdmin
debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $PHP_MYADM_PSWD"
# selection of the database type used by phpMyAdmin
debconf-set-selections <<< "phpmyadmin phpmyadmin/database-type select mysql"
# setup password for the phpMyAdmin configuration used during the initial setup
debconf-set-selections <<< "phpmyadmin phpmyadmin/setup-password password $PHP_MYADM_ISET_PSWD"

apt-get install phpmyadmin -y

systemctl restart mariadb.service
systemctl restart apache2.service

echo -e 'PHPMYADMIN CONFIGURED AND INSTALLED\n'

echo -e 'LAMP server deploymet completed!!'




