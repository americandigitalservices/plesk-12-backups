#!/bin/sh
## 2015 Backup Script
  ## Autobackup from a linux server using /var/www/vhosts/__domain__/*
  ## to a local data dir and then to Dropbox (replacing dropbox data each time)
  ## GPL by Dan Horning of American Digital Services - americandigitalservices.com
  ## uses script from github in upload-to-dropbox to communicate with Dropbox

## Usage:
  ### Unpack into a folder to run from - EG /root/backups/ setup upload-to-dropbox
  ### script per the instructions so that /root/.dropbox_uploader is created and has
  ### a valid upload key - or script will not upload your backups.

  ### Run from command line $ sh plesk_server_backup.sh or run from crontab on a regular occasion

## ToDo:
  ##   cli domain filter to pick single domain
  ##   Script Locking
  ##   Time Logging

### keep me in the background ###
renice +19 -p $$ &> /dev/null
if [ -x /usr/bin/ionice ]; then
  ionice -c3 -p $$ &> /dev/null
fi
## Script Locker
mylockfile="${0}.lock"
if [ -f ${mylockfile} ] ; then
  if [ "$(ps -p `cat ${mylockfile}` | wc -l)" -gt 1 ]; then
    echo "$0: Running PID `cat ${mylockfile}`"
    exit 0
  else
    echo " $0: Orphan lock file warning. Lock file deleted."
    rm ${mylockfile}
  fi
fi
echo $$ > ${mylockfile} #lock
echo "## Start time: "`date +%Y%m%d%H%M`
#################################

  ## Config
    mypath="${0%/*}"
    myname="`hostname -s`"
    dropbox_path="/"
    CONFIG_FILE="/root/.nonplesk_config"
    if [[ -e $CONFIG_FILE ]]; then

      #Loading data... and change old format config if necesary.
      source "$CONFIG_FILE" 2>/dev/null
      #Checking the loaded data
      if [[ $MYSQL_USER == "" || $MYSQL_PASS == "" || $MYSQL_BIN_D == "" || $targetdir == "" ]]; then
        echo -ne "Error loading data from \"$CONFIG_FILE\"...\n"
        echo -ne "Please Verify that you have added a config file with the following contents\n"
        echo -ne "\n"
        echo -ne "targetdir=\"/home/backups\"\n"
        echo -ne "MYSQL_USER=\"USERNAME\"\n"
        echo -ne "MYSQL_PASS=\"PASSWORD\"\n"
        echo -ne "MYSQL_BIN_D=\"/usr/bin\"\n"
        rm ${mylockfile}        #unlock
        exit 1
      fi
    else
      echo -ne "\n This is the first time you run this script.\n\n"
      echo -ne "\"$CONFIG_FILE\" doesn't exist ...\n"
      echo -ne "Please create the config file with the following contents\n"
      echo -ne "\n"
      echo -ne "targetdir=\"/home/backups\"\n"
      echo -ne "MYSQL_USER=\"USERNAME\"\n"
      echo -ne "MYSQL_PASS=\"PASSWORD\"\n"
      echo -ne "MYSQL_BIN_D=\"/usr/bin\"\n"
      rm ${mylockfile}        #unlock
      exit 1
    fi

  ## Pre-clean
    this_target_dir="${targetdir}/core"
    rm -Rf ${this_target_dir};
    mkdir -p ${this_target_dir};

  ## Backup core data
    tar -zcf ${this_target_dir}/backup_etc.tar.gz /etc/ /var/spool/ /boot/grub /boot/efi
    tar -zcf ${this_target_dir}/backup_named.tar.gz /var/named/ --ignore-failed-read
    tar -zcf ${this_target_dir}/backup_www.tar.gz /var/www/cgi-bin /var/www/error  /var/www/icons /var/www/webmail
    tar -zcf ${this_target_dir}/backup_svn.tar.gz /var/www/svnrepos
    tar -zcf ${this_target_dir}/backup_logs.tar.gz /var/log/

  ###### tar -zcf $targetdir/backup_zimbra.tgz /opt/zimbra/
    this_target_dir="${targetdir}/zimbra"
    rm -Rf ${this_target_dir};
    mkdir -p ${this_target_dir};

    # will need to call script in http://wiki.zimbra.com/wiki/Open_Source_Edition_Backup_Procedure#Backup_Shell_Script_with_Compressed_.26_Encrypted_Archives
    # probally the LVM one http://www.nervous.it/lang/en-us/2007/01/zimbra-lvm-backup-with-duplicity-volume/

  ##Backup Databases
    this_target_dir="${targetdir}/db"
    rm -Rf ${this_target_dir};
    mkdir -p ${this_target_dir};

    #mysqlcheck -A -o -u ${MYSQL_USER} -p${MYSQL_PASS}  ## running separately
    for database in $(${MYSQL_BIN_D}/mysql -u ${MYSQL_USER} -p${MYSQL_PASS} -e "SHOW DATABASES;" | grep "^\|" | grep -v Database);
        do echo -n "backing up ${database} ... ";
        mysqldump --add-drop-database --single-transaction -u ${MYSQL_USER} -p${MYSQL_PASS} ${database} > ${this_target_dir}/backup_db_${database}.sql && echo "ok" || echo "failed";
        gzip ${this_target_dir}/backup_db_${database}.sql;
    done

  ## Backup in domain based folders
    this_target_dir="${targetdir}/domains"
    rm -Rf ${this_target_dir};
    mkdir -p ${this_target_dir};

    echo -n "backing up primary domain ... ";
    tar -zcf ${this_target_dir}/backup_html.tar.gz /var/www/html && echo "ok" || echo "failed";

    for folder in $(find /var/www/vhosts/ -mindepth 1 -maxdepth 1 -type d | sed 's!.*/!!');
    	do echo -n "backing up $folder ... ";
    	tar -zcf ${this_target_dir}/backup_vhost_$folder.tar.gz /var/www/vhosts/$folder && echo "ok" || echo "failed";
    done

## encrypt
    # tar -cvz /<path> | gpg --encrypt --recipient <keyID> > /<backup-path>/backup_`date +%d_%m_%Y`.tar.gz.gpg
    # tar -cz $path | gpg --encrypt --recipient $keyID -o $dest_file

## run the dropbox backup if ~/.dropbox_cred exists
    if [ -f /root/.dropbox_uploader ]; then
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/core ${dropbox_path};
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/zimbra ${dropbox_path};
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/db ${dropbox_path};
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/domains ${dropbox_path};
      rm -Rf ${targetdir};
    fi

echo "## End time: "`date +%Y%m%d%H%M`
rm ${mylockfile}        #unlock
