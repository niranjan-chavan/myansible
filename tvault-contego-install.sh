#!/bin/bash
# Translate the OS version values into common nomenclature
# Sets global ``DISTRO`` from the ``os_*`` values
declare DISTRO
TVAULT_CONTEGO_CONF=/etc/tvault-contego/tvault-contego.conf
ipv6_regex='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
ipv6_nfs_regex='^\[([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}\]$'

function GetOpenStackRelease {
    NOVA_VERSION=`nova-manage version | awk -F. '{print $1}'`
    NOVA_VERSION_QUEEN=`nova-manage version`
    
    if [[ "$NOVA_VERSION" -eq "2016"  ]]; then
        export OPEN_STACK_RELEASE="mitaka"
        export OPEN_STACK_RELEASE_SUB="gtliberty"
    elif [[ "$NOVA_VERSION" -eq "13" ]] && [[ "$NOVA_VERSION" -lt "2000" ]]; then
         export OPEN_STACK_RELEASE="mitaka"
         export OPEN_STACK_RELEASE_SUB="gtliberty"
    elif [[ "$NOVA_VERSION" -gt "2016" ]]; then
         export OPEN_STACK_RELEASE="newton"
         export OPEN_STACK_RELEASE_SUB="gtliberty"
    elif [[ "$NOVA_VERSION" -ge "16" ]] || [[ "$NOVA_VERSION_QUEEN" -eq "0.0.1-3" ]]; then
         export OPEN_STACK_RELEASE="queens"
         export OPEN_STACK_RELEASE_SUB="gtliberty"
    elif [[ "$NOVA_VERSION" -gt "13" ]] && [[ "$NOVA_VERSION" -lt "2000" ]]; then
         export OPEN_STACK_RELEASE="newton"
         export OPEN_STACK_RELEASE_SUB="gtliberty"
    else
        export OPEN_STACK_RELEASE="premitaka"
        export OPEN_STACK_RELEASE_SUB="premitaka"
    fi
}
GetOpenStackRelease

# GetOSVersion
function GetOSVersion {

    # Figure out which vendor we are
    if [[ -x "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release 2>/dev/null) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        os_PACKAGE="rpm"
        if [[ "Debian,Ubuntu,LinuxMint" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        elif [[ "SUSE LINUX" =~ $os_VENDOR ]]; then
            lsb_release -d -s | grep -q openSUSE
            if [[ $? -eq 0 ]]; then
                os_VENDOR="openSUSE"
            fi
        elif [[ $os_VENDOR == "openSUSE project" ]]; then
            os_VENDOR="openSUSE"
        elif [[ $os_VENDOR =~ Red.*Hat ]]; then
            os_VENDOR="Red Hat"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # Red Hat Enterprise Linux Server release 7.0 Beta (Maipo)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        # XenServer release 6.2.0-70446c (xenenterprise)
        # Oracle Linux release 7
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora XenServer; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \([0-9].*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        if [ "$os_VENDOR" = "Red Hat" ] && [[ -r /etc/oracle-release ]]; then
            os_VENDOR=OracleLinux
        fi
        os_PACKAGE="rpm"
    elif [[ -r /etc/SuSE-release ]]; then
        for r in openSUSE "SUSE Linux"; do
            if [[ "$r" = "SUSE Linux" ]]; then
                os_VENDOR="SUSE LINUX"
            else
                os_VENDOR=$r
            fi

            if [[ -n "`grep \"$r\" /etc/SuSE-release`" ]]; then
                os_CODENAME=`grep "CODENAME = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_RELEASE=`grep "VERSION = " /etc/SuSE-release | sed 's:.* = ::g'`
                os_UPDATE=`grep "PATCHLEVEL = " /etc/SuSE-release | sed 's:.* = ::g'`
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    # If lsb_release is not installed, we should be able to detect Debian OS
    elif [[ -f /etc/debian_version ]] && [[ $(cat /proc/version) =~ "Debian" ]]; then
        os_VENDOR="Debian"
        os_PACKAGE="deb"
        os_CODENAME=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $2}')
        os_RELEASE=$(awk '/VERSION_ID=/' /etc/os-release | sed 's/VERSION_ID=//' | sed 's/\"//g')
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}

function GetDistro {
    GetOSVersion
    if [[ "$os_VENDOR" =~ (Ubuntu) || "$os_VENDOR" =~ (Debian) ]]; then
        # 'Everyone' refers to Ubuntu / Debian releases by the code name adjective
        DISTRO=$os_CODENAME
    elif [[ "$os_VENDOR" =~ (Fedora) ]]; then
        # For Fedora, just use 'f' and the release
        DISTRO="f$os_RELEASE"
    elif [[ "$os_VENDOR" =~ (openSUSE) ]]; then
        DISTRO="opensuse-$os_RELEASE"
    elif [[ "$os_VENDOR" =~ (SUSE LINUX) ]]; then
        # For SLE, also use the service pack
        if [[ -z "$os_UPDATE" ]]; then
            DISTRO="sle${os_RELEASE}"
        else
            DISTRO="sle${os_RELEASE}sp${os_UPDATE}"
        fi
    elif [[ "$os_VENDOR" =~ (Red Hat) || \
        "$os_VENDOR" =~ (CentOS) || \
        "$os_VENDOR" =~ (OracleLinux) ]]; then
        # Drop the . release as we assume it's compatible
        DISTRO="rhel${os_RELEASE::1}"
    elif [[ "$os_VENDOR" =~ (XenServer) ]]; then
        DISTRO="xs$os_RELEASE"
    else
        # Catch-all for now is Vendor + Release + Update
        DISTRO="$os_VENDOR-$os_RELEASE.$os_UPDATE"
    fi
    export DISTRO
}

# Utility function for checking machine architecture
# is_arch arch-type
function is_arch {
    [[ "$(uname -m)" == "$1" ]]
}

# Determine if current distribution is an Oracle distribution
# is_oraclelinux
function is_oraclelinux {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "OracleLinux" ]
}


# Determine if current distribution is a Fedora-based distribution
# (Fedora, RHEL, CentOS, etc).
# is_fedora
function is_fedora {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi

    [ "$os_VENDOR" = "Fedora" ] || [ "$os_VENDOR" = "Red Hat" ] || \
        [ "$os_VENDOR" = "CentOS" ] || [ "$os_VENDOR" = "OracleLinux" ]
}


# Determine if current distribution is a SUSE-based distribution
# (openSUSE, SLE).
# is_suse
function is_suse {
    if [[ -z "$os_VENDOR" ]]; then
        GetOSVersion
    fi
    [ "$os_VENDOR" = "openSUSE" ] || [ "$os_VENDOR" = "SUSE LINUX" ] || [ "$os_VENDOR" = "SUSE" ]
}


# Determine if current distribution is an Ubuntu-based distribution
# It will also detect non-Ubuntu but Debian-based distros
# is_ubuntu
function is_ubuntu {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSVersion
    fi
    [ "$os_PACKAGE" = "deb" ]
}

function get_nova_config_files {
cat > /tmp/get_configs.py <<-EOF
import os
import sys
file_name = sys.argv[1]
pids = [pid for pid in os.listdir('/proc') if pid.isdigit()]
config_files = list()
for pid in pids:
    try:
        for ps in open(os.path.join('/proc', pid, 'cmdline'), 'rb'):
            if True in ['nova-compute' in s for s in ps.split('\0')]:
                fields = ps.split('\0')
                for index, value in enumerate(fields):
                    if value == '--config-file':
                        config_files.append(value + '=' + fields[index + 1])
                    elif value.startswith('--config-file='):
                        config_files.append(value)
    except IOError: # proc has already terminated
        continue
if not config_files:
    config_files = '--config-file=' + file_name
else:
    config_files = ' '.join(list(set(config_files)))

print('{}'.format(config_files))

EOF

CONFIG_FILES=$(sudo -u $TVAULT_CONTEGO_EXT_USER python /tmp/get_configs.py $NOVA_CONF_FILE)
CONFIG_FILES="$CONFIG_FILES --config-file=$TVAULT_CONTEGO_CONF"

if [[ -d /etc/nova/nova.conf.d ]]; then
    CONFIG_FILES="$CONFIG_FILES --config-dir=/etc/nova/nova.conf.d"
fi

rm -rf /tmp/get_configs.py
}

# Exit after outputting a message about the distribution not being supported.
# exit_distro_not_supported [optional-string-telling-what-is-missing]
function exit_distro_not_supported {
    if [[ -z "$DISTRO" ]]; then
        GetDistro
    fi

    if [ $# -gt 0 ]; then
        die $LINENO "Support for $DISTRO is incomplete: no support for $@"
    else
        die $LINENO "Support for $DISTRO is incomplete."
    fi
}

# Set an option in an INI file
function ini_get_option() {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local section=$2
    local option=$3
    local remove=$4
    local other=$5
    local line
    line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ p; }" "$file")
    if [ "$other" = "yes" ] && [ "$remove" = "yes" ]; then
       line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*,/ p; }" "$file")
    fi
    #$xtrace
    echo "$line"
    if [ "$remove" = "yes" ] && [ ! -z "$line" ]; then
        grep -v "$line" "$file" > "$file.bak"
        mv "$file.bak" "$file"
    fi
}

# Determinate is the given option present in the INI file
# ini_has_option config-file section option
function ini_has_option() {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local section=$2
    local option=$3
    local ret=$4
    local line

    line=$(sed -ne "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ p; }" "$file")
    #$xtrace
    [ -n "$line" ]

    if [ "$ret" = "yes" ]; then
       if [ -n "$line" ]; then
          echo "0"
       else
           echo "1"
       fi
    fi
}

# iniset config-file section option value
function iniset() {
    local file=$1
    local section=$2
    local option=$3
    local value=$4
    if ! grep -q "^\[$section\]" "$file"; then
        # Add section at the end
        echo -e "\n[$section]" >>"$file"
    fi
    if ! ini_has_option "$file" "$section" "$option"; then
        # Add it
        sed -i -e "/^\[$section\]/ a\\
$option = $value
" "$file"
    else
        # Replace it
        sed -i -e "/^\[$section\]/,/^\[.*\]/ s|^\($option[ \t]*=[ \t]*\).*$|\1$value|" "$file"
    fi
}

# Set a multiple line option in an INI file
# iniset_multiline config-file section option value1 value2 valu3 ...
function iniset_multiline() {
    local file=$1
    local section=$2
    local option=$3
    shift 3
    local values
    for v in $@; do
        # The later sed command inserts each new value in the line next to
        # the section identifier, which causes the values to be inserted in
        # the reverse order. Do a reverse here to keep the original order.
        values="$v ${values}"
    done
    if ! grep -q "^\[$section\]" "$file"; then
        # Add section at the end
        echo -e "\n[$section]" >>"$file"
    else
        # Remove old values
        sed -i -e "/^\[$section\]/,/^\[.*\]/ { /^$option[ \t]*=/ d; }" "$file"
    fi
    # Add new ones
    for v in $values; do
        sed -i -e "/^\[$section\]/ a\\
$option = $v
" "$file"
    done
}


function create_tvault_object_store_service_in_systemd() {
cat > /etc/systemd/system/tvault-object-store.service <<-EOF
[Unit]
Description=Tvault Object Store
After=tvault-contego.service
[Service]
User=$TVAULT_CONTEGO_EXT_USER
Group=$TVAULT_CONTEGO_EXT_USER
Type=simple
LimitNOFILE=500000
LimitNPROC=500000
ExecStart=$TVAULT_CONTEGO_EXT_PYTHON $s3_fuse_file --config-file=$TVAULT_CONTEGO_CONF
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
}

function create_tvault_object_store_service_init() {
cat > /etc/init/tvault-object-store.conf <<-EOF
description "TrilioVault Object Store"
author "TrilioData <info@triliodata.com>"
start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]
respawn
chdir /var/run
pre-start script
    if [ ! -d /var/run/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir /var/run/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/run/$TVAULT_CONTEGO_EXT_USER
    fi
    if [ ! -d /var/lock/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir -p /var/lock/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/lock/$TVAULT_CONTEGO_EXT_USER
    fi
    if [ -f /var/log/nova/tvault-contego.log ]; then
       chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_USER /var/log/nova/tvault-contego.log
    fi
end script
script
    su -c "$TVAULT_CONTEGO_EXT_PYTHON $s3_fuse_file --config-file=$TVAULT_CONTEGO_CONF" $TVAULT_CONTEGO_EXT_USER
end script
EOF
}

function create_tvault_object_store_service_initd() {
cat > /etc/init.d/tvault-object-store <<-EOF
#!/bin/sh
#
# tvault-object-store  OpenStack Nova Compute Extension
#
# chkconfig:   - 98 02
# description: OpenStack Nova Compute Extension To Snapshot Virtual\
#               machines.
### BEGIN INIT INFO
# Provides:
# Required-Start: \$remote_fs \$network \$syslog
# Required-Stop: \$remote_fs \$syslog
# Default-Stop: 0 1 6
# Short-Description: OpenStack Nova Compute Extension
# Description: OpenStack Nova Compute Extension To Snapshot Virtual
#               machines.
### END INIT INFO
. /etc/rc.d/init.d/functions
prog=tvault-object-store
exec=$TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_OBJECT_STORE
pidfile="/var/run/$TVAULT_CONTEGO_EXT_USER/\$prog.pid"
configfiles="--config-file=$TVAULT_CONTEGO_CONF"
[ -e /etc/sysconfig/\$prog ] && . /etc/sysconfig/\$prog
lockfile=/var/lock/subsys/\$prog
start() {
    [ -x \$exec ] || exit 5
    [ -f \$config ] || exit 6
    echo -n \$"Starting \$prog: "
    daemon --user $TVAULT_CONTEGO_EXT_USER --pidfile \$pidfile "\$exec \$configfiles &>/dev/null & echo \\\$! > \$pidfile"
    retval=\$?
    echo
    [ \$retval -eq 0 ] && touch \$lockfile
    return \$retval
}
stop() {
    echo -n \$"Stopping \$prog: "
    killproc -p \$pidfile \$prog
    retval=\$?
    echo
    [ \$retval -eq 0 ] && rm -f \$lockfile
    return \$retval
}
restart() {
    stop
    start
}
reload() {
    restart
}
force_reload() {
    restart
}
rh_status() {
    status -p \$pidfile \$prog
}
rh_status_q() {
    rh_status >/dev/null 2>&1
}
case "\$1" in
    start)
        rh_status_q && exit 0
        \$1
        ;;
    stop)
        rh_status_q || exit 0
        \$1
        ;;
    restart)
        \$1
        ;;
    reload)
        rh_status_q || exit 7
        \$1
        ;;
    force-reload)
        force_reload
        ;;
    status)
        rh_status
        ;;
    condrestart|try-restart)
        rh_status_q || exit 0
        restart
        ;;
    *)
        echo \$"Usage: \$0 {start|stop|status|restart|condrestart|try-restart|reload|force-reload}"
        exit 2
esac
exit \$?
EOF
chmod +x /etc/init.d/tvault-object-store
}

function create_tvault_object_store_service_systemd() {
cat > /usr/lib/systemd/system/tvault-object-store.service <<-EOF
[Unit]
Description=TrilioVault Object Store
[Service]
Type=simple
TimeoutStartSec=0
Restart=always
User=$TVAULT_CONTEGO_EXT_USER
ExecStart=$TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_OBJECT_STORE --config-file=$TVAULT_CONTEGO_CONF
[Install]
WantedBy=multi-user.target
EOF
}

function create_tvault_contego_service_in_systemd() {
if [ "$NFS" = True ]; then
cat > /etc/systemd/system/tvault-contego.service <<-EOF
[Unit]
Description=Tvault contego
After=openstack-nova-compute.service
[Service]
User=$TVAULT_CONTEGO_EXT_USER
Group=$TVAULT_CONTEGO_EXT_USER
LimitNOFILE=65536
MemoryMax=10G
Type=simple
ExecStart=$openstack_python_path $tvault_contego_bin $CONFIG_FILES
TimeoutStopSec=20
KillMode=process
Restart=on-failure
CPUShares=2
[Install]
WantedBy=multi-user.target
EOF
elif [ "$Object_Store" = True ]; then
cat > /etc/systemd/system/tvault-contego.service <<-EOF
[Unit]
Description=Tvault contego
Requires=tvault-object-store.service
[Service]
User=$TVAULT_CONTEGO_EXT_USER
Group=$TVAULT_CONTEGO_EXT_USER
LimitNOFILE=65536
MemoryMax=10G
Type=simple
ExecStart=$openstack_python_path $tvault_contego_bin $CONFIG_FILES
TimeoutStopSec=20
KillMode=process
Restart=on-failure
CPUShares=2
[Install]
WantedBy=multi-user.target
EOF
fi
}

function create_tvault_datamover_service_in_systemd() {
cat > /etc/systemd/system/tvault-datamover-api.service <<-EOF
[Unit]
Description=TrilioData DataMover API service
After=tvault-datamover-api.service

[Service]
User=$TVAULT_CONTEGO_EXT_USER
Group=$TVAULT_CONTEGO_EXT_USER
Type=simple
ExecStart=$openstack_python_path $dmapi_bin
KillMode=process
Restart=on-failure
WorkingDirectory=/var/run

[Install]
WantedBy=multi-user.target
EOF
}

### Upstart ###
function create_tvault_contego_service_init() {
cat > /etc/init/tvault-contego.conf <<-EOF
description "TrilioVault Contego - Openstack Nova Compute Extension"
author "TrilioData <info@triliodata.com>"
start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]
respawn
chdir /var/run
pre-start script
    if [ ! -d /var/run/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir /var/run/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/run/$TVAULT_CONTEGO_EXT_USER
    fi
    if [ ! -d /var/lock/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir -p /var/lock/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/lock/$TVAULT_CONTEGO_EXT_USER
    fi
    if [ -f /var/log/nova/tvault-contego.log ]; then
       chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_USER /var/log/nova/tvault-contego.log
    fi
end script
script
    exec start-stop-daemon --start --chuid $TVAULT_CONTEGO_EXT_USER --exec $python_path $tvault_contego_bin -- $CONFIG_FILES
end script
EOF
}

function create_tvault_datamover_api_service_init() {
cat > /etc/init/tvault-datamover-api.conf <<-EOF
description "TrilioVault Datamover API"
author "TrilioData <info@triliodata.com>"
start on (filesystem and net-device-up IFACE!=lo)
stop on runlevel [016]
respawn
chdir /var/run
pre-start script
    if [ ! -d /var/run/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir /var/run/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/run/$TVAULT_CONTEGO_EXT_USER
    fi
    if [ ! -d /var/lock/$TVAULT_CONTEGO_EXT_USER ]; then
        mkdir -p /var/lock/$TVAULT_CONTEGO_EXT_USER
        chown root:$TVAULT_CONTEGO_EXT_USER /var/lock/$TVAULT_CONTEGO_EXT_USER
    fi
end script
script
    exec start-stop-daemon --start --chuid root --exec $python_path $dmapi_bin
end script
EOF
}

function create_tvault_contego_service_suse() {
cat > /etc/rc.d/tvault-contego <<-EOF
#!/bin/sh

### BEGIN INIT INFO
# Provides:          tvault-contego
# Default-Start:     3 5
# Default-Stop:      0 1 2 6
# Short-Description: Tvault Contego
# Description:       Tvault Contego
### END INIT INFO

DAEMON="contego"
USER="$TVAULT_CONTEGO_EXT_USER"
CONFFILE="$CONFIG_FILES"
RUNDIR="/var/run/$TVAULT_CONTEGO_EXT_USER"

. /etc/rc.status

case "$1" in
    start)
        echo -n "Starting tvault-contego"
        /sbin/startproc -q -s -u $USER $TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_BIN $CONFIG_FILES
        rc_status -v
        ;;
    stop)
        echo -n "Shutting down tvault-contego"
        /sbin/killproc $TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_BIN
        rc_status -v
        ;;
    restart)
        $0 stop
        $0 start
        rc_status
        ;;
    force-reload)
        $0 try-restart
        rc_status
        ;;
    reload)
        echo -n "Reload service tvault-contego"
        rc_failed 3
        rc_status -v
        ;;
    status)
        echo -n "Checking for service tvault-contego"
        /sbin/checkproc $TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_BIN
        rc_status -v
        ;;
    try-restart|condrestart)
        if test "$1" = "condrestart"; then
            echo "${attn} Use try-restart ${done}(LSB)${attn} rather than condrestart ${warn}(RH)${norm}"
        fi
        $0 status
        if test $? = 0; then
            $0 restart
        else
            rc_reset # Not running is not a failure.
        fi
        rc_status # Remember status and be quiet
        ;;
    *)
        echo "Usage: $0 {start|stop|status|try-restart|restart|force-reload|reload}"
        exit 1
        ;;
esac
rc_exit
EOF
chmod +x /etc/rc.d/tvault-contego
}

### Initd ###
function create_tvault_contego_service_initd() {
cat > /etc/init.d/tvault-contego <<-EOF
#!/bin/sh
#
# tvault-contego  OpenStack Nova Compute Extension
#
# chkconfig:   - 98 02
# description: OpenStack Nova Compute Extension To Snapshot Virtual\
#               machines.
### BEGIN INIT INFO
# Provides:
# Required-Start: \$remote_fs \$network \$syslog
# Required-Stop: \$remote_fs \$syslog
# Default-Stop: 0 1 6
# Short-Description: OpenStack Nova Compute Extension
# Description: OpenStack Nova Compute Extension To Snapshot Virtual
#               machines.
### END INIT INFO
. /etc/rc.d/init.d/functions
prog=tvault-contego
exec=$TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_BIN
pidfile="/var/run/$TVAULT_CONTEGO_EXT_USER/\$prog.pid"
configfiles="$CONFIG_FILES"
[ -e /etc/sysconfig/\$prog ] && . /etc/sysconfig/\$prog
lockfile=/var/lock/subsys/\$prog
start() {
    [ -x \$exec ] || exit 5
    [ -f \$config ] || exit 6
    echo -n \$"Starting \$prog: "
    daemon --user $TVAULT_CONTEGO_EXT_USER --pidfile \$pidfile "\$exec \$configfiles &>/dev/null & echo \\\$! > \$pidfile"
    retval=\$?
    echo
    [ \$retval -eq 0 ] && touch \$lockfile
    return \$retval
}
stop() {
    echo -n \$"Stopping \$prog: "
    killproc -p \$pidfile \$prog
    retval=\$?
    echo
    [ \$retval -eq 0 ] && rm -f \$lockfile
    return \$retval
}
restart() {
    stop
    start
}
reload() {
    restart
}
force_reload() {
    restart
}
rh_status() {
    status -p \$pidfile \$prog
}
rh_status_q() {
    rh_status >/dev/null 2>&1
}
case "\$1" in
    start)
        rh_status_q && exit 0
        \$1
        ;;
    stop)
        rh_status_q || exit 0
        \$1
        ;;
    restart)
        \$1
        ;;
    reload)
        rh_status_q || exit 7
        \$1
        ;;
    force-reload)
        force_reload
        ;;
    status)
        rh_status
        ;;
    condrestart|try-restart)
        rh_status_q || exit 0
        restart
        ;;
    *)
        echo \$"Usage: \$0 {start|stop|status|restart|condrestart|try-restart|reload|force-reload}"
        exit 2
esac
exit \$?
EOF
chmod +x /etc/init.d/tvault-contego
}



### Systemd ###
function create_tvault_contego_service_systemd() {
cat > /usr/lib/systemd/system/tvault-contego.service <<-EOF
[Unit]
Description=TrilioVault Contego - Openstack Nova Compute Extension
After=openstack-nova-compute.service
[Service]
Type=notify
NotifyAccess=all
TimeoutStartSec=0
Restart=always
User=$TVAULT_CONTEGO_EXT_USER
ExecStart=$TVAULT_CONTEGO_EXT_PYTHON $TVAULT_CONTEGO_EXT_BIN $CONFIG_FILES
[Install]
WantedBy=multi-user.target
EOF
}

###Function for mount backend#####

function create_contego_conf_nfs() {

NFS_OP="$NFS_OPTIONS"
if [ "$NFS_OPTIONS" == "" ]; then
   NFS_OP="nolock,soft,timeo=180,intr,lookupcache=none"
fi

cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_nfs_export = $NFS_SHARES
vault_storage_nfs_options = $NFS_OP
vault_storage_type = nfs
vault_data_directory_old = /var/triliovault
vault_data_directory = /var/triliovault-mounts
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3

[contego_sys_admin]
helper_command = sudo $privsep_bin_path

[conductor]
use_local = True
EOF

if [ ! -d $VAULT_DATA_DIR ]; then
   mkdir -m 775 -p "$VAULT_DATA_DIR"
   chown $TVAULT_CONTEGO_EXT_USER:"$TVAULT_CONTEGO_EXT_GROUP" "$VAULT_DATA_DIR"
else
    chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $VAULT_DATA_DIR
fi

}

function create_data_directories() {
if [ ! -d $VAULT_DATA_DIR ]; then
   mkdir -m 775 -p $VAULT_DATA_DIR
   chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $VAULT_DATA_DIR
else
    chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $VAULT_DATA_DIR
fi

if [ ! -d $VAULT_DATA_DIR_OLD ]; then
   mkdir -m 775 -p $VAULT_DATA_DIR_OLD
   chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $VAULT_DATA_DIR_OLD
else
     rm -rf $VAULT_DATA_DIR_OLD/*
     chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $VAULT_DATA_DIR_OLD
fi

}


function create_contego_conf_swift() {
cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_type = swift-s
vault_storage_nfs_export = TrilioVault
vault_data_directory_old = $VAULT_DATA_DIR_OLD
vault_data_directory = $VAULT_DATA_DIR
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
vault_swift_auth_url = $VAULT_SWIFT_AUTH_URL
vault_swift_username = $VAULT_SWIFT_USERNAME
vault_swift_password = $VAULT_SWIFT_PASSWORD
vault_swift_auth_version = $VAULT_SWIFT_AUTH_VERSION
vault_swift_domain_id = $VAULT_SWIFT_DOMAIN_ID
vault_swift_domain_name = $VAULT_SWIFT_DOMAIN_NAME
vault_swift_tenant = $VAULT_SWIFT_TENANT
vault_swift_region_name = $VAULT_SWIFT_REGION_NAME

[contego_sys_admin]
helper_command = sudo $privsep_bin_path

[conductor]
use_local = True
EOF

create_data_directories
}

function create_contego_conf_s3_aws() {
signature=$VAULT_S3_SIGNATURE_VERSION
if [ "$VAULT_S3_SIGNATURE_VERSION" == "" ]; then
    signature="default"
fi

cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_type = s3
vault_storage_nfs_export = TrilioVault
vault_data_directory_old = $VAULT_DATA_DIR_OLD
vault_data_directory = $VAULT_DATA_DIR
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
vault_s3_auth_version = DEFAULT
vault_s3_access_key_id = $VAULT_S3_ACCESS_KEY
vault_s3_secret_access_key = $VAULT_S3_SECRET_ACCESS_KEY
vault_s3_region_name = $VAULT_S3_REGION_NAME
vault_s3_bucket = $VAULT_S3_BUCKET
vault_s3_signature_version = $signature
[contego_sys_admin]
helper_command = sudo $privsep_bin_path

[conductor]
use_local = True

EOF

create_data_directories
}

function create_contego_conf_s3_other_compatible() {
cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_type = s3
vault_storage_nfs_export = TrilioVault
vault_data_directory_old = $VAULT_DATA_DIR_OLD
vault_data_directory = $VAULT_DATA_DIR
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
vault_s3_auth_version = DEFAULT
vault_s3_access_key_id = $VAULT_S3_ACCESS_KEY
vault_s3_secret_access_key = $VAULT_S3_SECRET_ACCESS_KEY
vault_s3_region_name = $VAULT_S3_REGION_NAME
vault_s3_bucket = $VAULT_S3_BUCKET
vault_s3_endpoint_url = $VAULT_S3_ENDPOINT_URL
vault_s3_signature_version = $VAULT_S3_SIGNATURE_VERSION
vault_s3_ssl = $VAULT_S3_SECURE

[contego_sys_admin]
helper_command = sudo $privsep_bin_path

[conductor]
use_local = True
EOF

create_data_directories
}

function create_contego_conf_s3_minio() {
cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_type = s3
vault_storage_nfs_export = TrilioVault
vault_data_directory_old = $VAULT_DATA_DIR_OLD
vault_data_directory = $VAULT_DATA_DIR
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
vault_s3_auth_version = DEFAULT
vault_s3_access_key_id = $VAULT_S3_ACCESS_KEY
vault_s3_secret_access_key = $VAULT_S3_SECRET_ACCESS_KEY
vault_s3_region_name = us-east-1
vault_s3_bucket = $VAULT_S3_BUCKET
vault_s3_endpoint_url = $VAULT_S3_ENDPOINT_URL
vault_s3_signature_version = $VAULT_S3_SIGNATURE_VERSION
vault_s3_support_empty_dir = $VAULT_S3_SUPPORT_EMPTY_DIR
vault_s3_ssl = $VAULT_S3_SECURE

[contego_sys_admin]
helper_command = sudo $privsep_helper_file

[conductor]
use_local = True
EOF

create_data_directories
}

function create_contego_conf_s3_other() {
cat > $TVAULT_CONTEGO_CONF <<-EOF
[DEFAULT]
vault_storage_type = s3
vault_storage_nfs_export = TrilioVault
vault_data_directory_old = $VAULT_DATA_DIR_OLD
vault_data_directory = $VAULT_DATA_DIR
log_file = /var/log/nova/tvault-contego.log
debug = False
verbose = True
max_uploads_pending = 3
max_commit_pending = 3
vault_s3_auth_version = DEFAULT
vault_s3_access_key_id = $VAULT_S3_ACCESS_KEY
vault_s3_secret_access_key = $VAULT_S3_SECRET_ACCESS_KEY
vault_s3_region_name = us-east-1
vault_s3_bucket = $VAULT_S3_BUCKET
vault_s3_endpoint_url = $VAULT_S3_ENDPOINT_URL
vault_s3_signature_version = $VAULT_S3_SIGNATURE_VERSION
vault_s3_support_empty_dir = $VAULT_S3_SUPPORT_EMPTY_DIR
vault_s3_ssl = $VAULT_S3_SECURE

[contego_sys_admin]
helper_command = sudo $privsep_helper_file

[conductor]
use_local = True
EOF

create_data_directories
}
##############

function create_contego_logrotate() {
cat > /etc/logrotate.d/tvault-contego <<-EOF
/var/log/nova/tvault-contego.log {
    daily
        missingok
        notifempty
        copytruncate
        size=25M
        rotate 3
        compress
}
EOF
}

function_create_trilio_yum_repo_file() {
cat > /etc/yum.repos.d/trilio.repo <<-EOF
[trilio]
name=Trilio Repository
baseurl=http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/yum-repo/queens/
enabled=1
gpgcheck=0
EOF
#yum update -y
}


function_create_trilio_apt_repo_file() {
cat > /etc/apt/sources.list.d/trilio.list <<-EOF
deb [trusted=yes] https://apt.fury.io/triliodata-3-3/ /
EOF
apt-get update -y
}

function is_nova_read_writable() {
    SHARES_ARRAY=(${NFS_SHARES//,/ })
    for key in "${!SHARES_ARRAY[@]}"
    do
         NFS_SHARE=${SHARES_ARRAY[$key]}
         MOUNT_POINT=`cat /proc/mounts | grep "$NFS_SHARE " | awk '{print $2}'`
         if [[ ! -z $MOUNT_POINT ]] ; then
            if sudo -u $TVAULT_CONTEGO_EXT_USER [ -w $MOUNT_POINT -a -r $MOUNT_POINT ] ; then
                continue
            else
               echo "$TVAULT_CONTEGO_EXT_USER user does not have read or/and write permissions on mount point $MOUNT_POINT, $NFS_SHARE"
               return 1
            fi
         fi
    done

return 0

}

function contego_uninstall() {
    TVAULT_IP="$1"

    swift_stop
    object_store_stop
    if [ -d "$TVAULT_CONTEGO_VIRTENV" ] ; then
       contego_stop
    fi
    rm -rf $TVAULT_CONTEGO_VIRTENV
    rm -rf /etc/logrotate.d/tvault-contego
    DIR=$(dirname "${TVAULT_CONTEGO_CONF}")
    rm -rf "${DIR}"
    rm -rf /var/log/nova/tvault-contego*
    GetDistro
    if [[ "$DISTRO" == "rhel7" ]]; then
        systemctl disable tvault-contego.service
        rm -f /etc/systemd/system/tvault-contego.service
        systemctl daemon-reload
        function_create_trilio_yum_repo_file
        if [[ $python2_version == "True" ]]; then
           yum remove tvault-contego -y
           yum remove puppet-triliovault -y
        elif [[ $python3_version == "True" ]]; then
           yum remove python3-tvault-contego -y
           yum remove puppet-triliovault -y
        fi
    elif is_ubuntu; then
        if [[ "$DISTRO" == "wily" ]] || [[ "$DISTRO" == "xenial" ]] || [["$DISTRO" == "bionic"]]; then
           systemctl disable tvault-contego.service
           rm -f /etc/systemd/system/tvault-contego.service
           systemctl daemon-reload
           apt-get purge contego -y
           if [[ $python2_version == "True" ]]; then
              apt-get purge tvault-contego -y 
           elif [[ $python3_version == "True" ]]; then
              apt-get purge python3-tvault-contego -y
           fi 
        else
             rm -f /etc/init/tvault-contego.conf
             apt-get purge contego -y
             if [[ $python2_version == "True" ]]; then
                apt-get purge tvault-contego -y 
             elif [[ $python3_version == "True" ]]; then
                apt-get purge python3-tvault-contego -y
             fi 
        fi
    elif is_fedora; then
        rm -f /etc/init.d/tvault-contego
    elif is_suse; then
         rm -f /etc/systemd/system/tvault-contego.service
         systemctl daemon-reload
    else
        exit_distro_not_supported "uninstalling tvault-contego"
    fi

    GetDistro
    if [[ "$DISTRO" == "rhel7" ]]; then
        systemctl disable tvault-object-store.service
        if [[ -e /etc/systemd/system/tvault-swift.service ]]; then
            rm -f /etc/systemd/system/tvault-swift.service
        else
            rm -f /etc/systemd/system/tvault-object-store.service
        fi
        systemctl daemon-reload
    elif is_ubuntu; then
        if [[ "$DISTRO" == "wily" ]] || [[ "$DISTRO" == "xenial" ]] || [[ "$DISTRO" == "bionic" ]]; then
            systemctl disable tvault-object-store.service
            if [[ -e /etc/systemd/system/tvault-swift.service ]]; then
                rm -f /etc/systemd/system/tvault-swift.service
            else
                rm -f /etc/systemd/system/tvault-object-store.service
            fi
            systemctl daemon-reload
        else
            if [[ -e /etc/init/tvault-swift.conf ]]; then
                rm -f /etc/init/tvault-swift.conf
            else
                rm -f /etc/init/tvault-object-store.conf
            fi
        fi
    elif is_fedora; then
        if [[ -e /etc/init.d/tvault-swift ]]; then
            rm -f /etc/init.d/tvault-swift
        else
            rm -f /etc/init.d/tvault-object-store
        fi
    elif is_suse; then
        if [[ -e /usr/lib/systemd/system/tvault-swift.service ]]; then
            rm -f /usr/lib/systemd/system/tvault-swift.service
        else
            rm -f /usr/lib/systemd/system/tvault-object-store.service
        fi
        systemctl daemon-reload
    else
        exit_distro_not_supported "uninstalling object-store"
    fi

}

function datamover_api_uninstall() {
   TVAULT_IP="$1"

   GetDistro
   if [[ "$DISTRO" == "rhel7" ]]; then
      echo "Uninstalling datamover service on RHEL 7 or CentOS 7"
      function_create_trilio_yum_repo_file
      if [[ $python2_version == "True" ]]; then
         yum remove dmapi -y
      elif [[ $python3_version == "True" ]]; then
         yum remove python3-dmapi -y
      fi
 
      systemctl disable tvault-datamover-api.service
      systemctl stop tvault-datamover-api.service
   elif is_ubuntu; then
      echo "Uninstalling tvault-datamover service on" $DISTRO
      if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then
          if [[ $python2_version == "True" ]]; then
             apt-get purge dmapi -y
          elif [[ $python3_version == "True" ]]; then
             apt-get purge python3-dmapi -y
          fi

          systemctl disable tvault-datamover-api.service
          systemctl stop tvault-datamover-api.service
      else
          if [[ $python2_version == "True" ]]; then
             apt-get purge dmapi -y
          elif [[ $python3_version == "True" ]]; then
             apt-get purge python3-dmapi -y
          fi
      fi

   elif is_suse; then
      echo "Uninstalling tvault-datamover service on" $DISTRO
      systemctl stop tvault-datamover-api.service
   else
        exit_distro_not_supported "Uninstalling tvault datamover api"
   fi
}

#Function to start contego service
function contego_start() {
   GetDistro
   is_running=`ps -ef | grep tvault-contego | grep -v grep | wc -l`
   if [ $is_running -lt 3 ]; then
      echo -e "starting tvault-contego service\n"
      if [[ "$DISTRO" == "rhel7" ]]; then
        systemctl daemon-reload
        systemctl start tvault-contego.service
      elif is_ubuntu; then
        sudo service tvault-contego start
      elif is_fedora; then
        service tvault-contego start
      elif is_suse; then
           systemctl daemon-reload
           systemctl start tvault-contego.service
      else
        echo "Distribution not supported, exiting \n"
        exit 1
      fi
   fi
}
##Function to stop contego service
function contego_stop() {
  GetDistro
      echo -e "stopping tvault-contego service\n"
      if [[ "$DISTRO" == "rhel7" ]]; then
            systemctl status tvault-contego | grep "active (running)"
            if [[ $? -eq 0 ]]; then
               systemctl stop tvault-contego.service
            fi
      elif is_ubuntu; then
        # Check for "running" because 14.04 returns "start/running"
        # and 16.04 returns "active (running)"
            service tvault-contego status | grep "running"
            if [[ $? -eq 0 ]]; then
               service tvault-contego stop
            fi
      elif is_fedora; then
            service tvault-contego status | grep "running"
            if [[ $? -eq 0 ]]; then
               service tvault-contego stop
            fi
      elif is_suse; then
           systemctl status tvault-contego | grep "active (running)"
           if [[ $? -eq 0 ]]; then
               systemctl stop tvault-contego.service
           fi
      else
        echo "Distribution not supported, exiting \n"
        exit 1
      fi
  unmount_nfs_backup
}

function object_store_start() {
   GetDistro
   is_running=`ps -ef | grep tvault-object-store | grep -v grep | wc -l`
   if [ $is_running -lt 3 ]; then
      echo -e "starting tvault-object-store service\n"
      if [[ "$DISTRO" == "rhel7" ]]; then
        systemctl daemon-reload
        systemctl start tvault-object-store.service
      elif is_ubuntu; then
           service tvault-object-store start
      elif is_fedora; then
        service tvault-object-store start
      elif is_suse; then
           systemctl daemon-reload
           systemctl start tvault-object-store.service
      else
        echo "Distribution not supported, exiting \n"
        exit 1
      fi
   fi
}

function swift_stop() {
  GetDistro
      echo -e "stopping tvault-swift service\n"
      if [[ "$DISTRO" == "rhel7" ]]; then
            systemctl status tvault-swift | grep "active (running)"
            if [[ $? -eq 0 ]]; then
               systemctl stop tvault-swift.service
               systemctl daemon-reload
            fi
      elif is_ubuntu; then
            service tvault-swift status | grep "start/running"
            if [[ $? -eq 0 ]]; then
               service tvault-swift stop
            fi
      elif is_fedora; then
            service tvault-swift status | grep "running"
            if [[ $? -eq 0 ]]; then
               service tvault-swift stop
            fi
      elif is_suse; then
           systemctl status tvault-swift | grep "active (running)"
           if [[ $? -eq 0 ]]; then
               systemctl stop tvault-swift.service
               systemctl daemon-reload
           fi
      else
        echo "Distribution not supported, exiting \n"
        exit 1
      fi
}

function object_store_stop() {
  GetDistro
      echo -e "stopping tvault-object-store service\n"
      if [[ "$DISTRO" == "rhel7" ]]; then
            systemctl status tvault-object-store | grep "active (running)"
            if [[ $? -eq 0 ]]; then
               systemctl stop tvault-object-store.service
               systemctl daemon-reload
            fi
      elif is_ubuntu; then
            service tvault-object-store status | grep "start/running"
            if [[ $? -eq 0 ]]; then
               service tvault-object-store stop
            fi
      elif is_fedora; then
            service tvault-object-store status | grep "running"
            if [[ $? -eq 0 ]]; then
               service tvault-object-store stop
            fi
      elif is_suse; then
           systemctl status tvault-object-store | grep "active (running)"
           if [[ $? -eq 0 ]]; then
               systemctl stop tvault-object-store.service
               systemctl daemon-reload
           fi
      else
        echo "Distribution not supported, exiting \n"
        exit 1
      fi
}

function unmount_nfs_backup() {
    dirs=($(find $VAULT_DATA_DIR -maxdepth 1 -type d))
    for d in "${dirs[@]}"; do
        if mount | grep $d > /dev/null; then
           umount -f $d
        fi
    done
    dirs=($(find $VAULT_DATA_DIR_OLD -maxdepth 1 -type d))
    for d in "${dirs[@]}"; do
        if mount | grep $d > /dev/null; then
           if [[  ${d} == *"tmpfs"* ]]; then
              umount -f $d
           fi
        fi
    done
}


create_filter_file()
{
cat >$1  <<EOL
[Filters]
# mount and unmout filter
mount: CommandFilter, mount, root
umount: CommandFilter, umount, root
rescan-scsi-bus.sh: CommandFilter, /usr/bin/rescan-scsi-bus.sh, root
qemu-img: CommandFilter, qemu-img, root
EOL
}

update_nova_sudoers()
{
echo "calling fuction for nova"
nova_file=$(find /etc/sudoers.d -name "nova*" | grep -Ew  'nova|nova_sudoers')
if [[ -z "$nova_file" ]]; then
   echo "We are creating nova sudoersfile"
   echo "Defaults:nova !requiretty" >> /etc/sudoers.d/nova
   echo "nova ALL = (root) NOPASSWD: /home/tvault/.virtenv/bin/privsep-helper *" >> /etc/sudoers.d/nova
else
   grep -qxF 'nova ALL = (root) NOPASSWD: /home/tvault/.virtenv/bin/privsep-helper *' $nova_file || echo 'nova ALL = (root) NOPASSWD: /home/tvault/.virtenv/bin/privsep-helper *' >> $nova_file
fi
}

check_virtual_environment()
{
   if [[ $python2_version == "True" ]]; then
      APT_PYTHON_VERSION="python"
   elif [[ $python3_version == "True" ]]; then
      APT_PYTHON_VERSION="python3"
   fi
   ENV_PATH=$($APT_PYTHON_VERSION -c "import sys; print(sys.prefix)")
   if [ "$ENV_PATH" == "/usr" ]; then
      echo "no need to change bin path"
      EXTRA_APT_VAR=""
   else
      EXTRA_APT_VAR="--no-install-recommends"
      echo "We are creating trilio.pth inside the virtual environment"
      echo $(/usr/bin/$APT_PYTHON_VERSION -c "import site, os; from os import path; p = [path_dir for path_dir in site.getsitepackages() if path.exists(os.path.join(path_dir, 'contego'))]; print(p[0]+'/')") > $($APT_PYTHON_VERSION -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")/trilio.pth
      echo "trilio.pth file created inside the virtual environment"
   fi
}

remove_trilio_filter()
{
 echo "start function remove trilio filter"

 if [ -f $NOVA_TRILIO_FILTERS_FILE ]; then
    echo "removing trilio.filters file $NOVA_TRILIO_FILTERS_FILE  "
    rm -rf $NOVA_TRILIO_FILTERS_FILE
 fi

 if [[ $python2_version == "True" ]]; then
      APT_PYTHON_VERSION="python"
 elif [[ $python3_version == "True" ]]; then
      APT_PYTHON_VERSION="python3"
 fi
 PTH_FILE=$($APT_PYTHON_VERSION -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")
 if [ -f $PTH_FILE/trilio.pth ]; then
 echo "this is the $PTH_FILE/trilio.pth"
 echo "removing trilio.pth file"
 rm -rf $PTH_FILE/trilio.pth
 fi

}

update_nova_sudoers_with_privsep()
{
echo "calling fuction for nova"
nova_file=$(find /etc/sudoers.d -name "nova*" | grep -Ew  'nova|nova_sudoers')
if [[ -z "$nova_file" ]]; then
   echo "We are creating nova sudoersfile"
   echo "Defaults:nova !requiretty" >> /etc/sudoers.d/nova
   echo "nova ALL = (root) NOPASSWD: " $privsep_bin_path "*" >> /etc/sudoers.d/nova
else
if grep -q $privsep_bin_path $nova_file;
 then
     echo "string aleready exist in nova sudoers with privsep value '$privsep_bin_path':"
 else
     echo "nova ALL = (root) NOPASSWD:" $privsep_bin_path "*" >> $nova_file
     fi
fi
}

###MAIN BLOCK
meto=`echo $1`
if [ -n "$2" ]; then
  auto=`echo $2`
fi

####### Nova Configuration Files ########################################
NOVA_CONF_FILE=/etc/nova/nova.conf
#Nova distribution specific configuration file path
NOVA_DIST_CONF_FILE=/usr/share/nova/nova-dist.conf
###############################
TVAULT_CONTEGO_EXT_USER=nova
TVAULT_CONTEGO_EXT_GROUP=nova
VAULT_DATA_DIR=/var/triliovault-mounts
VAULT_DATA_DIR_OLD=/var/triliovault
#Value of TVAULT_CONTEGO_VERSION will be replaced with latest build version during build creation.
TVAULT_CONTEGO_VERSION=4.0.78
declare TVAULT_CONTEGO_VIRTENV
TVAULT_CONTEGO_VIRTENV=/home/tvault
TVAULT_CONTEGO_VIRTENV_PATH="$TVAULT_CONTEGO_VIRTENV/.virtenv"
privsep_helper_file=/home/tvault/.virtenv/bin/privsep-helper
dmapi_log=/var/log/dmapi
python_path=`which python`
python3_path=`which python3`
HTTP_PORT=8085
PYPI_PORT=8081
###############################


if [ "$meto" == "--help" ];then
    echo -e "1. ./tvault-contego-install.sh --install --file <Answers file path> : install tvault-contego using answers file.\n"
    echo -e "2. ./tvault-contego-install.sh --install : install tvault-contego in interactive way.\n"
    echo -e "3. ./tvault-contego-install.sh --help : tvault-contego installation help.\n"
    echo -e "4. ./tvault-contego-install.sh --uninstall : uninstall tvault-contego. \n"
    echo -e "5. ./tvault-contego-install.sh --uninstall --file <Answers file path> : uninstall tvault-contego using answers file.\n"
    echo -e "6. ./tvault-contego-install.sh --start : Starts tvault-contego service and enables start-on-boot \n"
    echo -e "7. ./tvault-contego-install.sh --stop : Stops tvault-contego service and disables start-on-boot \n"
    echo -e "8. ./tvault-contego-install.sh --add <new nfsshare>: Adds a new share and restars tvault-contego service\n"
    exit 1
elif [ "$meto" == "--install" -a "$auto" == "--file" ];then
###configuration file
    if [ -z "$3" ]; then
       echo -e "Please provide path of tvault contego answers file\nYou can refer help using --help option\n"
       exit 1
    fi
    answers_file=`echo $3`
    if [ ! -f $answers_file ]; then
       echo -e "Answers file path that you provided does not exists\nPlease provide correct path.\n"
       exit 1
    fi
    source $answers_file
    if echo "$IP_ADDRESS" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
                VALID_IP_ADDRESS="$(echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255')"
                if [ -z "$VALID_IP_ADDRESS" ]
                then
                    echo "Please specify valid Tvault appliance IP address"
                    exit 1
                fi
        elif [[ $IP_ADDRESS =~ $ipv6_regex ]];
        then
                IP_ADDRESS="["$IP_ADDRESS"]"
                PYPI_PORT=8082
    else
        echo "Please specify valid Tvault appliance IP address"
        exit 1
    fi

    if [ "$openstack_python_version" == "python2" ]; then
        openstack_python_path=$python_path
        python2_version="True";python3_version="False"       
    elif [ "$openstack_python_version" == "python3" ]; then
        openstack_python_path=$python3_path
        python3_version="True";python2_version="False"     
    else
        echo -e "\nPlease enter correct python version"      
    fi

    if [ "$controller" = True ] ; then
        TVAULT_DATAMOVER_API="True";TVAULT_CONTEGO_EXT="False"
cat > /tmp/datamover_url <<-EOF
[DEFAULT]
dmapi_link_prefix = $datamover_url
dmapi_enabled_ssl_apis = $dmapi_enabled_ssl_apis

[wsgi]
ssl_cert_file = $ssl_cert_file
ssl_key_file = $ssl_key_file
EOF

    elif [ "$compute" = True ]; then
        if [ "$NOVA_COMPUTE_FILTERS_FILE" == "/usr/share/nova/rootwrap/compute.filters" ]; then
             echo "Adding trilio filter"
             create_filter_file /usr/share/nova/rootwrap/trilio.filters
             if [ "$NOVA_SUDOERS" == "require" ]; then
                echo "updating nova sudoers"
                update_nova_sudoers
             fi
        elif [ "$NOVA_COMPUTE_FILTERS_FILE" == "/etc/nova/rootwrap.d/compute.filters" ]; then
             echo "Adding trilio filter"
             create_filter_file /etc/nova/rootwrap.d/trilio.filters
             if [ "$NOVA_SUDOERS" == "require" ]; then
                echo "updating nova sudoers"
                update_nova_sudoers
             fi
        elif [ -f  $NOVA_COMPUTE_FILTERS_FILE ];then
             echo "Adding trilio filter"
             FILTER_PATH=$(echo $NOVA_COMPUTE_FILTERS_FILE | sed 's/compute.filters//')
             create_filter_file ${FILTER_PATH}trilio.filters
             if [ "$NOVA_SUDOERS" == "require" ]; then
                echo "updating nova sudoers"
                update_nova_sudoers
             fi
        fi
        TVAULT_CONTEGO_EXT="True";TVAULT_DATAMOVER_API="False"
        if  [ "$NFS" = True ]; then
        if ! type "showmount" > /dev/null; then
           echo "Error: Please install nfs-common packages and try install again"
           exit 1
        fi

        string="$NFS_SHARES"
        set -f
        array=(${string//,/ })
        for i in "${!array[@]}"
            do
                           nfstcp="tcp"
               NFS_SHARE_PATH="${array[i]}"
               nfsip=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print $1 }')
               if echo "$nfsip" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
                   then
                    nfstcp="tcp"
               elif [[ $nfsip =~ $ipv6_nfs_regex ]];
                   then
                   nfsip=${nfsip:1:${#nfsip}-2}
                   nfstcp="tcp6"
               else
                   echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
                   continue
               fi
                           nfspath=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print "/"$2 }')
               if [[ ! -z $nfsip || ! -z $nfspath ]];then
                   out=`rpcinfo -T $nfstcp $nfsip 100005 3`
                   if [[ $? -eq 0 ]];then
                       out=`showmount -e $nfsip --no-headers`
                       exports=(${out// / })
                       found=0
                       for j in "${!exports[@]}"
                           do
                              if [[ "${exports[j]}" == "$nfspath" ]];then
                                  found=1
                                  let "found_total++"
                                  break
                              fi
                           done
                       if [[ $found -eq 0 ]];then
                           echo "$nfspath @ $nfsip is NOT in the export lists"
                           out= `mount $NFS_SHARE_PATH $VAULT_DATA_DIR`
                           tp=${NFS_SHARE_PATH%/}
                           out=`df | grep "^$tp "`
                           if [[ $? -eq 0 ]];then
                               out= `umount -f $VAULT_DATA_DIR`
                               found=1
                               let "found_total++"
                           else
                                echo "$nfspath @ $nfsip is NOT valid"
                           fi
                           continue
                       fi
                   else
                        echo "Cannot find mountd @ $nfsip"
                        continue
                   fi
               else
                    echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
                    continue
               fi
            done
        if [[ "$found_total" != "${#array[@]}" ]];then
           echo "Please correct NFS lists to continue installing"
           exit 1
        fi
        else ## [ "$NFS" != True ] So assume Swift or S3 object Store
            Object_Store=True
        fi
    fi
elif [ "$meto" == "--install" ];then

    while true;do
        echo -n  "Enter your Tvault appliance IP : ";read IP_ADDRESS
        if echo "$IP_ADDRESS" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
                VALID_IP_ADDRESS="$(echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255')"
                if [ -z "$VALID_IP_ADDRESS" ]
                then
                    echo "Please specify valid Tvault appliance IP address"
                    continue
                else
                    echo "Tvault appliance IP : $IP_ADDRESS"
                    break
                fi
                elif [[ $IP_ADDRESS =~ $ipv6_regex ]];
                then
                echo "Tvault appliance IP : $IP_ADDRESS"
                IP_ADDRESS="["$IP_ADDRESS"]"
                PYPI_PORT=8082
                break
        else
                echo "Please specify valid Tvault appliance IP address"
                continue
        fi
    done
    echo -e "\nTriliovault services uses same python version where openstack services are running"
    echo -e "\nSelect the python version which openstack services are using (1/2) :"
    while true;do
        echo "1. Python 2"
        echo "2. Python 3"
        echo -n "Option : " ; read python_opt
        if [ "$python_opt" == 1 ]; then
            openstack_python_path=$python_path
            python2_version="True";python3_version="False"
            break
        elif [ "$python_opt" == 2 ]; then
            openstack_python_path=$python3_path
            python3_version="True";python2_version="False"
            break
        else
            echo -e "\nPlease select valid option (1/2) :"
            continue
        fi
    done
    echo -e "\nSelect the node which you are using (1/2) :"
    while true;do
        echo "1. Controller"
        echo "2. Compute"
        echo -n "Option : " ; read opt
        if [ "$opt" == 1 ]; then
            TVAULT_DATAMOVER_API="True";TVAULT_CONTEGO_EXT="False"
            break
        elif [ "$opt" == 2 ]; then
            TVAULT_CONTEGO_EXT="True";TVAULT_DATAMOVER_API="False"
            break
        else
            echo -e "\nPlease select valid option (1/2) :"
            continue
        fi
    done
    ssl_cert_file=""
    ssl_key_file=""
    dmapi_enabled_ssl_apis=""
    echo -e "\n"
    if [[ "$TVAULT_DATAMOVER_API" == "True" ]]; then
        echo -n "Please enter datamover endpoint url in format : http://<controller_ip>:<port>" ; read datamover_url
        if [[ $datamover_url == http*:*:* ]]; then
            :
        else
            echo -n "datamover url should be in format : http://<controller_ip>:<port>"
            exit 0
        fi
        if [[ $datamover_url = *"https"* ]]; then
            echo -n "    Path for ssl_cert_file: "; read ssl_cert_file
            echo -n "    Path for ssl_key_file: "; read ssl_key_file
            dmapi_enabled_ssl_apis="dmapi"
        fi

cat > /tmp/datamover_url <<-EOF
[DEFAULT]
dmapi_link_prefix = $datamover_url
dmapi_enabled_ssl_apis = $dmapi_enabled_ssl_apis

[wsgi]
ssl_cert_file = $ssl_cert_file
ssl_key_file = $ssl_key_file
EOF
    elif [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
        echo "Select compute filter file path (1/2/3):"
        while true;do
            echo "1. RHEL based [Default: /usr/share/nova/rootwrap/compute.filters]"
            echo "2. Debian Based [Default: /etc/nova/rootwrap.d/compute.filters]"
            echo "3. Other"
            echo -n "Choice : " ; read value
            if [ "$value" == 1 ]; then
                NOVA_COMPUTE_FILTERS_FILE="/usr/share/nova/rootwrap/compute.filters"
                create_filter_file /usr/share/nova/rootwrap/trilio.filters
                echo "TrilioVault needs to add the following statement in nova sudoers file"
                echo "nova ALL = (root) NOPASSWD: /home/tvault/.virtenv/bin/privsep-helper *"
                echo "These changes require for Datamover, Otherwise Datamover will not work"
                echo "Are you sure? Please select your option (1/2)"
                while true;do
                    echo "1. Yes"
                    echo "2. No"
                    echo -n "Choice : " ; read data
                    if [ "$data" == 2 ]; then
                         echo "You selected No for updating nova sudoers file, exiting the Contego installation, Please Select Yes"
                         exit 1;
                    elif [ "$data" == 1 ]; then
                         update_nova_sudoers   
                         break
                    else
                         echo "please select correct option"
                         exit 1 ;
                    fi
                done
                break
            elif [ "$value" == 2 ]; then
                NOVA_COMPUTE_FILTERS_FILE="/etc/nova/rootwrap.d/compute.filters"
                create_filter_file /etc/nova/rootwrap.d/trilio.filters
                echo "Need to add the following statement in nova sudoers file"
                echo "nova ALL = (root) NOPASSWD: /home/tvault/.virtenv/bin/privsep-helper *"
                echo "These changes require for Datamover, Otherwise Datamover will not work"
                echo "Are you sure? Please select your option"
                while true;do
                    echo "1. Yes"
                    echo "2. No"
                    echo -n "Choice : " ; read data
                    if [ "$data" == 2 ]; then
                         echo "You selected No for updating nova sudoers file, exiting the Contego installation, Please Select Yes"
                         exit 1;
                    elif [ "$data" == 1 ]; then
                         update_nova_sudoers    
                         break
                    else
                         echo "please select correct option"
                         exit 1 ;
                    fi
                done
                break
            elif [ "$value" == 3 ]; then
                while true;do
                     echo -n "Enter Enter NOVA_COMPUTE_FILTERS_FILE path : "; read NOVA_COMPUTE_FILTERS_FILE
                     if [ -z  $NOVA_COMPUTE_FILTERS_FILE ];then
                        echo
                        echo "No path specified, please specify valid path"
                        continue
                     elif [ -f  $NOVA_COMPUTE_FILTERS_FILE ];then
                        echo -e "\n"
                        FILTER_PATH=$(echo $NOVA_COMPUTE_FILTERS_FILE | sed 's/compute.filters//')
                        create_filter_file ${FILTER_PATH}trilio.filters
                        break
                     else
                        continue
                     fi
                done
                break
             fi
        done
      fi
        ########Collect details about nfs, swift, or s3 storage###
        if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
            found_total=0
            swift_stop
            object_store_stop
            contego_stop
            echo "Select the type of backup media (1/2/3) :"
            while true;do
            echo "1. NFS"
            echo "2. Swift"
            echo "3. S3"
        echo -n "Option : " ; read optmed
            if [ "$optmed" == 1 ]; then
               if ! type "showmount" > /dev/null; then
                  echo "Error: Please install nfs-common packages and try install again"
                  exit 1
               fi
               while true;do
                     echo -n "Enter NFS shares (Format: [IP:/path/to/nfs_share,IP:/path/to/nfs_share,...]): "; read NFS_SHARES
                     echo
                     nfsip=$(echo "$NFS_SHARES" | awk -F':/' '{print $1 }')
                     if [[ ! -z $nfsip ]];then
                        NFS=True
                        string="$NFS_SHARES"
                        set -f
                        array=(${string//,/ })
                        for i in "${!array[@]}"
                            do
                              nfstcp="tcp"
                              NFS_SHARE_PATH="${array[i]}"
                              nfsip=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print $1 }')
                              if echo "$nfsip" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
                                  then
                                   nfstcp="tcp"
                              elif [[ $nfsip =~ $ipv6_nfs_regex ]];
                                  then
                                   nfsip=${nfsip:1:${#nfsip}-2}
                                   nfstcp="tcp6"
                              else
                                   echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
                                   continue
                              fi
                              nfspath=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print "/"$2 }')
                              if [[ ! -z $nfsip || ! -z $nfspath ]];then
                                 out=`rpcinfo -T $nfstcp $nfsip 100005 3`
                                 if [[ $? -eq 0 ]];then
                                    out=`showmount -e $nfsip --no-headers`
                                    exports=(${out// / })
                                    found=0
                                    for j in "${!exports[@]}"
                                        do
                                           if [[ "${exports[j]}" == "$nfspath" ]];then
                                              found=1
                                              let "found_total++"
                                              break
                                           fi
                                        done
                                    if [[ $found -eq 0 ]];then
                                       echo "$nfspath @ $nfsip is NOT in the export lists"
                                       out= `mount $NFS_SHARE_PATH $VAULT_DATA_DIR`
                                       tp=${NFS_SHARE_PATH%/}
                                       out=`df | grep "^$tp "`
                                       if [[ $? -eq 0 ]];then
                                          let "found_total++"
                                          out= `umount -f $VAULT_DATA_DIR`
                                          found=1
                                       else
                                            echo "$nfspath @ $nfsip is NOT valid"
                                       fi
                                       continue
                                    fi
                                 else
                                     echo "Cannot find mountd @ $nfsip"
                                     continue
                                 fi
                              else
                                  echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
                                  continue
                              fi
                            done
                            break
                     else
                         echo "$NFS_SHARES path not specified. Please specify nfs share path"
                     fi
               done
               if [[ "$found_total" != "${#array[@]}" ]];then
                   echo "Please correct NFS lists to continue installing"
                   exit 1
               fi
               echo -n "Enter NFS share options, If enter blank then will take default options (Format: [nolock,soft,timeo=180,intr,lookupcache=none]): "; read NFS_OPTIONS
               echo
            elif [ "$optmed" == 2 ]; then
                  echo "Selected Swift as backup media."
                  Swift=True
          Object_Store=True
                  echo "Select the type of swift (1/2) :"
                  while true;do
                  echo "1. KEYSTONE V2"
                  echo "2. KEYSTONE V3"
                  echo "3. TEMPAUTH"
                  echo -n "Option : " ; read optmed1
                  if [ "$optmed1" == 1 ]; then
                     while true;do
                           VAULT_SWIFT_AUTH_VERSION="KEYSTONEV2"
                           if [[ $OPEN_STACK_RELEASE_SUB == "mitaka" ]] || [[ $(ini_has_option $NOVA_CONF_FILE neutron auth_url yes) == "0" ]];then
                              VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron auth_url)
                              IFS==
                              set $VAULT_SWIFT_AUTH_URL
                              VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
                              VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron project_name)
                              set $VAULT_SWIFT_TENANT
                              VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
                           else
                               VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron admin_auth_url)
                               IFS==
                               set $VAULT_SWIFT_AUTH_URL
                               VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
                               VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron admin_tenant_name)
                               set $VAULT_SWIFT_TENANT
                               VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
                           fi
                           if [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]]; then
                              VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v2.0"
                           fi
                           VAULT_SWIFT_USERNAME="triliovault"
                           VAULT_SWIFT_PASSWORD="52T8FVYZJse"
                           VAULT_SWIFT_DOMAIN_ID=""
                           VAULT_SWIFT_DOMAIN_NAME=""
                           break
                     done
                  elif [ "$optmed1" == 2 ]; then
                       while true;do
                             VAULT_SWIFT_AUTH_VERSION="KEYSTONEV3"
                             if [[ $OPEN_STACK_RELEASE_SUB == "mitaka" ]] || [[ $(ini_has_option $NOVA_CONF_FILE neutron auth_url yes) == "0" ]];then
                                VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron auth_url)
                                IFS==
                                set $VAULT_SWIFT_AUTH_URL
                                VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
                                if [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]]; then
                                     VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v3"
                                fi
                                VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron project_name)
                                set $VAULT_SWIFT_TENANT
                                VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
                                VAULT_SWIFT_USERNAME="triliovault"
                                VAULT_SWIFT_PASSWORD="52T8FVYZJse"
                                VAULT_SWIFT_DOMAIN_ID=""
                                VAULT_SWIFT_DOMAIN_NAME=""
                                if [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_id yes) == "0" ]; then
                                   VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_id)
                                elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_id yes) == "0" ]; then
                                     VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_id)
                                elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_name yes) == "0" ]; then
                                    VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_name)
                                elif [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_name yes) == "0" ]; then
                                    VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_name)
                                fi
                                if [ ! -z "$VAULT_SWIFT_DOMAIN_ID" ]; then
                                   set $VAULT_SWIFT_DOMAIN_ID
                                   VAULT_SWIFT_DOMAIN_ID=$(tr -d ' ' <<< "$2")
                                fi
                                if [ ! -z "$VAULT_SWIFT_DOMAIN_NAME" ]; then
                                   set $VAULT_SWIFT_DOMAIN_NAME
                                   VAULT_SWIFT_DOMAIN_NAME=$(tr -d ' ' <<< "$2")
                                fi
                             else
                                 VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron admin_auth_url)
                                 IFS==
                                 set $VAULT_SWIFT_AUTH_URL
                                 VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
                                 if [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]]; then
                                     VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v3"
                                 fi
                                 VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron admin_tenant_name)
                                 set $VAULT_SWIFT_TENANT
                                 VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
                                 VAULT_SWIFT_USERNAME="triliovault"
                                 VAULT_SWIFT_PASSWORD="52T8FVYZJse"
                                 VAULT_SWIFT_DOMAIN_ID=""
                                 VAULT_SWIFT_DOMAIN_NAME=""
                                 if [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_id yes) == "0" ]; then
                                    VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_id)
                                 elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_id yes) == "0" ]; then
                                     VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_id)
                                 elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_name yes) == "0" ]; then
                                    VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_name)
                                 elif [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_name yes) == "0" ]; then
                                    VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_name)
                                 fi
                                 if [ ! -z "$VAULT_SWIFT_DOMAIN_ID" ]; then
                                    set $VAULT_SWIFT_DOMAIN_ID
                                    VAULT_SWIFT_DOMAIN_ID=$(tr -d ' ' <<< "$2")
                                 fi
                                 if [ ! -z "$VAULT_SWIFT_DOMAIN_NAME" ]; then
                                    set $VAULT_SWIFT_DOMAIN_NAME
                                    VAULT_SWIFT_DOMAIN_NAME=$(tr -d ' ' <<< "$2")
                                 fi
                             fi
                             break
                       done
                  elif [ "$optmed1" == 3 ]; then
                       while true;do
                             VAULT_SWIFT_AUTH_VERSION="TEMPAUTH"
                             echo -n "Enter swift auth url: "; read VAULT_SWIFT_AUTH_URL
                             echo
                             echo -n "Enter swift username: "; read VAULT_SWIFT_USERNAME
                             echo
                             echo -n "Enter swift password: "; read -s VAULT_SWIFT_PASSWORD
                             echo
                             status=$(curl -i -o /dev/null --silent --write-out '%{http_code}\n' -H "X-Auth-User: $VAULT_SWIFT_USERNAME" -H \
                                     "X-Auth-Key: $VAULT_SWIFT_PASSWORD" $VAULT_SWIFT_AUTH_URL)
                             if [ "$status" != 200 ] && [ "$status" != 201 ]; then
                                echo "Please enter correct swift credentials"
                                exit 1
                             fi
                             VAULT_SWIFT_TENANT=""
                             VAULT_SWIFT_DOMAIN_ID=""
                             VAULT_SWIFT_DOMAIN_NAME=""
                             break
                       done
                  else
                      continue
                  fi
                  break
                  done
            elif [ "$optmed" == 3 ]; then
                echo "Selected S3 as backup media."
                S3=True
                Object_Store=True
                while true; do
                    echo "Select the S3 profile (1/2/3) :"
                    echo "1. Amazon S3"
                    echo "2. Other S3 compatible storage"
                    echo -n "Option : " ; read opts3type
                    echo -n "Enter S3 access key: "; read VAULT_S3_ACCESS_KEY
                    echo
                    echo -n "Enter S3 secret key: "; read VAULT_S3_SECRET_ACCESS_KEY
                    echo
                    echo -n "Enter S3 bucket: "; read VAULT_S3_BUCKET
                    echo
                    if [ "$opts3type" == 1 ]; then
                        Amazon=True
                        echo -n "Enter S3 region: "; read VAULT_S3_REGION_NAME
                        echo
                        echo -n "Enter vault signature version (if enter blank then it will take 'default' as default value): "; read VAULT_S3_SIGNATURE_VERSION
                        echo
                        break
                    elif [ "$opts3type" == 2 ]; then
                        other_S3_compatible_storage=True
                        echo -n "Enter S3 region: "; read VAULT_S3_REGION_NAME
                        echo
                        echo -n "Enter S3 Endpoint URL: "; read VAULT_S3_ENDPOINT_URL
                        echo
                        echo -n "Use SSL (True/False): "; read VAULT_S3_SECURE
                        echo
                        echo -n "Enter vault signature version "; read VAULT_S3_SIGNATURE_VERSION
                        echo
                        break
                    else
                        continue
                    fi
                    break
                done
     else
                continue
            fi
               break
            done
            VAULT_SWIFT_REGION_NAME="RegionOne"
            if [ $(ini_has_option $NOVA_CONF_FILE neutron region_name yes) == "0" ]; then
                 VAULT_SWIFT_REGION_NAME=$(ini_get_option $NOVA_CONF_FILE neutron region_name)
                 if [ ! -z "$VAULT_SWIFT_REGION_NAME" ]; then
                       set $VAULT_SWIFT_REGION_NAME
                       VAULT_SWIFT_REGION_NAME=$(tr -d ' ' <<< "$2")
                 fi
            fi
        fi
elif [ "$meto" == "--start" ]; then
     contego_start
     if [ "$NFS" = True ]; then
        is_nova_read_writable
     fi
     if [ "$Swift" = True ]; then
        swift_start
     fi
     exit $?
elif [ "$meto" == "--stop" ];then
     if [ "$Swift" = True ]; then
        swift_stop
     fi
     contego_stop
     exit $?
elif [ "$meto" == "--uninstall" -a "$auto" == "--file" ];then
###configuration file
    if [ -z "$3" ]; then
       echo -e "Please provide path of tvault contego answers file\nYou can refer help using --help option\n"
       exit 1
    fi
    answers_file=`echo $3`
    if [ ! -f $answers_file ]; then
       echo -e "Answers file path that you provided does not exists\nPlease provide correct path.\n"
       exit 1
    fi
    source $answers_file
    if echo "$IP_ADDRESS" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
                VALID_IP_ADDRESS="$(echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255')"
                if [ -z "$VALID_IP_ADDRESS" ]
                then
                    echo "Please specify valid Tvault appliance IP address"
                    exit 1
                fi
        elif [[ $IP_ADDRESS =~ $ipv6_regex ]];
        then
                IP_ADDRESS="["$IP_ADDRESS"]"
                PYPI_PORT=8082
    else
        echo "Please specify valid Tvault appliance IP address"
        exit 1
    fi
    if [ "$openstack_python_version" == "python2" ]; then
        openstack_python_path=$python_path
        python2_version="True";python3_version="False"       
    elif [ "$openstack_python_version" == "python3" ]; then
        openstack_python_path=$python3_path
        python3_version="True";python2_version="False"     
    else
        echo -e "\nPlease enter correct python version"      
    fi

    if [ "$controller" = True ] ; then
        TVAULT_DATAMOVER_API="True";TVAULT_CONTEGO_EXT="False"

    elif [ "$compute" = True ]; then
        TVAULT_CONTEGO_EXT="True";TVAULT_DATAMOVER_API="False"
    fi
    if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
       FILTER_PATH=$(echo $NOVA_COMPUTE_FILTERS_FILE | sed 's/compute.filters//')
       NOVA_TRILIO_FILTERS_FILE=${FILTER_PATH}trilio.filters
       contego_uninstall $IP_ADDRESS
       remove_trilio_filter
    elif [[ "$TVAULT_DATAMOVER_API" == "True" ]]; then
       datamover_api_uninstall $IP_ADDRESS
    fi
    echo -e "Uninstall completed\n"
    exit 0
elif [ "$meto" == "--uninstall" ];then
    while true;do
        echo -n  "Enter your Tvault appliance IP : ";read IP_ADDRESS
        if echo "$IP_ADDRESS" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
                VALID_IP_ADDRESS="$(echo $IP_ADDRESS | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255')"
                if [ -z "$VALID_IP_ADDRESS" ]
                then
                    echo "Please specify valid Tvault appliance IP address"
                    continue
                else
                    echo "Tvault appliance IP : $IP_ADDRESS"
                    break
                fi
                elif [[ $IP_ADDRESS =~ $ipv6_regex ]];
                then
                echo "Tvault appliance IP : $IP_ADDRESS"
                IP_ADDRESS="["$IP_ADDRESS"]"
                PYPI_PORT=8082
                break
        else
                echo "Please specify valid Tvault appliance IP address"
                continue
        fi
    done
    TVAULT_APPLIANCE_NODE=$IP_ADDRESS
    echo -e "\nTriliovault services uses same python version where openstack services are running"
    echo -e "\nSelect the python version which openstack services are using (1/2) :"
    while true;do
        echo "1. Python 2"
        echo "2. Python 3"
        echo -n "Option : " ; read python_opt
        if [ "$python_opt" == 1 ]; then
            openstack_python_path=$python_path
            python2_version="True";python3_version="False"
            break
        elif [ "$python_opt" == 2 ]; then
            openstack_python_path=$python3_path
            python3_version="True";python2_version="False"
            break
        else
            echo -e "\nPlease select valid option (1/2) :"
            continue
        fi
    done
    echo -e "\nSelect the node type (1/2) :"
    while true;do
        echo "1. Controller"
        echo "2. Compute"
        echo -n "Option : " ; read opt
        if [ "$opt" == 1 ]; then
            TVAULT_DATAMOVER_API="True";TVAULT_CONTEGO_EXT="False"
            break
        elif [ "$opt" == 2 ]; then
            TVAULT_CONTEGO_EXT="True";TVAULT_DATAMOVER_API="False"
            break
        else
            echo -e "\nPlease select valid option (1/2) :"
            continue
        fi
    done
    echo -e "\n"
    if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
       echo "Select compute filter file path (1/2/3):"
        while true;do
            echo "1. RHEL based [Default: /usr/share/nova/rootwrap/compute.filters]"
            echo "2. Debian Based [Default: /etc/nova/rootwrap.d/compute.filters]"
            echo "3. Other"
            echo -n "Choice : " ; read value
            if [ "$value" == 1 ]; then
               NOVA_COMPUTE_FILTERS_FILE="/usr/share/nova/rootwrap/compute.filters"
               NOVA_TRILIO_FILTERS_FILE="/usr/share/nova/rootwrap/trilio.filters"
            elif [ "$value" == 2 ]; then
               NOVA_COMPUTE_FILTERS_FILE="/etc/nova/rootwrap.d/compute.filters"
               NOVA_TRILIO_FILTERS_FILE="/etc/nova/rootwrap.d/trilio.filters"
            elif [ "$value" == 3 ]; then
               while true;do
                     echo -n "Enter Enter NOVA_COMPUTE_FILTERS_FILE path : "; read NOVA_COMPUTE_FILTERS_FILE
                     if [ -z  $NOVA_COMPUTE_FILTERS_FILE ];then
                        echo
                        echo "No path specified, please specify valid path"
                        continue
                     elif [ -f  $NOVA_COMPUTE_FILTERS_FILE ];then
                        echo -e "\n"
                        FILTER_PATH=$(echo $NOVA_COMPUTE_FILTERS_FILE | sed 's/compute.filters//')
                        NOVA_TRILIO_FILTERS_FILE=${FILTER_PATH}trilio.filters
                        break
                     else
                        continue
                     fi
               done
            fi
            break
        done
       contego_uninstall $IP_ADDRESS
       remove_trilio_filter
    elif [[ "$TVAULT_DATAMOVER_API" == "True" ]]; then
       datamover_api_uninstall $IP_ADDRESS
    fi
    echo -e "Uninstall completed\n"
    exit 0
elif [ "$meto" == "--add" ];then
    if [ -z "$auto" ]; then
       echo -e "Please provide nfs share to add\n"
       exit 1
    fi
    NFS_SHARE_PATH="$auto"
        nfstcp="tcp6"
        nfsip=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print $1 }')
    if echo "$nfsip" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
         nfstcp="tcp"
    elif [[ $nfsip =~ $ipv6_nfs_regex ]];
        then
         nfsip=${nfsip:1:${#nfsip}-2}
         nfstcp="tcp6"
    else
         echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
         continue
    fi
    nfspath=$(echo "$NFS_SHARE_PATH" | awk -F':/' '{print "/"$2 }')
    if [[ ! -z $nfsip || ! -z $nfspath ]];then
        out=`rpcinfo -T $nfstcp $nfsip 100005 3`
        if [[ $? -eq 0 ]];then
            out=`showmount -e $nfsip --no-headers`
            exports=(${out// / })
            found=0
            for j in "${!exports[@]}"
            do
                if [[ "${exports[j]}" == "$nfspath" ]];then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]];then
                echo "$nfspath @ $nfsip is NOT in the export lists. Please check the nfsshare name and try again"
                out= `mount $NFS_SHARE_PATH $VAULT_DATA_DIR`
                tp=${NFS_SHARE_PATH%/}
                out=`df | grep "^$tp "`
                if [[ $? -eq 0 ]];then
                   out= `umount -f $VAULT_DATA_DIR`
                   found=1
                   break
                else
                     echo "$nfspath @ $nfsip is NOT valid"
                     exit 1
                fi
            fi
        else
            echo "Cannot find mountd @ $nfsip. Please check the nfsshare name and try again"
            exit 1
        fi
    else
       echo "$NFS_SHARE_PATH is not a valid NFS path specified. Please specify nfs share path"
       exit 1
    fi
    # make sure that nfs share is valid
    exports=$(ini_get_option $TVAULT_CONTEGO_CONF DEFAULT vault_storage_nfs_export)
    if [[ ${exports} == *"${auto}"* ]];then
       echo "$auto is already part of nfs shares"
       exit 1
    fi
    str=$exports
    IFS==
    set $str
    exps=$(tr -d ' ' <<< "$2")
    exps=$exps,$auto
    iniset $TVAULT_CONTEGO_CONF DEFAULT vault_storage_nfs_export $exps
    contego_stop
    contego_start
else
    echo -e "Invalid option provided, Please refer help of this script using --help option \n"
    echo -e "1. ./tvault-contego-install.sh --install --file <Answers file path> : install tvault-contego using answers file.\n"
    echo -e "2. ./tvault-contego-install.sh --install : install tvault-contego in interactive way.\n"
    echo -e "3. ./tvault-contego-install.sh --help : tvault-contego installation help.\n"
    echo -e "4. ./tvault-contego-install.sh --uninstall : uninstall tvault-contego. \n"
    echo -e "5. ./tvault-contego-install.sh --uninstall --file <Answers file path> : uninstall tvault-contego using answers file.\n"
    echo -e "6. ./tvault-contego-install.sh --start : Starts tvault-contego service and enables start-on-boot \n"
    echo -e "7. ./tvault-contego-install.sh --stop : Stops tvault-contego service and disables start-on-boot \n"
    exit 1
fi

#####check version of virsh greater than 1.2.8
if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
    virsh_v=$(virsh -v)
        #echo $virsh_v
        diga=`echo "$virsh_v" | awk -F'.' '{print $1 "" }'`
        digb=`echo "$virsh_v" | awk -F'.' '{print $2 "" }'`
        digc=`echo "$virsh_v" | awk -F'.' '{print $3 "" }'`

        if [ $diga -eq 1 ];then
                if [ $digb -eq 2 ];then
                           if [ $digc -gt 7 ];then
                                echo "Virsh version found $virsh_v :condition satisfied"
                           elif [ $digc -le 7 ];then
                                echo "ERROR :virsh version found $virsh_v which is below expected 1.2.8, please upgrade virsh and try again."
                                exit 1
                            fi
                elif [[ $digb -le 2 ]]; then
                             echo "ERROR :virsh version found $virsh_v which is below expected 1.2.8, please upgrade virsh and try again."
                             exit 1
       elif [ $digb -gt 2 ];then
                           echo "Virsh version found $virsh_v :condition satisfied"
                fi
       elif [ $diga -gt 1 ];then
                echo "Virsh version found $virsh_v :condition satisfied"
       fi
fi

######
####### IP Address of Trilio Vault Appliance ############################
TVAULT_APPLIANCE_NODE=$IP_ADDRESS

#Nova compute.filters file path
#Uncomment following line as per the OS distribution, you can edit the path as per your nova configuration
###For RHEL systems
#NOVA_COMPUTE_FILTERS_FILE=/usr/share/nova/rootwrap/compute.filters

###For Debian systems
#NOVA_COMPUTE_FILTERS_FILE=/etc/nova/rootwrap.d/compute.filters

####### OpenStack Controller Node: Set  as True #######
#TVAULT_DATAMOVER_API=$valone

####### OpenStack Compute Node: Set TVAULT_DATAMOVER_API as True ##########
#TVAULT_CONTEGO_EXT=$valtwo
#TVAULT_CONTEGO_EXT_USER=nova

#VAULT_STORAGE_TYPE=nfs
#VAULT_DATA_DIR=/var/triliovault-mounts

####### MISC ############################################################
#Uncomment following line as per the OS distribution
####For RHEL systems
#TVAULT_CONTEGO_EXT_BIN=/usr/bin/tvault-contego

###For Debian systems
#TVAULT_CONTEGO_EXT_BIN=/usr/local/bin/tvault-contego

# Distro Functions
# ================

# Determine OS Vendor, Release and Update
# Tested with OS/X, Ubuntu, RedHat, CentOS, Fedora
# Returns results in global variables:
# ``os_VENDOR`` - vendor name: ``Ubuntu``, ``Fedora``, etc
# ``os_RELEASE`` - major release: ``14.04`` (Ubuntu), ``20`` (Fedora)
# ``os_UPDATE`` - update: ex. the ``5`` in ``RHEL6.5``
# ``os_PACKAGE`` - package type: ``deb`` or ``rpm``
# ``os_CODENAME`` - vendor's codename for release: ``snow leopard``, ``trusty``
os_VENDOR=""
os_RELEASE=""
os_UPDATE=""
os_PACKAGE=""
os_CODENAME=""



##Install block

if [ ! -f $NOVA_CONF_FILE ]; then
    echo "Nova configuration file '"$NOVA_CONF_FILE"' not found."
    exit 1
fi

if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
    if [ ! -f $NOVA_COMPUTE_FILTERS_FILE ]; then
        echo "Nova compute filters file '"$NOVA_COMPUTE_FILTERS_FILE"' not found."
        exit 1
    fi
fi

############



####if ceentos check qemu-img-rhev,qemu-kvm-common,qemu-kvm-rhev

: '
if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
        #chos=$(echo `lsb_release -i -s`)
        GetOSVersion
        if [[ "$os_VENDOR" == "CentOS" ]] || [[ "$os_VENDOR" == "Red Hat" ]];then
                paka=$(echo `rpm -qa qemu-img-rhev | wc -l`)
                pakb=$(echo `rpm -qa qemu-kvm-common-rhev | wc -l`)
                pakc=$(echo `rpm -qa qemu-kvm-rhev | wc -l`)
                pakd=$(echo `rpm -qa qemu-kvm-tools-rhev | wc -l`)
                        if [[ $paka -gt 0  &&  $pakb -gt 0 &&  $pakc -gt 0 ]];then
                        echo -n
                        else
                        echo "ERROR :please make sure you have install qemu-img-rhev,qemu-kvm-common,qemu-kvm-rhev  package"
                        #exit 1
                        fi
        fi
fi
'

###Add nova user to qemu, disk and kvm##
if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
GetOSVersion
        if [[ "$os_VENDOR" == "CentOS" ]] || [[ "$os_VENDOR" == "Red Hat" ]];then
                usermod -a -G disk $TVAULT_CONTEGO_EXT_USER
                usermod -a -G kvm $TVAULT_CONTEGO_EXT_USER
                usermod -a -G qemu $TVAULT_CONTEGO_EXT_USER

        elif [[ "$os_VENDOR" == "Ubuntu" ]];then
                usermod -a -G  kvm $TVAULT_CONTEGO_EXT_USER
                usermod -a -G disk $TVAULT_CONTEGO_EXT_USER
        fi
fi

############

if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then

   if [[ -z "$NFS_SHARES" ]];then
       if [[ "$NFS" == "True" ]]; then
        echo "NFS_SHARES are not defined, please define it in answers file"
        exit 0
       fi
   fi
   if [[ "$Swift" == "True" ]]; then
      NFS=False
      VAULT_SWIFT_DOMAIN_NAME=""
      if [[ -z $VAULT_SWIFT_AUTH_VERSION ]]; then
         echo "Please define swift auth version"
         exit 0
      fi
      if [[ "$VAULT_SWIFT_AUTH_VERSION" == "KEYSTONEV2" ]]; then
         VAULT_SWIFT_AUTH_VERSION="KEYSTONE"
         if [[ $OPEN_STACK_RELEASE_SUB == "mitaka" ]] || [[ $(ini_has_option $NOVA_CONF_FILE neutron auth_url yes) == "0" ]];then
            VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron auth_url)
            IFS==
            set $VAULT_SWIFT_AUTH_URL
            VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
            VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron project_name)
            set $VAULT_SWIFT_TENANT
            VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
         else
             VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron admin_auth_url)
             IFS==
             set $VAULT_SWIFT_AUTH_URL
             VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
             VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron admin_tenant_name)
             set $VAULT_SWIFT_TENANT
             VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
         fi
         if [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]]; then
              VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v2.0"
         fi
         VAULT_SWIFT_USERNAME="triliovault"
         VAULT_SWIFT_PASSWORD="52T8FVYZJse"
         VAULT_SWIFT_DOMAIN_ID=""
      elif [[ "$VAULT_SWIFT_AUTH_VERSION" == "KEYSTONEV3" ]]; then
           VAULT_SWIFT_AUTH_VERSION="KEYSTONE"
           if [[ $OPEN_STACK_RELEASE_SUB == "mitaka" ]] || [[ $(ini_has_option $NOVA_CONF_FILE neutron auth_url yes) == "0" ]];then
              VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron auth_url)
              IFS==
              set $VAULT_SWIFT_AUTH_URL
              VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
              if [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]]; then
                     VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v3"
              fi
              VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron project_name)
              set $VAULT_SWIFT_TENANT
              VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
              VAULT_SWIFT_USERNAME="triliovault"
              VAULT_SWIFT_PASSWORD="52T8FVYZJse"
              if [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_id yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_id)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_id yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_id)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_name yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_name)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_name yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_name)
              fi
              if [ ! -z "$VAULT_SWIFT_DOMAIN_ID" ]; then
                 set $VAULT_SWIFT_DOMAIN_ID
                 VAULT_SWIFT_DOMAIN_ID=$(tr -d ' ' <<< "$2")
              fi
              if [ ! -z "$VAULT_SWIFT_DOMAIN_NAME" ]; then
                 set $VAULT_SWIFT_DOMAIN_NAME
                 VAULT_SWIFT_DOMAIN_NAME=$(tr -d ' ' <<< "$2")
              fi
           else
              VAULT_SWIFT_AUTH_URL=$(ini_get_option $NOVA_CONF_FILE neutron admin_auth_url)
              IFS==
              set $VAULT_SWIFT_AUTH_URL
              VAULT_SWIFT_AUTH_URL=$(tr -d ' ' <<< "$2")
              if [[  ${VAULT_SWIFT_AUTH_URL} != *"v3"* ]] && [[  ${VAULT_SWIFT_AUTH_URL} != *"v2.0"* ]]; then
                     VAULT_SWIFT_AUTH_URL="${VAULT_SWIFT_AUTH_URL}/v3"
              fi
              VAULT_SWIFT_TENANT=$(ini_get_option $NOVA_CONF_FILE neutron admin_tenant_name)
              set $VAULT_SWIFT_TENANT
              VAULT_SWIFT_TENANT=$(tr -d ' ' <<< "$2")
              VAULT_SWIFT_USERNAME="triliovault"
              VAULT_SWIFT_PASSWORD="52T8FVYZJse"
              if [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_id yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_id)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_id yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_ID=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_id)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron project_domain_name yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron project_domain_name)
              elif [ $(ini_has_option $NOVA_CONF_FILE neutron user_domain_name yes) == "0" ]; then
                 VAULT_SWIFT_DOMAIN_NAME=$(ini_get_option $NOVA_CONF_FILE neutron user_domain_name)
              fi
              if [ ! -z "$VAULT_SWIFT_DOMAIN_ID" ]; then
                 set $VAULT_SWIFT_DOMAIN_ID
                 VAULT_SWIFT_DOMAIN_ID=$(tr -d ' ' <<< "$2")
              fi
              if [ ! -z "$VAULT_SWIFT_DOMAIN_NAME" ]; then
                 set $VAULT_SWIFT_DOMAIN_NAME
                 VAULT_SWIFT_DOMAIN_NAME=$(tr -d ' ' <<< "$2")
              fi
           fi
      elif [[ "$VAULT_SWIFT_AUTH_VERSION" == "TEMPAUTH" ]]; then
           status=$(curl -i -o /dev/null --silent --write-out '%{http_code}\n' -H "X-Auth-User: $VAULT_SWIFT_USERNAME" -H \
                                     "X-Auth-Key: $VAULT_SWIFT_PASSWORD" $VAULT_SWIFT_AUTH_URL)
           if [ "$status" != 200 ] && [ "$status" != 201 ]; then
              echo "Please enter correct swift credentials"
              exit 0
           fi
      else
          echo "Please specify correct value for auth version"
          exit 0
      fi
   fi
   PIP_INS=`pip --version || true`
   if [[ $PIP_INS == pip* ]];then
       CONTEGO_VERSION_INSTALLED=`pip list | grep tvault-contego || true`
       if [[  ${CONTEGO_VERSION_INSTALLED} == "tvault-contego "* ]]; then
          pip uninstall tvault-contego -y
       fi
   else
       easy_install --no-deps http://$TVAULT_APPLIANCE_NODE:$PYPI_PORT/packages/pip-7.1.2.tar.gz
       CONTEGO_VERSION_INSTALLED=`pip list  | grep tvault-contego || true`
       if [[  ${CONTEGO_VERSION_INSTALLED} == "tvault-contego "* ]]; then
          pip uninstall tvault-contego -y
       fi
       pip uninstall pip -y
   fi

   if [ ! -d /usr/lib64 ]; then
      ln -s /usr/lib /usr/lib64
   fi
   mkdir -p "$TVAULT_CONTEGO_VIRTENV"
   GetDistro
   echo "python 2 version " $python2_version
   if [[ "$DISTRO" == "rhel7" ]]; then
      echo "installing datamover service on RHEL 7 or CentOS 7"
      function_create_trilio_yum_repo_file
      if [[ $python2_version == "True" ]]; then
         yum install puppet-triliovault -y
         yum install tvault-contego -y
      elif [[ $python3_version == "True" ]]; then         
         yum install puppet-triliovault -y
         yum install python3-tvault-contego -y
      fi
   elif is_ubuntu; then
      echo "installing tvault-datamover service on" $DISTRO
      if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then
          curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/tvault-contego-extension_${TVAULT_CONTEGO_VERSION}_all.deb
          apt-get install ./tvault-contego-extension_${TVAULT_CONTEGO_VERSION}_all.deb -y 
          rm -rf ./tvault-contego-extension_${TVAULT_CONTEGO_VERSION}_all.deb
          if [[ $python2_version == "True" ]]; then
             curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb
             apt-get install ./tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb -y $EXTRA_APT_VAR
             rm -rf tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb
          elif [[ $python3_version == "True" ]]; then
             curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/python3-tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb
             apt-get install ./python3-tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb -y $EXTRA_APT_VAR
             rm -rf python3-tvault-contego_${TVAULT_CONTEGO_VERSION}_all.deb
             
          fi
      fi
   fi
   echo "Removing Contego from virtual environment"
   rm -rf /home/tvault/.virtenv/lib/python2.7/site-packages/contego
   echo "creating symlink of contego inside the virtual environment"
      if [[ $python2_version == "True" ]]; then
         check=$(python -c "import contego;print contego.__path__[0]")
         ln -s $check  /home/tvault/.virtenv/lib/python2.7/site-packages/contego
      elif [[ $python3_version == "True" ]]; then
         check=$(python3 -c "import contego; print(contego.__path__[0])")
         ln -s $check  /home/tvault/.virtenv/lib/python2.7/site-packages/contego
      fi
   echo "symlink creation done"

   tvault_contego_bin=$(which tvault-contego)
   echo "current working directory " $(pwd)
   
   if [[ "$DISTRO" == "rhel7" ]]; then
      echo "get tvault-contego version installed on RHEL 7 or CentOS 7"    
      if [[ $python2_version == "True" ]]; then
         CONTEGO_VERSION_INSTALLED=$(yum list installed | grep tvault-contego | awk '{print $2}' | awk -F'-' '{print $1}')
      elif [[ $python3_version == "True" ]]; then
         CONTEGO_VERSION_INSTALLED=$(yum list installed | grep python3-tvault-contego | awk '{print $2}' | awk -F'-' '{print $1}')
      fi
   elif is_ubuntu; then
      echo "installing tvault-datamover service on" $DISTRO
      if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then        
          if [[ $python2_version == "True" ]]; then
             CONTEGO_VERSION_INSTALLED=$(apt list --installed | grep tvault-contego | awk '{print $2}' | head -n 1)
          elif [[ $python3_version == "True" ]]; then
             CONTEGO_VERSION_INSTALLED=$(apt list --installed | grep python3-tvault-contego | awk '{print $2}' | head -n 1)
          fi
      fi
   fi
   echo "contego version installed" $CONTEGO_VERSION_INSTALLED
   echo "tvault contego verison" $TVAULT_CONTEGO_VERSION
   check_virtual_environment
   rm -rf tvault-contego-virtenv.tar.gz
   if [ "$TVAULT_CONTEGO_VERSION" != "$CONTEGO_VERSION_INSTALLED" ]; then
        echo -e "Problem encountered installing correct version of script\nretry by uninstalling script\n"
        exit 1
   fi   
   chown -R "$TVAULT_CONTEGO_EXT_USER":"$TVAULT_CONTEGO_EXT_USER" "$TVAULT_CONTEGO_VIRTENV"
   if [[ ! -d /var/log/nova ]]; then
        mkdir -p /var/log/nova
   fi
   chown $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP /var/log/nova

   privsep_bin_path=$(which privsep-helper)
   update_nova_sudoers_with_privsep

fi

dmapi="dmapi"
if [[ "$TVAULT_DATAMOVER_API" == "True" ]]; then
   echo "installing datmover-api packages"
   GetDistro

   if [[ "$DISTRO" == "rhel7" ]]; then
      echo "installing datamover service on RHEL 7 or CentOS 7"
      function_create_trilio_yum_repo_file
      #call to populate conf binary file
      #yum install dmapi -y
      if [[ $python2_version == "True" ]]; then
          yum install dmapi -y
      elif [[ $python3_version == "True" ]]; then
             yum install python3-dmapi -y
      fi
      chown -R $TVAULT_CONTEGO_EXT_USER:$TVAULT_CONTEGO_EXT_GROUP $dmapi_log
      dmapi_bin=$(which dmapi-api)
      populate-conf
      create_tvault_datamover_service_in_systemd
      systemctl daemon-reload
      systemctl enable tvault-datamover-api.service
      systemctl restart tvault-datamover-api.service
   elif is_ubuntu; then
      echo "installing tvault-datamover service on" $DISTRO
      if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then
          if [[ $python2_version == "True" ]]; then              
	      curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
              apt-get install ./dmapi_${TVAULT_CONTEGO_VERSION}_all.deb -y
              rm -rf ./dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
          elif [[ $python3_version == "True" ]]; then
	      curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
              apt-get install ./python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb -y
              rm -rf ./python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb

          fi  
          dmapi_bin=$(which dmapi-api)
          #call to populate conf binary file
          populate-conf
          #create_tvault_datamover_service_in_systemd
          systemctl restart tvault-datamover-api.service
      else
          if [[ $python2_version == "True" ]]; then
              curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
              apt-get install ./dmapi_${TVAULT_CONTEGO_VERSION}_all.deb -y
              rm -rf ./dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
          elif [[ $python3_version == "True" ]]; then
              curl -Og6 http://$TVAULT_APPLIANCE_NODE:$HTTP_PORT/deb-repo/deb-repo/python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
              apt-get install ./python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb -y
              rm -rf ./python3-dmapi_${TVAULT_CONTEGO_VERSION}_all.deb
          fi  
          #call to populate conf binary file
          dmapi_bin=$(which dmapi-api)
          populate-conf
          systemctl restart tvault-datamover-api.service
      fi
   elif is_suse; then
      #function_create_trilio_yum_repo_file
      #yum install dmapi -y
      #call to populate conf binary file
      #populate-conf
      echo "installing tvault-datamover service on" $DISTRO
      create_tvault_datamover_service_in_systemd
      systemctl daemon-reload
      systemctl enable tvault-datamover-api.service
      systemctl restart tvault-datamover-api.service
   else
        exit_distro_not_supported "installing tvault-contego"
   fi
   rm -rf /tmp/datamover_url
fi

TVAULT_CONTEGO_EXT_PYTHON="$TVAULT_CONTEGO_VIRTENV_PATH/bin/python"
TVAULT_CONTEGO_EXT_OBJECT_STORE=
TVAULT_CONTEGO_EXT_BACKEND_TYPE=
TVAULT_CONTEGO_EXT_SWIFT="$TVAULT_CONTEGO_VIRTENV_PATH/lib/python2.7/site-packages/contego/nova/extension/driver/vaultfuse.py"
TVAULT_CONTEGO_EXT_S3="$TVAULT_CONTEGO_VIRTENV_PATH/lib/python2.7/site-packages/contego/nova/extension/driver/s3vaultfuse.py"

if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
    TVAULT_CONTEGO_EXT_BIN=$(which tvault-contego)
    if [ ! -f $TVAULT_CONTEGO_EXT_BIN ]; then
        echo "nova extension tvault contego binary file '"$TVAULT_CONTEGO_EXT_BIN"' not found."
        exit 1
    fi
fi

if [[ "$TVAULT_CONTEGO_EXT" == "True" ]]; then
    echo "configuring nova compute extension"
    #iniset $NOVA_CONF_FILE DEFAULT compute_driver libvirt.LibvirtDriver
    ini_get_option "$NOVA_COMPUTE_FILTERS_FILE" "Filters" "qemu-img: EnvFilter" "yes" "yes"
    #grep -q -F 'qemu-img: EnvFilter, env, root, LC_ALL=, LANG=, qemu-img, root' $NOVA_COMPUTE_FILTERS_FILE || echo 'qemu-img: EnvFilter, env, root, LC_ALL=, LANG=, qemu-img, root' >> $NOVA_COMPUTE_FILTERS_FILE
    #grep -q -F 'rm: CommandFilter, rm, root' $NOVA_COMPUTE_FILTERS_FILE || echo 'rm: CommandFilter, rm, root' >> $NOVA_COMPUTE_FILTERS_FILE


    if [ ! -f $TVAULT_CONTEGO_CONF ]; then
        echo "creating contego.conf"
        mkdir -p /etc/tvault-contego
    fi
    if [ "$NFS" = True ]; then
        create_contego_conf_nfs
        echo "Snapshot will be stored in $VAULT_DATA_DIR"
    elif [ "$Swift" = True ]; then
         create_contego_conf_swift
    elif [ "$S3" = True ]; then
        if [ "$Amazon" = True ]; then
            create_contego_conf_s3_aws
        elif [ "$other_S3_compatible_storage" = True ]; then
            create_contego_conf_s3_other_compatible
        fi
    fi

    create_contego_logrotate

    get_nova_config_files

    : '
    CONFIG_FILES1=""
    for file in $NOVA_DIST_CONF_FILE $NOVA_CONF_FILE $TVAULT_CONTEGO_CONF ; do
        test -r $file && CONFIG_FILES1="$CONFIG_FILES1 --config-file=$file"
    done
    '

    GetDistro
    if [[ "$DISTRO" == "rhel7" ]]; then
        echo "installing nova extension tvault-contego on RHEL 7 or CentOS 7"
        create_tvault_contego_service_in_systemd
        systemctl daemon-reload
        systemctl enable tvault-contego.service
        contego_start
        sleep 15
        contego_start
    elif is_ubuntu; then
        echo "installing nova extension tvault-contego on" $DISTRO
        if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then
            create_tvault_contego_service_in_systemd
            systemctl daemon-reload
            systemctl enable tvault-contego.service
            contego_start
            sleep 15
            contego_start
        else
            create_tvault_contego_service_init
        fi
    elif is_fedora; then
        echo "installing nova extension tvault-contego on" $DISTRO
        create_tvault_contego_service_initd
        chkconfig tvault-contego on
    elif is_suse; then
         echo "installing nova extension tvault-contego on" $DISTRO
         create_tvault_contego_service_in_systemd
         systemctl daemon-reload
         systemctl enable tvault-contego.service
         contego_start
         sleep 15
         contego_start
    else
        exit_distro_not_supported "installing tvault-contego"
    fi

    if [ "$Object_Store" = True ]; then
        s3_fuse_file=$TVAULT_CONTEGO_EXT_S3
        if [ "$S3" = True ]; then
            TVAULT_CONTEGO_EXT_OBJECT_STORE=$TVAULT_CONTEGO_EXT_S3
        else
            TVAULT_CONTEGO_EXT_OBJECT_STORE=$TVAULT_CONTEGO_EXT_SWIFT
        fi
       GetDistro
       if [[ "$DISTRO" == "rhel7" ]]; then
          echo "installing tvault-object-store layer on RHEL 7 or CentOS 7"
          create_tvault_object_store_service_in_systemd
          systemctl daemon-reload
          systemctl enable tvault-object-store.service
       elif is_ubuntu; then
            echo "installing tvault-object-store layer on" $DISTRO
            if [[ "$os_CODENAME" == "wily" ]] || [[ "$os_CODENAME" == "xenial" ]] || [[ "$os_CODENAME" == "bionic" ]]; then
               create_tvault_object_store_service_in_systemd
               systemctl daemon-reload
               systemctl enable tvault-object-store.service
            else
                create_tvault_object_store_service_init
            fi
       elif is_fedora; then
            echo "installing tvault-object-store layer on" $DISTRO
            create_tvault_object_store_service_initd
            chkconfig tvault-object-store on
       elif is_suse; then
            echo "installing tvault-object-store layer on" $DISTRO
            create_tvault_object_store_service_in_systemd
            systemctl daemon-reload
            systemctl enable tvault-object-store.service
       else
            exit_distro_not_supported "installing tvault-object-store layer"
       fi
    fi

    if [ "$NFS" = True ]; then
       is_nova_read_writable
       if [ $? -ne 0 ]; then
           echo -e "Snapshot storage directory($VAULT_DATA_DIR) does not have write access to nova user\n \
                    Please assign read, write access to nova user on directory $VAULT_DATA_DIR "
           exit 1
       fi
    fi

    contego_stop
    echo "Install complete."
    exit 0
fi
