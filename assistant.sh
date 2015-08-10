#!/bin/bash

nic_number=$(ip addr ls | grep 'state UP' | grep -c -e "eth[0-9]\{1,2\}:")
ip_list=$(ip addr ls | grep global | awk '{print $2}' | awk -F '/' '{print $1}')

note[0]='\nBefore running this script:
- configure all your network cards
- edit your fstab and mount all the required devices\n
Press ctrl+c sto stop it at anytime.'

question[0]="\nIs this node going to be a gateway only?
(A gateway only node is able to run guests, but it doesn't store any data.
The cluster size is not going to be affected).\n"

question[1]="\nMore network card has been detected.
If one of them is going to be dedicated to syncronization data, type its ip.
(Leave it blank to not use dedicated nic).\n
These ip has been detected: $(echo $ip_list | tr -s '\n')"

question[2]="\nType the zookeeper ip address list on a
*single line*, separated by a single space.
Sheepdog will connect to these ip's.\n"

question[3]="\nRemember that each device must have extended attributes enabled.
Check your /etc/fstab if in doubt.
The following mount point has been detected:\n"

question[4]="\nThis node has been recognized as a Zookeeper node.
These servers' ip will be used:\n"

question[5]="\nPlease type the ip to bind sheep daemon.\n"

error[0]="\nNo devices has been detected.
It's recommended run sheepdog on a dedicated mount point.
Mount a device and re-run sheepdog_assistant.sh.\n"

error[1]='\nSheepdog is running! Sheep daemon must not be running.\n'
error[2]='\nQemu/kvm is running! Qemu must not be running'

sheep_disks=()
multi_nic=false

error () {
    echo -e "$1"
    exit 2
}

confirm () {
    while true
    do
        echo -e "$1"
        read -p '(y/n): ' answer
        [ "$answer" == 'y' -o "$answer" == 'Y' ] && return 0
        [ "$answer" == 'n' -o "$answer" == 'N' ] && return 1
        echo -e "\nType 'y' or 'n'\n"
    done
}

check_ip_syntax () {
    [ -z "$1" ] && return 2
    pattern='^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$'
    echo $1 | grep $pattern > /dev/null || return 1
    bytes=$(echo $1 | awk -F '.' '{print $1" "$2" "$3" "$4}')
    for byte in $bytes
    do
        [ $byte -le 255 ] || return 1
    done
    return 0
}

add_ip_io () {
while true
do
    read -p 'ip: ' ip_io
    [ -z "$ip_io" ] && break
    echo "$ip_list" | grep -x $ip_io > /dev/null
    [ $? -eq 0 ] && break || echo "Wrong ip. Type again."
done
}

add_ip_sheep () {
while true
do
    read -p 'ip: ' ip_sheep
    [ -z "$ip_sheep" ] && break
    echo "$ip_list" | grep -x $ip_sheep > /dev/null
    [ $? -eq 0 ] && break || echo "Wrong ip. Type again."
done
}

add_mp () {
    read -p 'path: ' path
    [ -z "$path" -a ${#sheep_disks[@]} -eq 0 ] && return 2
    [ -z "$path" ] && return 1
    grep -w "$path" /etc/mtab > /dev/null
    if [ $? -eq 0 ]
    then
        echo '...added'
        sheep_disks+=("$path")
        return 0
    else
        echo "It doesn't seem to be a mount point or it's not mounted"
        return 2
    fi
}

add_sheep_disks () {
    while true
    do
        add_mp
        status=$?
        [ $status -eq 2 ] && continue
        [ $status -eq 1 ] && break
    done
}

clear

pgrep -x sheep > /dev/null
[ $? -eq 0 ] && error "${error[1]}"

pgrep qemu > /dev/null
[ $? -eq 0 ] && error "${error[2]}"

pgrep -x kvm > /dev/null
[ $? -eq 0 ] && error "${error[2]}"

echo -e "${note[0]}"
confirm 'Continue?\n'
[ $? -ne 0 ] && exit

# Add devices if not gateway only
confirm "${question[0]}"
gw_only=$?
if [ $gw_only == 1 ]
then
    devices=$(grep ^/dev /etc/mtab | awk '{ print $2 }' | sed -e '/^\/$/d')
    [ -z "$devices" ] && error "${error[0]}"
    echo -e "${question[3]}"
    echo -e "$devices"
    echo -e "\nType the mount point(s) used by sheepdog, one per line."
    echo "(Leave blank once done)"
    add_sheep_disks
    [ -n "$sheep_disks" ] && \
    echo -e "\nThe selected mount point are: ${sheep_disks[@]}" || \
    error 'Add at least one device'
fi

# Add dedicated nic
if [ $nic_number -gt 1 ]
then
    echo -e "${question[1]}"
    add_ip_io
fi

# Zookeeper

# 1 means do not use zookeeper conf ip
use_zookeeper_conf_ips=1
if [ -f /etc/zookeeper/conf/zoo.cfg ]
then
    echo -e "${question[4]}"
    zookeeper_conf_ips=$(grep 'server\.' /etc/zookeeper/conf/zoo.cfg | grep -v '#' | awk -F '=' '{ print $2 }' | awk -F ':' '{ print $1 }')
    echo "$zookeeper_conf_ips"
    confirm "\nAre these the right zookeeper' ip(s)?\n"
    use_zookeeper_conf_ips=$?
fi

if [ $use_zookeeper_conf_ips -eq 1 ]
then
    while true
    do
        echo -e "${question[2]}"
        read -p 'ip(s): ' zookeeper_ips
        # check ip syntax
        [ -z "$zookeeper_ips" ] && continue
        bad_ip=0
        for zookeeper_ip in $zookeeper_ips
        do
            check_ip_syntax $zookeeper_ip
            if [ $? -ne 0 ]
            then
                echo "$zookeeper_ip is not a valid ip"
                bad_ip=1
                break
            fi
        done
        [ $bad_ip -ne 0 ] && continue
        
        # Strip spaces
        zookeeper_ips=$(echo "$zookeeper_ips" | tr -s ' ')
        echo -e "\nIs the ip list correct?\n\t$zookeeper_ips\n"
        confirm "Press 'n' to re-type, 'y' to continue\n"
        [ $? == 0 ] && break
    done
else
    zookeeper_ips="$zookeeper_conf_ips"
fi

ip_count=$(echo "$ip_list" | wc -w)
if [ $ip_count -eq 1 ]
then
    ip_sheep=$ip_list
else
    echo -e "${question[5]}"
    while true
    do
        add_ip_sheep
        [ $? -eq 0 ] && break
    done
fi

# Summary
[ $gw_only -eq 0 ] && gw_only_summary='yes' || gw_only_summary='no'

echo
echo -e "SUMMARY"
echo -e "======="
echo -e "Gateway only:\t$gw_only_summary" 
echo -e "Devices:\t${sheep_disks[@]}"
echo -e "Sheep ip:\t$ip_sheep"
echo -e "Dedicate nic:\t$ip_io"
echo -e "Zookeeper:\t$(echo $zookeeper_ips | tr -s '\n')"
echo -e "======="


confirm "\nIf everythin is correct, press 'y' or 'n' to exit\n"
[ $? -ne 0 ] && exit

confirm "\nWould you like to run sheepdog now?\n"
run=$?

# Generate the right syntax for sheep command

# gateway only
[ $gw_only -eq 0 ] && gw='--gateway'

# disks
disks='/var/lib/sheepdog'
if [ $gw_only -eq 1 ]
then
    for mp in ${sheep_disks[@]}
    do
        disks="$disks,$mp"
    done
    disks="-n $disks"
fi

# io nic e bind address
[ -n "$ip_io" ] && nic_io="-ioaddr host=$ip_io,port=3333"
sheep_addr="--myaddr $ip_sheep"

# zookeeper
for zookeeper_ip in $zookeeper_ips
do
    zookeeper="$zookeeper$zookeeper_ip:2181,"
done
zookeeper="-c zookeeper:$zookeeper"
zookeeper="${zookeeper%?}"

cmd=$(echo "sheep $gw $nic_io $sheep_addr $zookeeper $disks" | tr -s ' ')

echo
[ $run -eq 0 ] && echo $cmd || exit

