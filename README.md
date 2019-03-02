# Cron Drush

This script is intended to run Drupal activities from system cron by help of Drush.

Originally it has been developed in AWS context, so it may contain some specifics.

## Installation

1. Copy the script to your system `/usr/local/bin/drin-drush.sh`
1. Give it execution rights `chmod 755 /usr/local/bin/cron-drush.sh`
1. Configure system cron (see below)
1. Configure environment variables (see below)

### System Cron

1. Create new cron file (for example `/etc/cron.d/drush`)
1. Add an entry (see example below)
1. Configure environment variables

#### Example

```
WEB_USER=apache2
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
0 * * * *  root  cron-drush.sh cron
```

### Environment variables

Those variables have to be specified in cron file,
or in AWS case those can be also in `envvars`
which is used automatically.

#### CRON_DRUSH_LOG

Optional.

Location cron drush logfile.

Default: `/var/log/cron-drush.log`

#### WEB_USER

Optional.

Specifies web server user for running `drush` as.

Default: tries to guess between some common usernames.

#### COMPOSER_HOME

Optional.

This is needed for script to find `drush`.
In composer dir there is `vendor/bin` which contains `drush`.

Default: `/usr/lib/composer/vendor/bin/drush`

#### WEBROOT

Optional.

Drush needs to know where Drupal is located.

Default: tries to guess between some common paths.

#### LEADER_SCRIPT

Optional.

This is needed only in multi-instance setup where there are multiple web servers against one database.
The script determines by exit code 0 which instance is considered "leader" in the group.

The value may be absolute path or relative path.
In latter case the script is searched from PATH.

Default: `leader.py`

#### BASE_URL

Optional.

In makes sense only in single-site setup when some Drupal functionality may need it and creating drush aliases files is not needed.

Example: `https://www.example.com`

## Usage

* This script is meant to be executed from system cron
* This script is meant to be executed as root
* It passes it's arguments to `drush`, so accepts arbitrary `drush` arguments, not just `cron`
* See logs at `/var/log/cron-drush.log`
* Create leader script if needed.

## Running multi-site

Modify your cron file. For example:
```
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
0 * * * *  root  cron-drush.sh @site1 cron ; cron-drush.sh @site2 cron
```

Drop drush aliases file into `/etc/drush` folder, so that homeless webserver user can find it.
