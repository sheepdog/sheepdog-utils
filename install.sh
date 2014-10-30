#!/bin/bash

set -o pipefail

# Use 'git branch -a' to get the full branch list
branch='master'
dpkg_installed='/tmp/installed_packages.list'
dpkg_required='automake pkg-config liburcu1 liburcu-dev zlib1g zlib1g-dev
libglib2.0-dev libpixman-1-dev groff build-essential git libzookeeper-mt-dev
apt-show-versions parted'
sheep_url='https://github.com/sheepdog/sheepdog.git'
qemu_url='git://github.com/qemu/qemu.git'
qemu_src_dir='/usr/src/qemu'
sheepdog_url='git://github.com/sheepdog/sheepdog.git'
sheepdog_src_dir='/usr/src/sheepdog'
ip_list=$(ip addr ls | grep global | awk '{print $2}' | awk -F '/' '{print $1}')
zookeeper_conf_file='/etc/zookeeper/conf/zoo.cfg'
zookeeper_id_file='/etc/zookeeper/conf/myid'
cores=$(grep -c processor /proc/cpuinfo)
script_dir=$(basename $0)
ulimit=1024000

zookeeper_conf='tickTime=2000
initLimit=10
syncLimit=5
dataDir=/var/lib/zookeeper
clientPort=2181
maxClientCnxns=0
'

notes[0]='REMEMBER: use the option --enable-kvm when running 
qemu-system-x86_64 in your scripts.'
notes[1]='Check the other zookeeper nodes configuration.
You might have to add this node and reload the service'
notes[2]='A reboot is required. Would you like to reboot now? (You can run sheepdog_assistent.sh later).'
error[0]='It was not possible to install all the required packages.
Check your repositories (you need also "src" repository).'
error[1]="Valid options are only '1', '2' or '3'"
error[2]='It was not possible download the source code'
error[3]='There are no ip set. Configure your network first.'
error[4]='This is a wrong ip.'
question[0]='Would you like to run sheepdog-assistant?'
question[1]="It's recommended to update your system (aptitude safe-upgrade),
bofore installing sheepdog. Would you like to do it now?"

help () {
cat << EOF

        Installing sheepdog, the node will be part of the cluster and it can 
        store data increasing the cluster size.

        Installing qemu, the same node will be able to run virtual machines.
        This means it will play both roles: front-end (Virtualization) and
        back-end (storage).

        Installing zookeeper (cluster manager), the node will take part of the
        quorum. The role of the cluster manager is checking if nodes die or get
        added and notify the others.
        Remember that it's better to have and odd number of zookeeper daemons
        in the cluster and you don't need many of them.
        Three of them can monitor tens of nodes.

EOF
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

fix_limit () {
    file_max=$(grep fs.file-max /etc/sysctl.conf | grep -v '#' | awk '{print $3}')
    if [ -z "$file_max" ]
    then
        echo 'fixing fs.file-max'
        echo "fs.file-max = $ulimit" >> /etc/sysctl.conf
        sysctl -p
    elif [ $file_max -ne $ulimit ]
    then
        echo 'fixing fs.file-max'
        sed -i -e "/^fs.file-max/d" /etc/sysctl.conf
        echo "fs.file-max = $ulimit" >> /etc/sysctl.conf
        sysctl -p
    fi
    
    reboot_needed=0
    if [ $(ulimit -Hn) -ne $ulimit ]
    then
        echo "fixing number of opened file hard limit to $ulimit" 
        sed -i -e '/# End of file/d' /etc/security/limits.conf
        sed -i -e '/root hard nofile/d' /etc/security/limits.conf
        echo "root hard nofile $ulimit" >> /etc/security/limits.conf
        echo '# End of file' >> /etc/security/limits.conf
        reboot_needed=1
    fi
    
    if [ $(ulimit -Sn) -ne $ulimit ]
    then
        echo "fixing number of opened file soft limit to $ulimit"
        sed -i -e '/# End of file/d' /etc/security/limits.conf
        sed -i -e '/root soft nofile/d' /etc/security/limits.conf
        echo "root soft nofile $ulimit" >> /etc/security/limits.conf
        echo '# End of file' >> /etc/security/limits.conf
        reboot_needed=1
    fi
}


get_dpck_list () {
    dpkg -l | grep ^ii | awk '{print $2}' >  $dpkg_installed
}

check_installed_packages () {
    for package in $@
    do
        grep $package $dpkg_installed > /dev/null || error ${error[0]}
    done
}

error () {
    echo "Error: $1"
    exit 2
}

install_sheepdog () {
    if [ -d $sheepdog_src_dir ]
    then
        echo "Found sheepdog sources. Removing"
        cd $sheepdog_src_dir
        make uninstall > /dev/null
        cd - > /dev/null
        rm -rf $sheepdog_src_dir
    fi
    cd /usr/src
    git clone $sheepdog_url || error "${error[2]}"
    cd $sheepdog_src_dir
    if [ "$branch" != 'master' ]
    then
        echo "Selecting branch $branch"
        git checkout -b $branch origin/$branch || exit 2
    fi
    echo "Building..."
    ./autogen.sh > /dev/null && \
    ./configure --enable-zookeeper --disable-corosync > /dev/null && \
    make -j $cores install > /dev/null
}

install_qemu () {
    if [ -d $qemu_src_dir ]
    then
        echo "Found qemu sources. Removing"
        cd $qemu_src_dir
        make uninstall
        cd - > /dev/null
        rm -rf $qemu_src_dir
    fi
    cd /usr/src
    git clone $qemu_url || error "${error[2]}"
    cd $qemu_src_dir
    echo "Building..."
    ./configure --enable-kvm --target-list="x86_64-softmmu" > /dev/null && \
    make -j $cores install > /dev/null
}

install_zookeeper () {
    aptitude -y install zookeeper zookeeperd
    get_dpck_list
    check_installed_packages zookeeper zookeeperd || return 2
}

configure_zookeeper () {
    # FIX:
    # In case of using a netmask different from /24 there may be id conflicts
    ip_number=$(echo $ip_list | wc -w)
    if [ $ip_number -gt 1 ]
    then
        echo 'More than one ip has beed deteceted:'
        echo $ip_list
        echo 'Type the ip that will be used by zookeeper.'
        correct=1
        while true
        do
            read -p 'ip: ' ip
            for ip_detected in $ip_list
            do
                if [ "$ip_detected" == "$ip" ]
                then
                    correct=0
                    break
                fi
            done
            if [ $correct -eq 0 ]
            then
                break
            else
                echo "Wrong ip: re-type it"
            fi
        done
    else
        ip="$ip_list"
        echo "Zookeeper will listen on ip $ip"
    fi
    myid=$(echo $ip | awk -F '.' '{print $4}')
    
    echo 'Type the other zookeeper nodes ip, separated by a single space.'
    echo 'If this is the only zookeeper node, just press enter.'
    while true
    do
        read -p 'ip: ' zookeeper_ips
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
        echo "Is this ip list correct?"
        confirm "$zookeeper_ips"
        [ $? -eq 0 ] && break
    done
        
    echo "$zookeeper_conf" > $zookeeper_conf_file
    zookeeper_ips="$zookeeper_ips $ip"
    for ip in $zookeeper_ips
    do
        id=$(echo $ip | awk -F '.' '{print $4}')
        echo "server.$id=$ip:2888:3888" >> $zookeeper_conf_file
    done
    
    echo $myid > $zookeeper_id_file
    
    service zookeeper restart
}

install_required () {
    aptitude -y install $dpkg_required
    get_dpck_list
    check_installed_packages $dpkg_required || error "${error[0]}"
}


# Checking network settings
[ -z "$ip_list" ] && error "${error[3]}"
[ "$(whoami)" != 'root' ] && error "You need to be root"

# Update debian
echo 'Updating debian packages list'
aptitude update > /dev/null
confirm "${question[1]}"
[ $? -eq 0 ] && aptitude -y safe-upgrade

cat << EOF

If you already installed the standard qemu-kvm package it will be removed.
If /usr/src/qemu or /usr/src/sheepdog exist, they will be replaced after trying
to uninstalling them.


Do you whant do prceed?"

Chosse what you need to install

1) sheepdog
2) sheepdog + qemu
3) sheepdog + qemu + zookeeper
4) help

EOF

read -p 'number: ' choise

case $choise in
1)
    echo 'Installing required packages'
    install_required
    echo "Installing sheepdog..."
    install_sheepdog && sheep -v || error "Failed"
    echo 'Done'
    ;;
2)
    echo 'Installing required packages'
    install_required; echo 'Done'
    echo "Installing sheepdog..."
    install_sheepdog && sheep -v || error "Failed"
    echo "Installing qemu..."
    install_qemu && qemu-system-x86_64 --version || error "Failed"
    echo 'Done'
    echo ${notes[0]}
    ;;
3)
    echo 'Installing required packages'
    install_required; echo 'Done'
    echo "Installing sheepdog..."
    install_sheepdog || error "Failed"
    echo 'Done'
    echo "Installing qemu..."
    echo 'skipped'
    install_qemu || error "Failed"
    echo 'Done'
    echo "Installing zookeeper"
    install_zookeeper
    configure_zookeeper
    echo 'Done'
    ;;
4)  help
    exit
    ;;
*)
    error "${error[1]}"
    ;;
esac

# Print summary
case $choise in
1)
    echo -e "\nSummary:\n"
    sheep -v
    echo
    ;;
2)
    echo -e "\nSummary:\n"
    sheep -v
    qemu-system-x86_64 --version
    echo
    echo ${notes[0]}
    ;;
3)
    echo -e "\nSummary:\n"
    sheep -v
    qemu-system-x86_64 --version
    apt-show-versions zookeeper
    echo
    echo ${notes[1]}
    echo ${notes[0]}
    ;;
esac

# Check ulimit
fix_limit

# Reboot to change ulimit
if [ $reboot_needed -eq 1 ]
then
     confirm "${notes[2]}"
     if [ $? -eq 0 ]
     then
        reboot
        exit
    fi
fi
    
confirm "${question[0]}'"
[ $? -eq 0 ] && $script_dir/assistant.sh

