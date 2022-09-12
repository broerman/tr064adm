# TR-064  Admintool

This  script reads ans set some values in tr-064 managed devices. 


# Requirements:
 - bash
 - gnutools (sed,grep)
 - xmlstarlet
 - jq 
 - yq # (pip install yq)

**bash** and **gnutools** are ususally installed by default on linux distributions.
**xmlstarlet** and **jq** mostly found in the distributions package management (yum,deb,pacman..)
For **yq** you need a python environment with pip to install.

# Variables

Environment variables for auth can be set in source files.

  - /usr/local/etc/tr064vars
  - $HOME/.tr064vars

This file contains Variables for authorzation, url and Modem type of the device.

```
# /usr/local/etc/tr064vars:$HOME/.tr064vars
# If not set , host part of  url is calculated by ip route. You can set by
TR064Url="https://fritz.box:49443"

# Username and password are requierd for some actions like reboot 
TR064User="fritzXXXX"
TR064Password='XXXXXXXXXXXXXXXXXXXX'

# Cable and DSL devices have different methods for some setting portmapping
# The script will try to set this variable from Modelname, but it can be set here
CONNTYPE=Cable
CONNTYPE=DSL
```

# Commands

    tr064adm.sh info

    tr064adm.sh uptime   [ -H ] # humanreadble

    tr064adm.sh hosts list [ --all ] [ --output <json|xml|*hosts*>

    tr064adm.sh devicelog

    tr064adm.sh portmapping <list|info|add|delete> -p UDP|TCP  -e 1194 -c <ip>
    tr064adm.sh portmapping add -p TCP  -e 21

    tr064adm.sh routers

    tr064adm.sh reboot


Referenz:

https://avm.de/fileadmin/user_upload/Global/Service/Schnittstellen/AVM_TR-064_first_steps.pdf

