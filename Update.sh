#!/bin/bash

# This program is shared in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

# Without parameter script will go through all yaml files and create/pull/recreate all of them
#   - it will skip all files with "!" in front 
# With yaml file name as parameter only that container will be created/pulled/recreated
#   - script will NOT skip files with "!" in front
#   - file name can be provided with o without extension (.yaml, .yml)
# Script will REBUILD custom images (with correct pair of compose "*.yaml" file and "*.dockerfile" file) 

# Used naming scheme:
# cNAME - const, vName - variable, vNAME - all caps variable for "Text" (multiline) 

# colors
cBlue='\033[0;36m'
cGreen='\033[0;32m'
cYellow='\033[0;33m'
cRED='\033[0;31m'
cNC='\033[0m' # No Color

# char used to ignore vInputFiles when doing "ALL"
cSkipChar="!"

vInputFiles="$1"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Update ALL or single Container
if [ -z "$vInputFiles" ] 
then
	echo -e "${cBlue}Updating ${cGreen}ALL${cBlue}, Working directory is ${cGreen}'$SCRIPT_DIR'${cNC}"
  vInputFiles=$SCRIPT_DIR/*.yaml
  vSingleFileMode=false
else
  if [ -f $SCRIPT_DIR"/"$vInputFiles ]; then
    vInputFiles=$vInputFiles
  elif [ -f $SCRIPT_DIR"/"$vInputFiles".yaml" ]; then
    vInputFiles=$vInputFiles".yaml"
  elif [ -f $SCRIPT_DIR"/"$vInputFiles".yml" ]; then
    vInputFiles=$vInputFiles".yml"
  else
    echo "File '${vInputFiles}' not found!"
    exit
  fi 

  echo -e "${cBlue}Updating only ${cGreen}${vInputFiles/#$cSkipChar}${cBlue}, Working directory is ${cGreen}'$SCRIPT_DIR'${cNC}"
  vInputFiles=$SCRIPT_DIR"/"$vInputFiles
  vSingleFileMode=true
fi

echo -e "${cBlue}Start Update${cNC}"
#echo -e "${cBlue}## Removing old images ##${cNC}"
#docker image prune -a -f
echo -e "${cBlue}## Removing old volumes ##${cNC}"
docker volume prune -f
echo ""

for vFile in $vInputFiles
do
  vFilename=$(basename -- "$vFile")
  vFilename="${vFilename%.*}" # remove extension
  vFilenameLower=$(echo $vFilename | tr '[:upper:]' '[:lower:]') # docker-compose do not like upper case in stack name
  vEnvFilename="$SCRIPT_DIR/${vFilename}.env"

  if [[ $vFilename == $cSkipChar* ]]; 
  then
    vFilename=${vFilename/#$cSkipChar}
    if [[ "$vSingleFileMode" = false ]]; 
    then
      vSKIPPED="$vSKIPPED  $vFilename \n"
      #echo -e "${cBlue}######################## Skipping ${cYellow}$vFilename ${cBlue}########################${cNC}\n"
      continue 
    fi
  fi

  echo -e "${cBlue}######################## Updating ${cGreen}$vFilename ${cBlue}########################${cNC}"

  # check if env file with same name as yaml exists, if yes use it in docker-compose up --env-file
  vUseEnv=""
  if test -f "$vEnvFilename"; then
    echo -e "${cYellow}Found ENV configuration file, will use it with compose.${cNC}"
	vUseEnv="--env-file $vEnvFilename"
  fi

  echo -e "${cBlue}## Checking for new images / build / pull ##${cNC}"
  docker-compose -f $vFile -p $vFilenameLower $vUseEnv build --pull
    vExitCode_BUILD=$? # save exit code for later 
  docker-compose -f $vFile -p $vFilenameLower $vUseEnv pull
    vExitCode_PULL=$? # save exit code for later
  echo -e "${cBlue}## Upgrade if needed ##${cNC}"

  # create or recreate/update container (all comand output catched to variable for further use)
  vDOCKER_UP=$(docker-compose -f $vFile -p $vFilenameLower $vUseEnv up -d 2>&1) 
    vExitCode_UP=$? # save exit code for later
  echo "$vDOCKER_UP" # all output was catched to variable so we need to write it to terminal

  # if any of the commands returne error exit code than report it
  if [[ $vExitCode_BUILD != 0 || $vExitCode_PULL != 0 || $vExitCode_UP != 0 ]];
  then
    vERROR="$vERROR  $vFilename \n"
    continue
  fi

  # to make sure we have enaugh free space remove all old images after every update
  # if no update was made skip (yes I know that single expression would be enough)
  if [[ $vDOCKER_UP == *"Creat"* || $vDOCKER_UP == *"Recreat"* ]]; 
  then
    vUPDATED="$vUPDATED  $vFilename \n"
    echo -e "${cBlue}## Removing old images ##${cNC}"
    docker image prune -a -f
    echo -e "${cBlue}## Removing old volumes ##${cNC}"
    docker volume prune -f
  else
    vNOT_UPDATED="$vNOT_UPDATED  $vFilename \n"
  fi

  echo ""
done

# Main task compleated
echo -e "${cBlue}########################${cGreen} Done ${cBlue}########################${cNC}\n"

# Summary for user plus LOG file
vSUMMARY="$vSUMMARY${cBlue}Created or updated:${cNC}\n"
if [ -z "$vUPDATED" ]
then
      vSUMMARY="$vSUMMARY [none]\n\n"
else
      vSUMMARY="$vSUMMARY${cGreen}$vUPDATED${cNC}\n"
fi

vSUMMARY="$vSUMMARY${cBlue}Already up-to-date:${cNC}\n"
if [ -z "$vNOT_UPDATED" ]
then
      vSUMMARY="$vSUMMARY [none]\n\n"
else
      vSUMMARY="$vSUMMARY${cGreen}$vNOT_UPDATED${cNC}\n"
fi

vSUMMARY="$vSUMMARY${cBlue}SKIPPED:${cNC}\n"
if [ -z "$vSKIPPED" ]
then
      vSUMMARY="$vSUMMARY [none]\n\n"
else
      vSUMMARY="$vSUMMARY${cYellow}$vSKIPPED${cNC}\n"
fi

vSUMMARY="$vSUMMARY${cBlue}ERROR:${cNC}\n"
if [ -z "$vERROR" ]
then
      vSUMMARY="$vSUMMARY [none]\n\n"
else
      vSUMMARY="$vSUMMARY${cRED}$vERROR${cNC}\n"
fi

# Log file with date and summary
echo -e "$vSUMMARY"
date +"### %Y-%m-%d %H:%M:%S ###" >> "$SCRIPT_DIR/UpdateHistory.log"
echo -e "$vSUMMARY" | sed 's/\x1B\[[0-9;]\{1,\}[A-Za-z]//g' >> "$SCRIPT_DIR/UpdateHistory.log"

