#!/bin/bash

# This script must be executed as root.
# It will execute drush as web user.
# Source: https://github.com/ragnarkurmwunder/cron-drush/blob/master/cron-drush.sh

# Fail if error, if unset var, if pipeline error
set -euo pipefail


# Read populate current environment.
function load_envvars {
  local envvars
  for envvars in \
    /etc/environment.export \
    /opt/elasticbeanstalk/support/envvars
  do
    if [ -f "$envvars" ]; then
      source "$envvars"
    fi
  done
}


# Logging: If logfile is not not specified, provide defualt.
function determine__cron_drush_log {
  export CRON_DRUSH_LOG="${CRON_DRUSH_LOG:-/var/log/cron-drush.log}"
}


function log_error_and_exit {
  local msg="$1"
  echo -e "\n\n\nExecution of $0 was prevented by error: $msg"
  exit 1
}


function determine__web_user {

  # Return if WEBUSER contains a good username.
  if [[ -v WEBUSER ]]; then
    if id -u "$WEBUSER" &>/dev/null; then
      return
    fi
  fi

  # Try to guess web user.
  unset WEBUSER
  local guess
  for guess in webapp www-data apache
  do
    if id -u "$guess" &>/dev/null; then
      export WEBUSER="$guess"
      return
    fi
  done

  log_error_and_exit "Environment variable 'WEBUSER' must be set. Needed to run 'drush' as proper user."
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

  log_error_and_exit "Environment variable 'COMPOSER_HOME' must be set. Expecting to find 'drush' under '$COMPOSER_HOME/vendor/bin'."
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

  log_error_and_exit "Environment variable 'WEBROOT' must be set. 'drush' needs to know where Drupal is located."
  exit 1
}


# Make sure this script is run as root.
function ensure_root {
  local current_user="$(id -un)"
  if [ "$current_user" != 'root' ]; then
    echo "Execute this script as 'root'."
    exit 1
  fi
}


function determine__leader_script {

  if [[ -v LEADER_SCRIPT ]]; then
    if [ -f "$LEADER_SCRIPT" ]; then
      return
    fi
  fi

  # Note that backslash skips aliasing.
  local guess="$(\which aws-leader.py 2>/dev/null || true)"
  if [ -f "$guess" ]; then
    export LEADER_SCRIPT="$guess"
    return
  fi

  export -n LEADER_SCRIPT
  unset LEADER_SCRIPT
}


function ensure_leader {
  if [[ -v LEADER_SCRIPT ]]; then
    if [ -f "$LEADER_SCRIPT" ]; then
      if ! "$LEADER_SCRIPT"; then
        exit
      fi
    fi
  fi
}


function logging_start {

  # Redirect stdout and stderr to append to a logfile.
  # Collect all errors during execution of the script.
  exec &>>"$CRON_DRUSH_LOG"
}


# Note, it creates global $cmd, because cannot return array.
function determine_drush_command_line {
  if [[ -v BASE_URL ]]; then
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
function execute {
  local stats="$1"
  local exit_code="$2"
  local output="$3"
  # Disable error check temporarily to be able to capture exit code.
  set +e
  # Execute as web user.
  # Sudo can pass the environment, except PATH.
  # Use 'time' with full path not to collide with other versions of it.
  sudo -E -u "$WEBUSER" PATH="$PATH" /usr/bin/time -f 'time=%es, mem=%Mkb' -o "$stats" "${cmd[@]}" &>"$output"
  echo "exit_code=$?" > "$exit_code"
  # Enable error checking
  set -e
}


# Log to Syslog.
function log_syslog {
  local stats="$1"
  local exit_code="$2"
  local msg="$(cat "$stats"), $(cat "$exit_code"), command=${cmd[*]}"
  logger -t 'cron-drush' -p 'cron.info' -- "$msg"
}


# Log to cron-drush.log.
# Note that output is directed to cron-drush.log
function log_cron_drush {

  local stats="$1"
  local exit_code="$2"
  local output="$3"

  # Separator between messages.
  echo
  echo
  echo

  date
  echo "${cmd[*]}"
  cat "$output"
  cat "$stats"
  cat "$exit_code"
}


# Check if it is safe/ok to run cron now?
function ok_to_run {

  local stats="$1"
  local exit_code="$2"
  local output="$3"

  cmd=(cron-drush-ok-to-run.sh)

  if ! hash "${cmd[0]}" &>/dev/null ; then
    return 0
  fi

  execute "$stats" "$exit_code" "$output"
  local exit_code=$(cat "$exit_code")

  if (( "$exit_code" > 0 )) ; then
    logger -t "cron-drush" -- "Execution of $0 was prevented by: ${cmd[*]}"
    return 1
  else
    return 0
  fi
}

function change_dir {
  # drush: chdir(): Permission denied (errno 13)
  # drush must be executed in folder where it can do chdir as webuser.
  cd /
}


function main {
  change_dir
  load_envvars
  # Set PATH as early as possible, but after load_aws_envvars,
  # because it may distort or influence PATH.
  export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin"
  ensure_root
  # From here on, we are executing as web user.
  determine__leader_script
  ensure_leader
  # Start logging after leader is determined:
  determine__cron_drush_log
  logging_start
  # determine web user, webroot and composer home after logging started.
  determine__web_user
  determine__webroot
  determine__composer_home
  export PATH="$PATH:$COMPOSER_HOME/vendor/bin"
  local tmp=$(sudo -u "$WEBUSER" mktemp -d /tmp/cron-drush.XXXXXXXX || exit 1)
  trap "rm -rf $tmp" EXIT
  local stats="$tmp/stats"
  local exit_code="$tmp/exit_code"
  local output="$tmp/output"
  if ok_to_run "$stats" "$exit_code" "$output" ; then
    # Note, it creates global $cmd, because cannot return array:
    determine_drush_command_line "$@"
    execute "$stats" "$exit_code" "$output"
    # Reads stats and saves into log:
    log_syslog "$stats" "$exit_code"
  fi
  log_cron_drush "$stats" "$exit_code" "$output"
}


main "$@"
