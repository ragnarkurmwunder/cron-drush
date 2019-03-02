#!/bin/bash

# This script must be executed as root.
# It will execute drush as webapp.

# export PATH after envvars, because envvars may distort PATH
source /opt/elasticbeanstalk/support/envvars
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:$COMPOSER_HOME/vendor/bin"

log=/var/log/cron-drush.log

# make sure this script is run as webapp
current_user=$(id -un)
case "$current_user" in
  root)
    # webapp does not have home, so we must circumvent

    # need to initiate log file as root
    # because later, being as webapp, we lack permissions to do so
    touch "$log"
    chown webapp:webapp "$log"

    sudo -u webapp "$0" "$@"
    exit "$?"
    ;;
  webapp)
    true
    ;;
  *)
    echo "Execute this script as 'root'."
    exit 1
    ;;
esac

leader.py || exit

exec >> "$log" 2>&1

echo
echo
echo
date

# create temporary dir
# and remove it upon exiting
# can safely drop there all temporary files
tmp=$(mktemp -d /tmp/cron-drush.XXXXXXXX || exit 1)
trap "rm -rf $tmp" EXIT

stats="$tmp/stats"

if [ -n "$BASE_URL" ]; then
  # for a single-site, we assume BASE_URL is defined
  cmd=(drush --root="$WEBROOT" --uri="$BASE_URL" "$@")
else
  # for a multi-site, we assume BASE_URL is not defined in env, and it is supplied by an alias.
  cmd=(drush --root="$WEBROOT" "$@")
fi

set -x
/usr/bin/time -f 'time=%es, mem=%Mkb' -o "$stats" "${cmd[@]}"
{ set +x; } 2> /dev/null

# log stats to syslog
msg="$(cat "$stats"), cmd=${cmd[*]}"
logger -t "drush-cron" -- "$msg"
