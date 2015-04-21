#!/bin/sh
## 2015 Backup Script
  ## Autobackup from a plesk 12 server
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
#################################

  ## Config
    mypath="`pwd`"
    myname="`hostname -s`"
    dropbox_path="/"
    targetdir="/home/backups"
    MYSQL_USER="admin" ## best to use root here to get the complete mysql backups
    MYSQL_PASS="`cat /etc/psa/.psa.shadow`" ## otherwise certain tables are skipped
    MYSQL_BIN_D=`grep MYSQL_BIN_D /etc/psa/psa.conf | awk '{print $2}'`
    PRODUCT_ROOT_D=`grep PRODUCT_ROOT_D /etc/psa/psa.conf | awk '{print $2}'`
    ## timestamp=`date +%Y%m%d%H%M` ## not used for backup to dropbox

  ## Pre-clean
    this_target_dir="${targetdir}/core"
    rm -Rf ${this_target_dir};
    mkdir -p ${this_target_dir}/db;

  ## Backup core data
    tar -zcf ${this_target_dir}/backup_etc.tar.gz /etc/ /var/spool/ /var/lib/mailman/ /var/lib/plesk/ /boot/grub /boot/efi
    tar -zcf ${this_target_dir}/backup_logs.tar.gz /var/log/ /usr/local/psa/var/log/
    tar -zcf ${this_target_dir}/backup_named.tar.gz /var/named/ --ignore-failed-read
    tar -zcf ${this_target_dir}/backup_www.tar.gz /var/www/cgi-bin /var/www/error /var/www/html /var/www/icons /var/www/manual \
     /var/www/usage /var/www/vhosts/.skel /var/www/vhosts/chroot /var/www/vhosts/default /var/www/vhosts/fs /var/www/vhosts/fs-passwd
    tar -zcf ${this_target_dir}/backup_qmail.tar.gz /var/qmail/ --exclude "/var/qmail/mailnames"

  ##Backup Databases
    #mysqlcheck -A -o -u ${MYSQL_USER} -p${MYSQL_PASS}
    for database in $(mysql -u ${MYSQL_USER} -p${MYSQL_PASS} -e "SHOW DATABASES WHERE \`Database\` not in (SELECT psa.data_bases.\`name\` FROM psa.data_bases WHERE psa.data_bases.db_server_id = 1)" | grep "^\|" | grep -v Database);
        do echo -n "backing up ${database} ... ";
        mysqldump --add-drop-database -u ${MYSQL_USER} -p${MYSQL_PASS} ${database} > ${this_target_dir}/db/backup_db_${database}.sql && echo "ok" || echo "failed";
        gzip ${this_target_dir}/db/backup_db_${database}.sql;
    done
  ## Backup client data files in domain based folders
    rm -Rf ${targetdir}/clients/
    mysql="${MYSQL_BIN_D}/mysql -N -u${MYSQL_USER} -p${MYSQL_PASS} psa"
    cat ${mypath}/plesk_backup_query.sql | $mysql | while read user domain dbs paths fwds
      do this_target_dir="${targetdir}/clients/${user}/${domain}"
      echo -n "backing up ${user} ${domain} to ${this_target_dir} ...";
      mkdir -p ${this_target_dir};

      if [ ${dbs} != "NULL" ]; then
        for database in ${dbs//,/ };
          do echo -n "backing up db ${database} ... ";
          mysqldump --add-drop-database -u ${MYSQL_USER} -p${MYSQL_PASS} ${database} > ${this_target_dir}/backup_db_${database}.sql && echo "ok" || echo "failed";
          gzip ${this_target_dir}/backup_db_${database}.sql;
        done
      fi

      ## Backup file data
      if [ ${paths} != "NULL" ]; then
        echo -n "backing up files ${paths} ... ";
        tar -zcf ${this_target_dir}/backup_vhost_${domain}.tar.gz ${paths//,/ } /var/www/vhosts/system/${domain} && echo "ok" || echo "failed";
      fi

      ## Backup Customer Emails
      if [ ${domain} != "NULL" ]; then
        echo -n "backing up emails ${domain} ... ";
        tar -zcf ${this_target_dir}/backup_mailnames_${domain}.tar.gz /var/qmail/mailnames/${domain} && echo "ok" || echo "failed";
      fi

      if [ ${fwds} != "NULL" ]; then
          echo "${fwds}" > ${this_target_dir}/forwarding_url.txt
      fi

      echo "...done"
    done

## Todo: if enabled encrypt files with key
  ## method tba

## run the dropbox backup if ~/.dropbox_cred exists
    if [ -f /root/.dropbox_uploader ]; then
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/core ${dropbox_path};
      sh ${mypath}/upload-to-dropbox/dropbox_uploader.sh upload ${targetdir}/clients ${dropbox_path};
      rm -Rf ${targetdir};
    fi
