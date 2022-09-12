#!/bin/bash

# 24.Sep 2020 Bernd Broermann
# 11.Sep.2022

# Requirements:
# - curl
# - xmlstarlet
# - jq
# - yq # (pip install yq)

# curl -s http://fritz.box:49000/tr64desc.xml | xq
# curl -s http://fritz.box:49000/lanhostconfigmgmSCPD.xml | xq

[ -r /usr/local/etc/tr064vars ] && . /usr/local/etc/tr064vars
[ -r $HOME/.tr064vars ] && . $HOME/.tr064vars

TR064Url=${TR064Url:-"https://$(ip route | awk '/default/ {print $3}'):49443"}

if  ! type xq &>/dev/null  ; then echo "Please install yq:  pip install yq ."  ; exit ; fi

usage () {
    cat <<EOF

    ${0##*/} info

    ${0##*/} uptime   [ -H ] # humanreadble

    ${0##*/} hosts list [ --all ] [ --output <json|xml|*hosts*>

    ${0##*/} logs

    ${0##*/} portmapping <list|info|add|delete> -p UDP|TCP  -e 1194 -c <ip>
    ${0##*/} portmapping add -p TCP  -e 21

    ${0##*/} routers

    ${0##*/} reboot
EOF

exit
}


# function for human readble uptime
sec2str ()
{
    if [[ $1 == -v ]]; then
        local -n _result=$2;
        shift 2;
    else
        local _result;
    fi;
    local -a _elapsed;
    TZ=UTC printf -v _elapsed "%(%Y %j %H %M %S)T" $1;
    read -a _elapsed <<< "$_elapsed";
    _elapsed=$((10#$_elapsed-1970)) _elapsed[1]=$((10#${_elapsed[1]}-1));
    printf -v _elapsed " %dy %dd %.0fh %.0f' %.0f\"" ${_elapsed[@]};
    _result=${_elapsed// 0?};
    [[ ${_result@A} == _result=* ]] && echo "$_result"
}


tr-064 () {

    urn="dslforum-org"
    # urn="schemas-upnp-org"
    location=$1
    service=$2
    action=$3
    shift 3
    inputs=$@

    param=$(
       for input in $inputs ; do
       echo "<s:${input%=*}>${input#*=}</s:${input%=*}>"
       done
    )

    REQUESTBODY="<?xml version='1.0' encoding='utf-8'?>
        <s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'>
            <s:Body>
                <u:$action xmlns:u='urn:$urn:service:$service'>
                    $param
                </u:$action>
            </s:Body>
        </s:Envelope>"

    curl -s -k -m 5 --anyauth -u "$TR064User:$TR064Password" ${TR064Url}$location \
    -H 'Content-Type: text/xml; charset="utf-8"' \
    -H "SoapAction:urn:$urn:service:$service#$action" \
    -d "$REQUESTBODY" \
    | xq -r ".\"s:Envelope\".\"s:Body\".\"u:${action}Response\"" \
    | jq 'del(."@xmlns:u")'
}

fail () {
    echo "$@"
    exit 1
}
authorized () {
    if [[ $RESULT =~ Unauthorized ]] ; then
        echo "Unauthorized! set correct user and password"; return 1
    else
        return 0
    fi
}

ENDPOINT=$1
shift
ACTION=$1

if grep -q -- "^-" <<< $ACTION ; then
  : #echo "conatins minussign"
else
  shift
fi


VERBOSE=false
A=1
GETOPT=$(getopt -o     'vdO:t:p:e:c:H' \
	                --long 'verbose,debug,output:,all,type:,protocol:,externalport:,client:,human' \
			                -n "${0##*/}" -- "$@")
if [ $? -ne 0 ]; then echo 'Terminating...' >&2; exit 1; fi
eval set -- "$GETOPT"; unset GETOPT
while true; do
    case "$1" in
        '-v'|'--verbose') VERBOSE=true; shift; continue ;;
        '-d'|'--debug') DEBUG=true; shift; continue ;;
        '--all') A=0 ; shift ; continue ;;
        '-O'|'--output') OUTPUT=${2}; shift 2; continue ;;
        '-t'|'--type') CONNTYPE=${2}; shift 2; continue ;;
        '-p'|'--protocol') Protocol=${2}; shift 2; continue ;;
        '-e'|'--externalport') ExternalPort=${2}; shift 2; continue ;;
        '-c'|'--client') InternalClient=${2}; shift 2; continue ;;
        '-H'|'--human') HUMAN=true ; shift; continue ;;

        '--') shift; break ;;
        *) echo 'Internal error!' >&2; exit 1 ;;
    esac
done


[ $OUTPUT ] || OUTPUT=hosts


case $ENDPOINT in
    info)
        RESULT=$(tr-064 /upnp/control/deviceinfo DeviceInfo:1 GetInfo)
        if authorized ; then
            echo "$RESULT" \
            |jq 'del(."NewDeviceLog")'\
            |sed -e  "s/\"New/\"/g"\
            |jq
        fi
    ;;
    uptime)
        RESULT=$(tr-064 /upnp/control/deviceinfo DeviceInfo:1 GetInfo)
        if authorized ; then
            secs=$(echo "$RESULT" | jq -r '.NewUpTime')
            [ "$HUMAN" == "true" ] && sec2str $secs || echo $secs
        fi
    ;;
    devicelog|logs)
        RESULT=$(tr-064 /upnp/control/deviceinfo DeviceInfo:1 GetInfo)
        if authorized ; then
            echo "$RESULT" | jq -r '."NewDeviceLog"' | tac
        fi
    ;;
    reboot)
        tr-064 /upnp/control/deviceconfig DeviceConfig:1 Reboot
    ;;


    routers)
        RESULT=$(tr-064 /upnp/control/lanhostconfigmgm LANHostConfigManagement:1 GetIPRoutersList)
        if authorized ; then
            echo "$RESULT" | jq -r '.NewIPRouters'
        fi
    ;;
    hosts)
        RESULT=$(tr-064 /upnp/control/hosts  Hosts:1  GetHostNumberOfEntries)
        if authorized ; then
            HostNumberOfEntries=$(echo "$RESULT" | jq -r '."NewHostNumberOfEntries"')

            max=$(($HostNumberOfEntries - 1))

            for I in $(seq 0 $max) ; do
                HostEntry=$(tr-064 /upnp/control/hosts Hosts:1 GetGenericHostEntry NewIndex=$I)
                case $OUTPUT in
                    json)
                        echo "$HostEntry"
                    ;;
                    hosts)
                        echo "$HostEntry" | jq -r --argjson a $A  'select(."NewActive"|tonumber >= $a)
                             |"\(."NewIPAddress") \(."NewHostName") # \(."NewActive") \(."NewInterfaceType")"'
                    ;;
                    *)
                        echo "-o json|-o hosts"
                    ;;
                esac
            done
        fi
    ;;

    portmapping)
        # Set Conntectontype by ModelName
        ModelName=$(tr-064 /upnp/control/deviceinfo DeviceInfo:1 GetInfo |jq -r '.NewModelName')
        [[ $ModelName =~ Cable ]] && CONNTYPE=Cable || CONNTYPE=DSL
        # Connectiontype is DSL , if no defined
        CONNTYPE=${CONNTYPE:-DSL}


        if [[ "$CONNTYPE" =~ [D|d][S|s][L|l] ]] ; then
            LOCATION=wanpppconn1
            SERVICE=WANPPPConnection
        fi
        if [[ "$CONNTYPE" =~ [c|C]able ]] ; then
            LOCATION=wanipconnection1
            SERVICE=WANIPConnection
        fi

        [ $LOCATION ] || fail "LOCATION missing"
        [ $SERVICE ] || fail "SERVICE missing"

        $VERBOSE && echo "ControlURL :   /upnp/control/$LOCATION"
        $VERBOSE && echo "Service    :   ${SERVICE}:1"
        $VERBOSE && echo "$TR064User:....${TR064Password:((${#TR064Password}-3)):${#TR064Password}}   ${TR064Url}"


        case $ACTION in
            list)
                entries=$(tr-064 /upnp/control/$LOCATION  ${SERVICE}:1  GetPortMappingNumberOfEntries |  jq -r '.NewPortMappingNumberOfEntries' )
                max=$(($entries - 1))

                for I in $(seq 0 $max) ; do
                    tr-064 /upnp/control/$LOCATION  ${SERVICE}:1 GetGenericPortMappingEntry NewPortMappingIndex=$I
                done

            ;;

            add)

                MYIP=$(ip a s $(ip route|sed -n "s/default .*dev \([a-z0-1]*\) .*/\1/p")|sed -n "s/.*inet \([0-9\.]*\)\/[0-9]* .*/\1/p")
                [ $Protocol ] || fail "-p|--protocol (TCP|UDP)  missing"
                [ $ExternalPort ] || fail "-e|--externalport missing"
                [ $InternalPort ] || InternalPort=$ExternalPort
                [ $InternalClient ] || InternalClient=$MYIP
                [ "$PortMappingDescription" ] || PortMappingDescription="Inbound_Port${InternalPort}_${Protocol}"
                echo "
                Protocol=$Protocol
                ExternalPort=$ExternalPort
                InternalPort=$InternalPort
                InternalClient=$InternalClient
                PortMappingDescription=$PortMappingDescription
                "
                tr-064 /upnp/control/$LOCATION  ${SERVICE}:1 AddPortMapping \
                NewRemoteHost=0.0.0.0 \
                NewExternalPort=$ExternalPort \
                NewProtocol=$Protocol \
                NewInternalPort=$InternalPort \
                NewInternalClient=$InternalClient \
                NewEnabled=1 \
                NewPortMappingDescription="$PortMappingDescription" \
                NewLeaseDuration=0
            ;;
            show|info)
                [ $Protocol ] || fail "-p|--protocol (TCP|UDP)  missing"
                [ $ExternalPort ] || fail "-e|--externalport missing"

                tr-064 /upnp/control/$LOCATION  ${SERVICE}:1 GetSpecificPortMappingEntry \
                NewRemoteHost=0.0.0.0 \
                NewProtocol=$Protocol \
                NewExternalPort=$ExternalPort
            ;;

            delete)
                [ $Protocol ] || fail "-p|--protocol (TCP|UDP)  missing"
                [ $ExternalPort ] || fail "-e missing"
                tr-064 /upnp/control/$LOCATION  ${SERVICE}:1 DeletePortMapping \
                    NewRemoteHost=0.0.0.0 \
                    NewProtocol=$Protocol \
                    NewExternalPort=$ExternalPort
            ;;


            *) usage ;;

        esac

    ;;
    voip)
       tr-064 /upnp/control/x_voip X_VoIP:1 X_AVM-DE_GetClients | jq -r '."NewX_AVM-DE_ClientList"' | xq  '.List.Item[]'
    ;;

    *) usage ;;

esac
