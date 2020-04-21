#!/bin/bash
metos=`echo $1`
metos2=`echo $2`
####################
TVAULT_V=4.0.74.tar.gz
TVAULT_VERSION=$(echo $TVAULT_V | awk -F '.tar' '{ print $1 }')
PYPI_PORT=8081
HTTP_PORT=8085
#####################

ipv6_regex='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
ipv6_regex_1='^\[([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}\]$'

function_create_trilio_yum_repo_file() {
cat > /etc/yum.repos.d/trilio.repo <<-EOF
[trilio]
name=Trilio Repository
baseurl=http://$TVAULTAPP:$HTTP_PORT/yum-repo/queens/
enabled=1
gpgcheck=0
EOF
#yum update -y
}

function_create_trilio_apt_repo_file() {
cat > /etc/apt/sources.list.d/trilio.list <<-EOF
deb http://$TVAULTAPP:$HTTP_PORT deb-repo/
EOF
apt-get update -y | grep '^Error'
}

remove_pth_file()
{
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

remove_pip_packages()
{
  PIP_INS=`pip --version || true`
  EASY_INS=`easy_install --version`
  if [[ $PIP_INS == pip* ]];then
     echo "uninstalling packages"
     echo "PIP already installed"
     pip uninstall tvault-horizon-plugin -y
     pip uninstall python-workloadmgrclient -y
  elif [[ $EASY_INS == setuptools* ]];then
       echo "uninstalling packages"
       easy_install --no-deps pip  &> /dev/null
       if [ $? -ne 0 ];then
          echo "installing pip-7.1.2.tar.gz"
          easy_install --no-deps http://$TVAULTAPP:$PYPI_PORT/packages/pip-7.1.2.tar.gz &> /dev/null
          if [ $? -eq 0 ]; then
             echo "pip installation done successfully"
          else
              echo "Error : easy_install http://$TVAULTAPP:$PYPI_PORT/packages/pip-7.1.2.tar.gz"
              exit 1
          fi
          pip uninstall tvault-horizon-plugin -y
          pip uninstall python-workloadmgrclient -y
       else
           pip uninstall tvault-horizon-plugin -y
           pip uninstall python-workloadmgrclient -y
       fi
       pip uninstall pip -y
  else
      echo "pip and easy_install not available hence skipping trilio pip package cleanup."
  fi
}

if [ "$metos" == "--auto" ];then
        source tvault-horizon-plugin-install.answer

elif [ "$metos" == "--help" ];then
        echo
        echo "1. ./tvault-horizon-plugin-install.sh : install tvault-horizon-plugin in interactive way."
        echo
        echo "2. ./tvault-horizon-plugin-install.sh --auto : install tvault-horizon-plugin using tvault-horizon-plugin-install.answer file."
        echo
        echo "3. ./tvault-horizon-plugin-install.sh --uninstall : uninstall tvault-horizon-plugin in interactive way."
        echo
        echo "4. ./tvault-horizon-plugin-install.sh --uninstall --auto: uninstall tvault-horizon-plugin using tvault-horizon-plugin-install.answer file"
        echo
        echo "5. ./tvault-horizon-plugin-install.sh --help : tvault-horizon-plugin installation help."
        echo
        exit 1
fi

if [ "$metos" == "--auto" ];then
        source tvault-horizon-plugin-install.answer
        if [ "$python_version" == "python2" ];then
            python2_version="True";python3_version="False"
        elif [ "$python_version" == "python3" ];then
            python2_version="False";python3_version="True"
        fi

elif [ "$metos" == "--uninstall" ]; then
        if [ "$metos2" == "" ]; then
        echo -e "\nTriliovault services uses same python version where openstack services are running"
        echo -e "\nSelect the python version which openstack services are using (1/2) :"
        while true;do
            echo "1. Python 2"
            echo "2. Python 3"
            echo -n "Option : " ; read python_opt
            if [ "$python_opt" == 1 ]; then                
                python2_version="True";python3_version="False"
                break
            elif [ "$python_opt" == 2 ]; then                
                python3_version="True";python2_version="False"
                break
            else
                echo -e "\nPlease select valid option (1/2) :"
                continue
            fi
        done  
        fi     

        if [ "$metos2" == "--auto" ];then
                source tvault-horizon-plugin-install.answer
                HORIZON=$HORIZON_PATH
                if [ "$python_version" == "python2" ];then
                    python2_version="True";python3_version="False"
                elif [ "$python_version" == "python3" ];then
                    python3_version="True";python2_version="False"
                fi
        elif [ -d /usr/share/openstack-dashboard/openstack_dashboard/local/enabled ];then
              HORIZON=/usr/share/openstack-dashboard
        else
              echo -n "Please specify path to openstack_dashboard folder : "; read HORIZON
        fi

        cd $HORIZON
        find $HORIZON -name "tvault_panel_group.py*" -exec rm -f {} \;
        find $HORIZON -name "tvault_admin_panel_group.py*" -exec rm -f {} \;
        find $HORIZON -name "tvault_panel.py*" -exec rm -f {} \;
        find $HORIZON -name "tvault_settings_panel.py*" -exec rm -f {} \;
        find $HORIZON -name "tvault_admin_panel.py*" -exec rm -f {} \;
        find $HORIZON -name "tvault_filter.py*" -exec rm -f {} \;

        cat > /tmp/sync_static.py <<-EOF
import settings
import os
import subprocess
root = settings.STATIC_ROOT+os.sep+"dashboards"
subprocess.call("rm -rf  "+root, shell=True)
EOF

        $APT_PYTHON_VERSION $file shell < /tmp/sync_static.py &> /dev/null
        rm -rf /tmp/sync_static.py
        cd -
        remove_pth_file
        DISTRO=$(awk '/ID=/' /etc/os-release | sed 's/ID=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}')
        if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
          DISTRO_VERSION=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}' | cut -d '.' -f 1) 
	   if [[ $python2_version == "True" ]]; then
              yum remove workloadmgrclient -y
              yum remove tvault-horizon-plugin -y
           elif [[ $python3_version == "True" ]]; then
             if [[ $DISTRO_VERSION == 7 ]]; then
		yum remove python3-workloadmgrclient-el7 -y
		yum remove python3-tvault-horizon-plugin -y
	     elif [[ $DISTRO_VERSION == 8 ]]; then
		yum remove python3-workloadmgrclient-el8 -y
                yum remove python3-tvault-horizon-plugin -y
	     fi   
           fi
        else
           if [[ $python2_version == "True" ]]; then
              apt purge python-workloadmgrclient -y
              apt purge tvault-horizon-plugin -y
           elif [[ $python3_version == "True" ]]; then
              apt purge python3-workloadmgrclient -y
              apt purge python3-tvault-horizon-plugin -y
           fi
        fi

        if [ "$metos2" == "--auto" ];then
            systemctl restart $WebServer
        else
            if [ -d /etc/apache2 ];then
             systemctl restart apache2
            elif [ -d /etc/httpd ];then
              systemctl restart httpd
            else
            echo -n "Please specify your WebServer service name";read WebServer
            systemctl restart $WebServer
            fi
        fi
        echo "Uninstall completed"
        exit 0

elif [ "$metos" == "" ];then
while true;do
echo -n  "Enter your Tvault appliance IP address : ";read TVAULTAPP
if echo "$TVAULTAPP" | egrep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
        then
                VALID_IP_ADDRESS="$(echo $TVAULTAPP | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255')"
                if [ -z "$VALID_IP_ADDRESS" ]
                then
                echo "Please specify valid Tvault appliance IP address"
                continue
                else
                echo
                break
                fi
elif [[ $TVAULTAPP =~ $ipv6_regex ]];
        then
        TVAULTAPP="["$TVAULTAPP"]"
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
        python2_version="True";python3_version="False"
        break
    elif [ "$python_opt" == 2 ]; then
        python3_version="True";python2_version="False"
        break
    else
        echo -e "\nPlease select valid option (1/2) :"
        continue
    fi
done
fi

if [ -d /usr/share/openstack-dashboard/openstack_dashboard/local/enabled ];then
HORIZON=/usr/share/openstack-dashboard
else
        if [ "$metos" == "--auto" ];then
        HORIZON=$HORIZON_PATH
        else
        echo -n "Please specify path to openstack_dashboard folder : "; read HORIZON
        fi
fi


check_virtual_environment()
{
   if [[ $python2_version == "True" ]]; then
      APT_PYTHON_VERSION="python"
   elif [[ $python3_version == "True" ]]; then
      APT_PYTHON_VERSION="python3"
   fi
   ENV_PATH=$($APT_PYTHON_VERSION -c "import sys; print(sys.prefix)")
   file=$(find $ENV_PATH -name "*manage.py" | grep -E 'openstack-dashboard|horizon|bin')
   echo "manage.py is found at : " $file
   if [ "$ENV_PATH" == "/usr" ]; then
      echo "no need to change bin path"
      EXTRA_APT_VAR=""
   else
      EXTRA_APT_VAR="--no-install-recommends"
   fi
}

###installing packages main##
remove_pip_packages
check_virtual_environment
DISTRO=$(awk '/ID=/' /etc/os-release | sed 's/ID=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}')
if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
   DISTRO_VERSION=$(awk '/VERSION=/' /etc/os-release | sed 's/VERSION=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}' | cut -d '.' -f 1)
   function_create_trilio_yum_repo_file
   if [[ $python2_version == "True" ]]; then
      yum install workloadmgrclient -y
      yum install tvault-horizon-plugin -y
   elif [[ $python3_version == "True" ]]; then
     if [[ $DISTRO_VERSION == 7 ]]; then
	    yum install python3-workloadmgrclient-el7 -y
	    yum install python3-tvault-horizon-plugin -y
     elif [[ $DISTRO_VERSION == 8 ]]; then
	     yum install python3-workloadmgrclient-el8 -y
	     yum install python3-tvault-horizon-plugin -y
     fi
   fi
else
   if [[ $python2_version == "True" ]]; then
      curl -Og6 http://$TVAULTAPP:$HTTP_PORT/deb-repo/deb-repo/python-workloadmgrclient_${TVAULT_VERSION}_all.deb
      apt-get install ./python-workloadmgrclient_${TVAULT_VERSION}_all.deb -y $EXTRA_APT_VAR
      rm -rf ./python-workloadmgrclient_${TVAULT_VERSION}_all.deb
      curl -Og6 http://$TVAULTAPP:$HTTP_PORT/deb-repo/deb-repo/tvault-horizon-plugin_${TVAULT_VERSION}_all.deb
      apt-get install ./tvault-horizon-plugin_${TVAULT_VERSION}_all.deb -y $EXTRA_APT_VAR
      rm -rf ./tvault-horizon-plugin_${TVAULT_VERSION}_all.deb
   elif [[ $python3_version == "True" ]]; then
      curl -Og6 http://$TVAULTAPP:$HTTP_PORT/deb-repo/deb-repo/python3-workloadmgrclient_${TVAULT_VERSION}_all.deb
      apt-get install ./python3-workloadmgrclient_${TVAULT_VERSION}_all.deb -y $EXTRA_APT_VAR
      rm -rf ./python3-workloadmgrclient_${TVAULT_VERSION}_all.deb
      curl -Og6 http://$TVAULTAPP:$HTTP_PORT/deb-repo/deb-repo/python3-tvault-horizon-plugin_${TVAULT_VERSION}_all.deb
      apt-get install ./python3-tvault-horizon-plugin_${TVAULT_VERSION}_all.deb -y $EXTRA_APT_VAR
      rm -rf ./python3-tvault-horizon-plugin_${TVAULT_VERSION}_all.deb
   fi
fi 
#######
# creating trilio.pth file which includes system path
if [[ $EXTRA_APT_VAR == "--no-install-recommends" ]]; then
	echo "We are creating trilio.pth inside the virtual environment"
	echo $(/usr/bin/$APT_PYTHON_VERSION -c "import site, os; from os import path; p = [path_dir for path_dir in site.getsitepackages() if path.exists(os.path.join(path_dir, 'dashboards'))]; print(p[0]+'/')") > $($APT_PYTHON_VERSION -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")/trilio.pth
	echo "trilio.pth file created inside the virtual environment"
fi


###write tvault_panel.py and tvault_panel_group.py

cat > $HORIZON/openstack_dashboard/local/enabled/tvault_panel_group.py <<-EOF
from django.utils.translation import ugettext_lazy as _
# The slug of the panel group to be added to HORIZON_CONFIG. Required.
PANEL_GROUP = 'backups'
# The display name of the PANEL_GROUP. Required.
PANEL_GROUP_NAME = _('Backups')
# The slug of the dashboard the PANEL_GROUP associated with. Required.
PANEL_GROUP_DASHBOARD = 'project'
EOF
cat > $HORIZON/openstack_dashboard/local/enabled/tvault_admin_panel_group.py <<-EOF
from django.utils.translation import ugettext_lazy as _
# The slug of the panel group to be added to HORIZON_CONFIG. Required.
PANEL_GROUP = 'backups-admin'
# The display name of the PANEL_GROUP. Required.
PANEL_GROUP_NAME = _('Backups-Admin')
# The slug of the dashboard the PANEL_GROUP associated with. Required.
PANEL_GROUP_DASHBOARD = 'admin'
EOF
cat > $HORIZON/openstack_dashboard/local/enabled/tvault_panel.py <<-EOF
# The slug of the panel to be added to HORIZON_CONFIG. Required.
PANEL = 'workloads'
# The slug of the dashboard the PANEL associated with. Required.
PANEL_DASHBOARD = 'project'
# The slug of the panel group the PANEL is associated with.
PANEL_GROUP = 'backups'
# Python panel class of the PANEL to be added.
ADD_PANEL = ('dashboards.workloads.panel.Workloads')
DISABLED = False
EOF
cat > $HORIZON/openstack_dashboard/local/enabled/tvault_settings_panel.py <<-EOF
# The slug of the panel to be added to HORIZON_CONFIG. Required.
PANEL = 'settings'
# The slug of the dashboard the PANEL associated with. Required.
PANEL_DASHBOARD = 'project'
# The slug of the panel group the PANEL is associated with.
PANEL_GROUP = 'backups'
# Python panel class of the PANEL to be added.
ADD_PANEL = ('dashboards.settings.panel.Settings')
DISABLED = False
EOF
cat > $HORIZON/openstack_dashboard/local/enabled/tvault_admin_panel.py <<-EOF
# The slug of the panel to be added to HORIZON_CONFIG. Required.
PANEL = 'workloads_admin'
# The slug of the dashboard the PANEL associated with. Required.
PANEL_DASHBOARD = 'admin'
# The slug of the panel group the PANEL is associated with.
PANEL_GROUP = 'backups-admin'
# Python panel class of the PANEL to be added.
ADD_PANEL = ('dashboards.workloads_admin.panel.Workloads_admin')
ADD_INSTALLED_APPS = ['dashboards']
DISABLED = False
EOF
cat > $HORIZON/openstack_dashboard/templatetags/tvault_filter.py <<-EOF
from django import template
from openstack_dashboard import api
from openstack_dashboard import policy
from datetime import datetime
from django.template.defaultfilters import stringfilter
import pytz

register = template.Library()

@register.filter(name='getusername')
def get_user_name(user_id, request):
    user_name = user_id
    if policy.check((("identity", "identity:get_user"),), request):
        try:
            user = api.keystone.user_get(request, user_id)
            if user:
                user_name = user.username
        except Exception:
            pass
    else:
        LOG.debug("Insufficient privilege level to view user information.")
    return user_name

@register.filter(name='getprojectname')
def get_project_name(project_id, request):
    project_name = project_id
    try:
        project_info = api.keystone.tenant_get(request, project_id, admin = True)
        if project_info:
            project_name = project_info.name
    except Exception:
        pass
    return project_name

def get_time_zone(request):
    tz = 'UTC'
    try:
        tz = request._get_cookies()['django_timezone']
    except:
        try:
            tz = request.COOKIES['django_timezone']
        except:
            pass

    return tz

def get_local_time(record_time, input_format, output_format, tz):
        """
        Convert and return the date and time - from GMT to local time
        """
        try:
            if not record_time or record_time is None or record_time == '':
                return ''
            else:
                if not input_format \
                        or input_format == None \
                        or input_format == '':
                    input_format = '%Y-%m-%dT%H:%M:%S.%f';
                if not output_format  \
                        or output_format == None \
                        or output_format == '':
                    output_format = "%m/%d/%Y %I:%M:%S %p";

                local_time = datetime.strptime(
                                record_time, input_format)
                local_tz = pytz.timezone(tz)
                from_zone = pytz.timezone('UTC')
                local_time = local_time.replace(tzinfo=from_zone)
                local_time = local_time.astimezone(local_tz)
                local_time = datetime.strftime(
                                local_time, output_format)
                return local_time
        except Exception as ex:
            pass
            return record_time

@register.filter(name='gettime')
def get_time_for_audit(time_stamp, request):
    display_time = time_stamp
    try:
        time_zone_of_ui = get_time_zone(request)
        display_time = get_local_time(time_stamp, '%I:%M:%S.%f %p - %m/%d/%Y','%I:%M:%S %p - %m/%d/%Y', time_zone_of_ui)
    except Exception as ex:
        pass
    return display_time

@register.filter(name='getsnapshotquantifier')
def display_time_quantifier(seconds):
    intervals = (
    ('weeks', 604800),  # 60 * 60 * 24 * 7
    ('days', 86400),    # 60 * 60 * 24
    ('hours', 3600),    # 60 * 60
    ('minutes', 60),
    ('seconds', 1),
    )

    result = []
    granularity = 4
    for name, count in intervals:
        value = seconds // count
        if value:
            seconds -= value * count
            if value == 1:
                name = name.rstrip('s')
            result.append("{} {}".format(value, name))
        else:
            # Add a blank if we're in the middle of other values
            if len(result) > 0:
                result.append(None)
    return ', '.join([x for x in result[:granularity] if x is not None])

@register.filter(name='custom_split')
@stringfilter
def custom_split(value, key):
    key=int(key)
    return value.split('_')[key]

EOF

######
:<<'END_COMMENT'
DISTRO=$(awk '/ID=/' /etc/os-release | sed 's/ID=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}')
if [ "$metos" == "--auto" ];then
    if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
        systemctl restart $WebServer
    else
        service $WebServer restart
    fi
elif [ "$metos" == "" ];then
        if [ -d /etc/apache2 ];then
        service apache2 restart
        elif [ -d /etc/httpd ];then
            if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
                  systemctl restart httpd
            else
                  service httpd restart
            fi
        else
        echo -n "Please specify your WebServer service name";read WebServer
        service $WebServer restart
        fi
fi
END_COMMENT

cat > /tmp/sync_static.py <<-EOF
import settings
import subprocess
ls = settings.INSTALLED_APPS
data = ""
for app in ls:
    if app != 'dashboards':
       data += "-i "+str(app)+" "

subprocess.call("$APT_PYTHON_VERSION $file collectstatic --noinput "+data, shell=True)
EOF

cd $HORIZON
echo "Collect horizon static file: $APT_PYTHON_VERSION"
$APT_PYTHON_VERSION $file collectstatic --noinput
echo "Collect files  done"
echo "Compression steps for horizon static file"
nohup $APT_PYTHON_VERSION $file compress --force
echo "Compresstion done for static files"

$APT_PYTHON_VERSION $file shell < /tmp/sync_static.py &> /dev/null
rm -rf /tmp/sync_static.py
echo "Tvault horizon installation is complete"

os_local_settings_path=$(find / -name "*local_settings.py" | grep -E 'openstack-dashboard|horizon')
echo -e "HORIZON_CONFIG['customization_module'] = 'dashboards.overrides'" >> `echo $os_local_settings_path | cut -d ' ' -f1`

DISTRO=$(awk '/ID=/' /etc/os-release | sed 's/ID=//' | sed -r 's/\"|\(|\)//g' | awk '{print $1;exit}')
echo "Distro $DISTRO"
if [ "$metos" == "--auto" ];then
    if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
        echo "starting webserver"
        systemctl restart $WebServer
    else
        echo "starting webserver"
        service $WebServer restart
    fi
elif [ "$metos" == "" ];then
        if [ -d /etc/apache2 ];then
        echo "starting webserver"
        service apache2 restart
        elif [ -d /etc/httpd ];then
            if [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" ]]; then
                  echo "starting webserver"
                  systemctl restart httpd
            else
                  echo "starting webserver"
                  service httpd restart
            fi
        else
        echo -n "Please specify your WebServer service name";read WebServer
        service $WebServer restart
        fi
fi
