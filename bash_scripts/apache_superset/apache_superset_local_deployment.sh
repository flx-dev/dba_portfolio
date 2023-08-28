#!/usr/bin/bash

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

#  additional sources:
#  https://superset.apache.org/docs/installation/configuring-superset

# error handlers
set -o errexit
set -o nounset
set -o pipefail


#CONSTANTS
WAIT_TIME=30;
CURRENT_DIR=$(pwd);
SUPERSET_HOME="apache_superset";
HTTP_ADDR="http://127.0.0.1:8088";

#FUNCTIONS
# activate the default python venv
activate_pyvenv () {
  . venv/bin/activate
}

# licence and warnings
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

# traps 
trap 'rm -rf $CURRENT_DIR/$SUPERSET_HOME 2> /dev/null;\
    echo -e "\nOperation interrupted, cleaning up!\n";\
    exit;' SIGINT SIGTERM

## BEGIN

# stop if root
if [ "$EUID" = 0 ];   

    then echo "Please DO NOT run this script as root";
    sleep 4s;
    exit;
fi;

#info
echo -e "    ###################             ###################"
echo -e "\n      Welcome to the Apache Superset flash installer!!!\n"
echo -e "    ###################             ###################"

disclaimer

echo -e "    ## This script will install a local development version ##"
echo -e "           #### Please DO NOT run it as root!!\n ####"


# add parameter to user's .bashrc file
{

echo -e "\n#superset added paramenters"
echo -e "export FLASK_APP=superset"
echo -e "alias activate='. venv/bin/activate'"
echo -e "alias superset_start='cd "$CURRENT_DIR"/"$SUPERSET_HOME" && 
    activate &&
    superset run -h 0.0.0.0 -p 8088 --with-threads --reload'"

} >> /home/"$USER"/.bashrc

#superset pre-requisites
sudo apt-get install build-essential libssl-dev libffi-dev python3-dev \
    python3-pip libsasl2-dev libldap2-dev default-libmysqlclient-dev -y

sudo apt-get install python3-virtualenv python3-venv -y

# create folder for virtual enviroment
mkdir apache_superset
cd apache_superset

# create virtual environment and launch it

python3 -m venv venv && activate_pyvenv

#install superset dependencies with pip3
pip3 install wheel
pip3 install pillow
#pip3 install wtforms==2.2

# install superset
pip3 install apache-superset

# solve bug with previous version of sqlparse
pip3 uninstall -y sqlparse && pip3 install sqlparse==0.4.3
pip3 install marshmallow-enum
# set environment variable
export FLASK_APP=superset

# create a superset config file
touch venv/bin/superset_config.py

# create default config
echo -e " #Superset specific config
ROW_LIMIT = 5000

SUPERSET_WEBSERVER_PORT = 8088

# Flask App Builder configuration
# Your App secret key will be used for securely signing the session cookie
# and encrypting sensitive information on the database
# Make sure you are changing this key for your deployment with a strong key.
# You can generate a strong key using \`openssl rand -base64 42\`.
# Alternatively you can set it with \`SUPERSET_SECRET_KEY\` environment variable.
SECRET_KEY = 'YOUR_OWN_RANDOM_GENERATED_SECRET_KEY'

# The SQLAlchemy connection string to your database backend
# This connection defines the path to the database that stores your
# superset metadata (slices, connections, tables, dashboards, ...).
# Note that the connection information to connect to the datasources
# you want to explore are managed directly in the web UI
SQLALCHEMY_DATABASE_URI = 'sqlite://///home/$USER/.superset/superset.db'

# Flask-WTF flag for CSRF
WTF_CSRF_ENABLED = True
# Add endpoints that need to be exempt from CSRF protection
WTF_CSRF_EXEMPT_LIST = []
# A CSRF token that expires in 1 year
WTF_CSRF_TIME_LIMIT = 60 * 60 * 24 * 365

# Set this API key to enable Mapbox visualizations
MAPBOX_API_KEY = ''
# enable unsafe SQLite connection
PREVENT_UNSAFE_DB_CONNECTIONS = False" >> venv/bin/superset_config.py

#initialize the superset database
superset db upgrade

# Create an admin user in your metadata database 
# (use `admin` as username and password to be able to load the examples)
sleep 4s
echo -e "\n\nto be able to use the preloaded example use 'admin' as password'"
echo -e "\n\n"
sleep 4s

superset fab create-admin

# Load some data to play with - to use this set password to 'admin'
superset load_examples

# repeat command to complete download due to limitations
superset load_examples

# Create default roles and permissions
superset init

echo -e "re-open a new terminal and run 'superset_start'"
echo -e "You will be able to access Apache Superset at this address:"
echo -e "\n $HTTP_ADDR \n\n"
echo -e "to close Apache Superset press CTRL+C\n"
read -t "$WAIT_TIME" -n 1 -s -r -p "Press any Key to Continue";

clear
exit;
