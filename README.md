# Cron Drush

This script is intended to run Drupal activities from system cron by help of Drush.

Originally it has been developed in AWS context, so it may contain some specifics.

## Installation

1. Copy the script to your system `/usr/local/bin/drin-drush.sh`
1. Give it execution rights `chmod 755 /usr/local/bin/cron-drush.sh`
1. Modify it according to your needs
1. Configure system cron entry
   1. Create new cron file (for example `/etc/cron.d/drush`) or append to an existing one
   1. Add an entry, for example:
   ```
   PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
   0 * * * *  root  cron-drush.sh cron
   ```
1. This script assumes availbility of following environment variables for its operations:
   1. `COMPOSER_HOME` (for example: `/usr/lib/composer`)
   1. `BASE_URL` (optional) (for example: `https://www.example.com`)
   1. `WEBROOT` (for example `/var/app/current/web`)
1. Either define those in your cron file or modify the script to your needs

## Usage

* This script is meant to be executed from system cron
* This script is meant to be executed as root
* It passes it's arguments to `drush`, so accepts arbitrary `drush` arguments, not just `cron`
* See logs at `/var/log/cron-drush.log`

## Modifications

1. Take care of environment variables (mentioned in "Installation" section)
1. Specify web server user and group (for `sudo` and `chmod`)
1. Make sure the `PATH` (in the script) allows find `drush`, `mysql` and other base utilities
1. If you don't need leader functionality, strip it out

## Running multi-site

Modify your cron file. For example:
```
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
0 * * * *  root  cron-drush.sh @site1 cron ; cron-drush.sh @site2 cron
```

Drop drush aliases file into `/etc/drush` folder, so that homeless webserver user can find it.