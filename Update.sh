#!/bin/bash

# This program is shared in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Script is available at: https://github.com/sebeksd/Docker-Update-Script
# For more information look at showHelp() function

# Used naming scheme:
# cNAME - const, vName - variable, vNAME - all caps variable for "Text" (multiline) 

showHelp()
{
  echo "
Usage: ${0##*/} without parameter will go through all yaml files and create/pull/recreate all of them
  - it will skip all files with '!' in front 
  
With yaml file name as parameter only that container will be created/pulled/recreated
  - script will NOT skip files with '!' in front
  - file name can be provided with or without extension ('.yaml', '.yml')
  
Script will: 
  - REBUILD custom images (with correct pair of compose '*.yaml' file and '*.dockerfile' file) 
  - use ENV file (with correct pair of compose '*.yaml' file and '*.env' file) 

Depending on container state:
 - if does not exist => create and start
 - if exists but not running => update but leave stopped
 - if exists and running => recreate and restart
  
Additional options are:
  -c - check only, it will pull images without updating running containers, in this mode there is no cleanup (ignores -r0, -r1, -r2, -rv, -ri, -po) 
  -r0, -r1, -r2 - different cleanup options, r0 - no cleanup, r1 - cleanup on script finish, r2 - cleanup after every update (useful when low on disk space)
  -rv - cleanup only volumes (works with -r1 and -r2)
  -ri - cleanup only images (works with -r1 and -r2)
  -po - 'pulled only' update containers that have already pulled images only, can be used after first running script with -c

Default is: -r1 (both unused images and volumes will be removed)
Script is available at: https://github.com/sebeksd/Docker-Update-Script"

    exit 1
}

# colors
cBlue='\033[0;36m'
cGreen='\033[0;32m'
cYellow='\033[0;33m'
cRED='\033[0;31m'
cNC='\033[0m' # No Color

# char used to ignore vInputFiles when doing "ALL"
cSkipChar="!"

cSCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Variables
vInputFiles=""
vNoUpdate=false
vCleanupLevel=1
vCleanupOnlyVolumes=false
vCleanupOnlyImages=false
vUpdatePulledOnly=false

# abort whole script (instead of single command) when user press ctr+c
trap "exit" INT

# get all arguments, file/container name has no "-" in front, other option have "-"
for arg in "$@" 
do
  case "$arg" in
    -r0) vCleanupLevel=0;; # no cleanup
    -r1) vCleanupLevel=1;; # cleanup on script finish
    -r2) vCleanupLevel=2;; # cleanup after every update 
    -rv) vCleanupOnlyVolumes=true;;
    -ri) vCleanupOnlyImages=true;;
    -po) vUpdatePulledOnly=true;;
    -c) vNoUpdate=true;;
	  -h | --help)
      showHelp  
      exit 0
      ;;
    *) vInputFiles="$arg";;
  esac
done

# Sanity check for parameters
if [[ "$vNoUpdate" == true && "$vUpdatePulledOnly" == true ]]; then  
  # in pull only ignore "no pull" flag 
  vUpdatePulledOnly=false
  echo -e "${cRED}Do not use -c with -po, ignoring -po${cNC}"
fi

# Update ALL or single Container
if [ -z "$vInputFiles" ]; then
  echo -e "${cBlue}Updating ${cGreen}ALL${cBlue}, Working directory is ${cGreen}'$cSCRIPT_DIR'${cNC}"
  vInputFiles=$cSCRIPT_DIR/*.yaml
  vSingleFileMode=false
else
  # if single container update, check if user provided name with file extension or not
  if [ -f $cSCRIPT_DIR"/"$vInputFiles ]; then
    vInputFiles=$vInputFiles
  elif [ -f $cSCRIPT_DIR"/"$vInputFiles".yaml" ]; then
    vInputFiles=$vInputFiles".yaml"
  elif [ -f $cSCRIPT_DIR"/"$vInputFiles".yml" ]; then
    vInputFiles=$vInputFiles".yml"
  else
    echo "File '${vInputFiles}' not found!"
    exit
  fi

  echo -e "${cBlue}Updating only ${cGreen}${vInputFiles/#$cSkipChar}${cBlue}, Working directory is ${cGreen}'$cSCRIPT_DIR'${cNC}"
  vInputFiles=$cSCRIPT_DIR"/"$vInputFiles
  vSingleFileMode=true
fi

container_exists()
{
  if [ "$(docker ps -aq -f name=$vFilename)" ]; then
    true # exists
  else
    false # not exists
  fi  
}

container_running()
{
  # Warning! correct result is raported only if container exists 
  if [ "$(docker ps -aq -f status=exited -f status=created -f name=$vFilename)" ]; then
    false # stopped and existing
  else
    true # running or not existing
  fi   
}

docker_cleanup()
{
  if [[ "$vCleanupLevel" == 0 || "$vNoUpdate" == true ]]; then
    return
  fi

  echo -e "${cBlue}## Cleanup ##${cNC}"

  if [ "$vCleanupOnlyVolumes" == false ]; then  
    echo -e "${cBlue}## Removing old images ##${cNC}"
    docker image prune -a -f
  fi

  if [ "$vCleanupOnlyImages" == false ]; then
    echo -e "${cBlue}## Removing old volumes ##${cNC}"
    docker volume prune -f
  fi
  echo ""
}

vModes="${cBlue}Mode:${cNC}\n"
if [ "$vNoUpdate" == true ]; then
  vModes="$vModes ${cYellow}  - Pull only, not updating!${cNC}\n"
else
  if [ "$vCleanupLevel" == 0 ]; then
    vModes="${cYellow}  - No cleanup${cNC}\n\n"
  else
    if [ "$vCleanupLevel" == 1 ]; then
      vModes="$vModes ${cYellow}  - Cleanup on script finish${cNC}\n"
    fi
    if [ "$vCleanupLevel" == 2 ]; then
      vModes="$vModes ${cYellow}  - Cleanup after every update${cNC}\n"
    fi
    if [ "$vCleanupOnlyImages" == true ]; then
      vModes="$vModes ${cYellow}  - Cleanup only Images${cNC}\n"
    fi
    if [ "$vCleanupOnlyVolumes" == true ]; then
      vModes="$vModes ${cYellow}  - Cleanup only Volumes${cNC}\n"
    fi
    if [ "$vUpdatePulledOnly" == true ]; then
      vModes="$vModes ${cYellow}  - Do not pull new images, update only already pulled${cNC}\n"
    fi
  fi
fi
echo -e "$vModes"

for vFile in $vInputFiles
do
  vFilename=$(basename -- "$vFile")
  vFilename="${vFilename%.*}" # remove extension
  vFilenameLower=$(echo $vFilename | tr '[:upper:]' '[:lower:]') # docker-compose do not like upper case in stack name
  vEnvFilename="$cSCRIPT_DIR/${vFilename}.env"

  if [[ $vFilename == $cSkipChar* ]]; then
    vFilename=${vFilename/#$cSkipChar}
    if [[ "$vSingleFileMode" = false ]]; then
      vSKIPPED="$vSKIPPED  ${cYellow}$vFilename${cNC}\n"
      #echo -e "${cBlue}######################## Skipping ${cYellow}$vFilename ${cBlue}########################${cNC}\n"
      continue 
    fi
  fi

  if [ "$vNoUpdate" = false ]; then
    echo -e "${cBlue}######################## Updating ${cGreen}$vFilename ${cBlue}########################${cNC}"
  else
    echo -e "${cBlue}######################## Checking/Pulling ${cGreen}$vFilename ${cBlue}########################${cNC}"
  fi

  # check if env file with same name as yaml exists, if yes use it in docker-compose up --env-file
  vUseEnv=""
  if test -f "$vEnvFilename"; then
    echo -e "${cYellow}Found ENV configuration file, will use it with compose.${cNC}"
	  vUseEnv="--env-file $vEnvFilename"
  fi

  # skipp pulling images when option -po was provided
  if [[ "$vUpdatePulledOnly" == false ]]; then
    echo -e "${cBlue}## Checking for new images / build / pull ##${cNC}"
    vImagesCountPre=$(docker images -q | wc -l)
    docker-compose -f $vFile -p $vFilenameLower $vUseEnv build --pull
      vExitCode_BUILD=$? # save exit code for later 
    docker-compose -f $vFile -p $vFilenameLower $vUseEnv pull
      vExitCode_PULL=$? # save exit code for later
    vImagesCountPost=$(docker images -q | wc -l)
  else
    vExitCode_BUILD=0
    vExitCode_PULL=0
  fi

  vContainerExists=false
  vContainerRunning=false

  # create or recreate/update container (all command output catched to variable for further use)
  if [ "$vNoUpdate" = false ]; then
    echo -e "${cBlue}## Upgrade if needed ##${cNC}"
    # Checking if container exists and is running
    # - if does not exist => create and start
    # - if exists but not running => update but leave stopped
    # - if exists and running => recreate and start
    vShouldStart=""

    if container_exists; then
      vContainerExists=true
      
      if ! container_running; then
        vShouldStart="--no-start"
        echo -e "${cYellow} Container is not running, updating only${cNC}"
      else
        vContainerRunning=true
      fi
    else
      echo -e "${cYellow} Container does not exist, trying to Create${cNC}"
    fi

    vDOCKER_UP=$(docker-compose -f $vFile -p $vFilenameLower $vUseEnv up $vShouldStart -d 2>&1) 
    vExitCode_UP=$? # save exit code for later

    echo "$vDOCKER_UP" # all output was catched to variable so we need to write it to terminal
  else
    vExitCode_UP=0
  fi

  # if any of the commands returne error exit code than report it
  if [[ $vExitCode_BUILD != 0 || $vExitCode_PULL != 0 || $vExitCode_UP != 0 ]]; then
    vERROR="$vERROR  ${cRED}$vFilename${cNC}\n"
    continue
  fi

  if [ "$vNoUpdate" = true ]; then
    # parsing and displaying output of docker-compose pull at the same time is hard so instead
    # we count docker images before and after
    if [[ $vImagesCountPre < $vImagesCountPost ]]; then
      vUPDATED="$vUPDATED  $vFilename \n"
    else
      vNOT_UPDATED="$vNOT_UPDATED  $vFilename \n"
    fi
  else
    # if no update was made skip
    # depending on state of the container before update we parse output differently
    vWasUpdated=false

    # container does not exists
    if [ "$vContainerExists" = false ]; then
      if [[ $vDOCKER_UP == *"Creat"* ]]; then
        vWasUpdated=true
      fi
    fi

    # container exists but not running
    if [[ "$vContainerExists" = true && "$vContainerRunning" = false ]]; then
      if [[ $vDOCKER_UP == *"Recreat"* ]]; then
        vWasUpdated=true
      fi
    fi

    # container exists and is running
    if [[ "$vContainerExists" = true && "$vContainerRunning" = true ]]; then
      if [[ $vDOCKER_UP == *"Recreat"* ]]; then
        vWasUpdated=true
      fi
    fi

    if [ "$vWasUpdated" = true ]; then
      if [ "$vContainerRunning" = true ]; then
        vUPDATED="$vUPDATED  ${cGreen}$vFilename${cNC}\n"
      else
        vUPDATED="$vUPDATED  ${cGreen}$vFilename${cNC} - ${cYellow}stopped${cNC}\n"
      fi
      # cleanup after every update if enabled
      # to make sure we have enaugh free space remove all old images after every update
      if [ "$vCleanupLevel" = 2 ]; then
        docker_cleanup
      fi
    else
      if [ "$vContainerRunning" = true ]; then
        vNOT_UPDATED="$vNOT_UPDATED  ${cGreen}$vFilename${cNC}\n"
      else
        vNOT_UPDATED="$vNOT_UPDATED  ${cGreen}$vFilename${cNC} - ${cYellow}stopped${cNC}\n"
      fi
    fi
  fi

  echo ""
done

# cleanup on script finish if enabled
if [[ "$vCleanupLevel" = 1 || "$vCleanupLevel" = 2 ]]; then
  docker_cleanup
fi

# Main task compleated
echo -e "${cBlue}########################${cGreen} Done ${cBlue}########################${cNC}\n"

# Summary for user plus LOG file
if [ "$vNoUpdate" = false ]; then
  vSUMMARY="$vSUMMARY${cBlue}Created or updated:${cNC}\n"
else
  vSUMMARY="$vSUMMARY${cBlue}Updates available:${cNC}\n"
fi

if [ -z "$vUPDATED" ]; then
      vSUMMARY="$vSUMMARY  [none]\n\n"
else
      vSUMMARY="$vSUMMARY$vUPDATED\n"
fi

vSUMMARY="$vSUMMARY${cBlue}Already up-to-date:${cNC}\n"
if [ -z "$vNOT_UPDATED" ]; then
      vSUMMARY="$vSUMMARY  [none]\n\n"
else
      vSUMMARY="$vSUMMARY$vNOT_UPDATED\n"
fi

vSUMMARY="$vSUMMARY${cBlue}SKIPPED:${cNC}\n"
if [ -z "$vSKIPPED" ]; then
      vSUMMARY="$vSUMMARY  [none]\n\n"
else
      vSUMMARY="$vSUMMARY$vSKIPPED\n"
fi

vSUMMARY="$vSUMMARY${cBlue}ERROR:${cNC}\n"
if [ -z "$vERROR" ]; then
      vSUMMARY="$vSUMMARY  [none]\n\n"
else
      vSUMMARY="$vSUMMARY$vERROR\n"
fi

# Log file with date and summary
echo -e "$vSUMMARY"
date +"### %Y-%m-%d %H:%M:%S ###" >> "$cSCRIPT_DIR/UpdateHistory.log"
echo -e "$vModes\n$vSUMMARY" | sed 's/\x1B\[[0-9;]\{1,\}[A-Za-z]//g' >> "$cSCRIPT_DIR/UpdateHistory.log"

