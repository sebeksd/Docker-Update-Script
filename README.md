# Docker update script #


# README #

## Description ##
Simple script designed for "home" use to update multiply docker containers. Script should be run from same directory as docker-compose configuration files are contained in.
It also support building images from docker file + docker-compose file.
Env files are also supported, when env file with same name as ".yaml" file is present script will use it with docekr-compose, e.g. MySQL.env + MySQL.yaml in same directory (script will show info about that when env file is used).

## Usage: ##
- Run script to update all containers (files with "!" as prefix are ignored): ./Update.sh
- Run script providing a single file name to update only that container (files with "!" are NOT ignored): ./Update.sh NextCloud.yaml (extension can be omitted)

Containers that don't require update (no changes found) will not be restarted.

## How to run ##
1. Directory contains: Update.sh, NextCloud.yaml, Nextcloud.dockerfile, MySQL.yaml
- Run: ./Update.sh
- Result: Create or update (with build from docker file) NextCloud, Create or update (without build) MySQL

2. Directory contains: Update.sh, NextCloud.yaml, Nextcloud.dockerfile, MySQL.yaml
- Run: ./Update.sh MySQL.yaml
- Result: Create or update (without build) only MySQL (can contain multiply containers) 
- Extension ".yaml" can be omitted

## File structure example: ##
Yaml file can contain multiply containers definition, it can also contain "image" node or "build" node, e.g.: \
1. 
```
version: "3.5"
services:
  nodered:
    image: nodered/node-red
```
2.
```
version: "3.5"
services:
  nextcloud:
    build:
        context: ./
        dockerfile: Nextcloud.dockerfile
```

![ReadmeScreenshot.png](images_readme/ReadmeScreenshot.png)

## Donation ##
If you like this and you think it is worth of your money or you just have to much money, feel free to donate to my Bitcoin Address :)

Bitcoin address: 17dys6rtkz8yeJLVoB7VahVYQ7TNgyuMUy
