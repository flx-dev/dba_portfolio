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
# this script accepts lists in the format 
# first name - last name; email

# error handlers
set -o errexit
set -o nounset
set -o pipefail

## BEGIN CONSTANTS
# wait time for keypress
WAIT_TIME=20;

# password lenght
PASSWD_LEN=10;
# location of the users list to generate for HR
SOURCE_LIST='./hr_users_sample_list.txt';

# location of the cleansed list
USR_LIST_FILE='./new_user_list.txt';

# file containing list of users and passwords generated
# debug purpose
GEN_USR_LIST='./gen_usr_list.txt';
GEN_PASWD_FILE='./gen_passwd.txt';

## END CONSTANTS

## BEGIN FUNCTIONS

#clean user input
clean_input () {
# set all to lower case remove leading trailing spaces
    tr '[:upper:]' '[:lower:]' < "$1" |\
    #remove leading spaces
    sed 's/^[ \t]*//'|\
    #remove trailing
    sed 's/[ \t]*$//'|\
    #remove empty lines
    sed '/^$/d' >> "$2"
    return 0;
}

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

# create necessary files
touch ./gen_usr_list.txt
touch ./gen_passwd.txt
touch ./list_users_passwd_created.txt

#error trap
trap "rm $USR_LIST_FILE ./gen_usr_list.txt ./gen_passwd.txt \
    ./list_users_passwd_created.txt 2> /dev/null; exit" SIGINT SIGTERM


echo -e "      ################  BULK USERS CREATION SCRIPT ######################"
echo -e "\n    This script creates new users from a given formatted list and"
echo -e "    generates a another list to allow to bulk email the credentials"
echo -e "    accepted format: [first - last; emaill] John - Doe; jo.d@myemail.com"

disclaimer

#check for duplicate entries in the input list
check_flag=$(uniq -dc $SOURCE_LIST)
if [ -n "$check_flag" ]; then
    echo -e "    Duplicated users present! Please address the following issues:\n"
    echo -e "$check_flag \n"
    read -t "$WAIT_TIME" -n 1 -s -r -p "   Press any Key to Continue";
    clear
    rm $USR_LIST_FILE ./gen_usr_list.txt ./gen_passwd.txt \
        ./list_users_passwd_created.txt 2> /dev/null;
    exit;
fi


clean_input "$SOURCE_LIST" "$USR_LIST_FILE"

# grab length of the users list
usr_nr=$(wc -l < $USR_LIST_FILE)

# make sure of the number of users
echo -e "\n"
echo -e "     $usr_nr USERS ARE ABOUT TO BE CREATED Ctrl+C to Abort \n"

for ((i=1; i<="$usr_nr"; i++))
do
    
    # extract 2 char from name
    first=$(sed -n "$i"'p' "$USR_LIST_FILE" | grep -o -P '^.{2}' |\
            #remove trailing
            sed 's/[ \t]*$//')

    # extract 5 char from lastname after - sym
    last=$(sed -n "$i"'p' "$USR_LIST_FILE" | grep -o -P '\-.{0,5}' |\
           # remove the - sym
           sed 's/\-//g'|\
           #remove trailing
           sed 's/[ \t]*$//')
    # extract email after ;
    email=$(sed -n "$i"'p' "$USR_LIST_FILE" | grep -o "\;.*" |\
            # remove the ; sym
            sed 's/\;//g'|\
            # trim all spaces
            tr -d -c '[:graph:]')

    # generate random password 10 char
    rd_passwd=$(openssl rand -base64 $PASSWD_LEN)
    
    # generate distinct characters to deal with people with
    # same first and last name
    char_dist=$(echo -n "$first$last$email" | sha256sum |\
        grep -o -P '^.{2}')

    # full username assembled
    user_name_ad=$first$last$char_dist

    #append user to list > debug
    echo "$user_name_ad" >> "$GEN_USR_LIST"

    # append password > debug
    echo "$rd_passwd" >> "$GEN_PASWD_FILE"

    # append generated name and password to list
    echo -e "username: $user_name_ad pswd: $rd_passwd email: $email" >>\
        ./list_users_passwd_created.txt
    
     # create new user
     sudo useradd -m "$user_name_ad" -s /usr/bin/bash
     echo "$user_name_ad:$rd_passwd" | sudo chpasswd
    
     # expirepassword to force change on login
     sudo passwd -e "$user_name_ad"

done

# remove residual files leave only thelist with users and pswd
rm gen_passwd.txt gen_usr_list.txt new_user_list.txt 2> /dev/null ;

echo -e "ALL USERS CREATED"
