#!/bin/bash

# This script must be executed as root.
# It will execute drush as web user.

# Fail if error.
set -e


# AWS-specific: read envvars into current environment
# It may contain important variables for us.
function load_aws_envvars {
  local envvars=/opt/elasticbeanstalk/support/envvars
  if [ -f "$envvars" ]; then
    source "$envvars"
  fi
}


# Logging: If logfile is not not specified, provide defualt.
function determine__cron_drush_log {
  export CRON_DRUSH_LOG="${CRON_DRUSH_LOG:-/var/log/cron-drush.log}"
}


function determine__web_user {

  # Return if WEB_USER contains a good username.
  if id -u "$WEB_USER" &>/dev/null; then
    return
  fi

  # Try to guess web user.
  unset WEB_USER
  local guess
  for guess in webapp www-data apache
  do
    if id -u "$guess" &>/dev/null; then
      export WEB_USER="$guess"
      return
    fi
  done

  echo "Environment variable 'WEB_USER' must be set. Needed to run `drush` as proper user."
  exit 1
}


function determine__composer_home {

  # Check if drush is already in PATH.
  if hash drush &>/dev/null; then
    return
  fi

  # The variable is properly set.
  if [ -f "$COMPOSER_HOME/vendor/bin/drush" ]; then
    return
  fi

  # Try to guess.
  if [ -f "/usr/lib/composer/vendor/bin/drush" ]; then
    export COMPOSER_HOME=/usr/lib/composer/vendor/bin/drush
    return
  fi

  echo "Environment variable 'COMPOSER_HOME' must be set. Expecting to find 'drush' under '$COMPOSER_HOME/vendor/bin'."
  exit 1
}


function determine__webroot {

  if [ -f "$WEBROOT/index.php" ]; then
    return
  fi

  # Try to guess.
  # For D7 and D8.
  local guess
  for guess in /{var/app/current,var/app/current/current,var/www,var/www/html,var/lib/www,var/apache,usr/local/httpd,Library/WebServer,Local/Library/WebServer,usr/local/apache2}/{.,web}
  do
    if [ -f "$guess/index.php" ]; then
      export WEBROOT="$(readlink -f "$guess")"
      return
    fi
  done

  echo "Environment variable 'WEBROOT' must be set. 'drush' needs to know where Drupal is located."
  exit 1
}


# Need to initiate log file as root,
# because later, being as web user,
# we lack permissions to do so.
function init_logfile {
   touch "$CRON_DRUSH_LOG"
   chown "$WEB_USER" "$CRON_DRUSH_LOG"
}


# Make sure this script is run as web user.
function switch_users {

  local current_user="$(id -un)"

  case "$current_user" in

    root)
      # Web user does not have home,
      # so we must circumvent.
      init_logfile
      sudo -u "$WEB_USER" "$0" "$@"
      exit "$?"
      ;;

    "$WEB_USER")
      true
      ;;

    *)
      echo "Execute this script as 'root'."
      exit 1
      ;;

  esac
}


function determine__leader_script {

  if [ -f "$LEADER_SCRIPT" ]; then
    return
  fi

  # Note that backslash skips aliasing.
  local guess="$(\which leader.py &>/dev/null || true)"
  if [ -f "$guess" ]; then
    export LEADER_SCRIPT="$guess"
    return
  fi

  export -n LEADER_SCRIPT
  unset LEADER_SCRIPT
}


function ensure_leader {
  if [ -f "$LEADER_SCRIPT" ]; then
    if ! "$LEADER_SCRIPT"; then
      exit
    fi
  fi
}


function logging_start {

  # Redirect stdout and stderr to append to a logfile.
  exec &>>"$CRON_DRUSH_LOG"

  # Add some space to log followed by timestamp.
  echo
  echo
  echo
  date
}


# Note, it creates global $cmd, because cannot return array.
function determine_drush_command_line {
  if [ -n "$BASE_URL" ]; then
    # For a single-site, we assume BASE_URL is defined.
    cmd=(drush --root="$WEBROOT" --uri="$BASE_URL" "$@")
  else
    # For a multi-site, we assume BASE_URL is not defined in env,
    # and it is supplied by an alias.
    cmd=(drush --root="$WEBROOT" "$@")
  fi
}


# Debug/Log the actual drush command line executed.
# It also generates stats.
function execute_drush {
  local stats="$1"
  set -x
  /usr/bin/time -f 'time=%es, mem=%Mkb' -o "$stats" "${cmd[@]}"
  { set +x; } &>/dev/null
}


# Log stats to Syslog.
function log_stats {
  local msg="$(cat "$stats")"
  # To syslog.
  logger -t "drush-cron" -- "$msg"
  # To our log.
  echo "$msg"
}


function main {
  load_aws_envvars
  determine__composer_home
  # Set PATH as early as possible, but after load_aws_envvars and determine__composer_home,
  # because they mey distort or influence PATH.
  export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:$COMPOSER_HOME/vendor/bin"
  determine__cron_drush_log
  determine__web_user
  determine__webroot
  # It also initialises logfile while root:
  switch_users "$@"
  # From here on, we are executing as web user.
  determine__leader_script
  ensure_leader
  # Start logging after leader is determined:
  logging_start
  # Create temporary dir and remove it upon exiting.
  # Cannot put it into a function, EXIT is emitted on return.
  local tmp=$(mktemp -d /tmp/cron-drush.XXXXXXXX || exit 1)
  trap "rm -rf $tmp" EXIT
  stats="$tmp/stats"
  # Note, it creates global $cmd, because cannot return array:
  determine_drush_command_line "$@"
  # Saves stats:
  execute_drush "$stats"
  # Reads stats and saves into log:
  log_stats "$stats"
}


main "$@"
