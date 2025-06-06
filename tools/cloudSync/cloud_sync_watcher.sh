#!/bin/bash
emudeckBackend="$HOME/.config/EmuDeck/backend/"
. $emudeckBackend/functions/all.sh
echo "SERVICE - START" > $emudeckLogs/CloudWatcher.log

show_notification(){
  text=$1
  if [ -n "$DISPLAY" ]; then
     notify-send "$text" --icon="$HOME/.local/share/icons/emudeck/EmuDeck.png" --app-name "EmuDeck CloudSync"
  else
      echo "Not on desktop mode"
  fi

}

if [ $system = "darwin" ];then
  source "$emudeckBackend/darwin/functions/ToolsScripts/emuDeckCloudSync.sh"
fi

touch "$savesPath/.gaming"
touch "$savesPath/.watching"

show_notification "CloudSync Ready!"

# Declare an array to store current hashes
echo "SERVICE - declare" >> $emudeckLogs/CloudWatcher.log
declare -A current_hashes

# Function to calculate the hash of a directory
calculate_hash() {
  dir="$1"
  hash=$(find "$dir" -type f -exec sha256sum {} + | sha256sum | awk '{print $1}')
  echo "$hash"
}

# Extract the name of the folder immediately behind "saves"
get_parent_folder_name() {
  dir="$1"
  parent_dir=$(dirname "$dir")
  folder_name=$(basename "$parent_dir")
  echo "$folder_name"
}



get_emulator() {
  local currentEmu=$(cat "$savesPath/.emuName")
  echo $currentEmu
}

# Initialize current hashes
for dir in "$savesPath"/*/*; do
  if [ -d "$dir" ]; then
  current_hashes["$dir"]=$(calculate_hash "$dir")
  fi
done

# Loop that runs every second
while [ 1 == 1 ]
do

  # Check for changes in hashes
  lastSavedDir=''

  for dir in "${!current_hashes[@]}"; do
    #echo -ne "." >> $emudeckLogs/CloudWatcher.log

    if [ -h "$dir" ]; then
      realDir=$(readlink -f "$dir")
      new_hash=$(calculate_hash "$realDir")
    else
      new_hash=$(calculate_hash "$dir")
    fi


    # if [[ $dir == *"citra/saves"* ]]; then
    #   echo "$dir - ${current_hashes[$dir]}" >> $emudeckLogs/CloudWatcher.log
    #   echo "$dir - $new_hash" >> $emudeckLogs/CloudWatcher.log
    # fi

    currentEmu=$(get_emulator)
    if [ "$currentEmu" != '' ] && [ "$currentEmu" = 'all' ]; then
      currentEmu=$dir
    fi

    # echo $currentEmu >> $emudeckLogs/CloudWatcher.log
    # echo $dir >> $emudeckLogs/CloudWatcher.log

    if [ "${current_hashes[$dir]}" != "$new_hash" ] && [[ $dir == *"$currentEmu"* ]]; then
      # Show the name of the folder immediately behind "saves"
       echo "SERVICE - CHANGES DETECTED on $dir, LETS CHECK IF ITS A DUPLICATE" >> $emudeckLogs/CloudWatcher.log
       timestamp=$(date +%s)

       if [ $((timestamp - lastSavedTime)) == 0 ]; then
        echo "SERVICE - IGNORED, same timestamp" >> $emudeckLogs/CloudWatcher.log
       fi
       echo $((timestamp - lastSavedTime)) >> $emudeckLogs/CloudWatcher.log

      if [ $((timestamp - lastSavedTime)) -ge 1 ]; then
        emuName=$(get_parent_folder_name "$dir")
        #cloud_sync_update

        echo "SERVICE - $emuName CHANGES CONFIRMED" >> $emudeckLogs/CloudWatcher.log
        echo $timestamp > "$savesPath/$emuName/.pending_upload"
        echo "SERVICE - UPLOADING" >> $emudeckLogs/CloudWatcher.log
        show_notification "Uploading from $emuName"
        cloud_sync_uploadEmu $emuName
        rm -rf "$savesPath/$emuName/.pending_upload"
        echo "SERVICE - UPLOADED!" >> $emudeckLogs/CloudWatcher.log
        lastSavedTime=$(date +%s)
      else
        lastSavedTime=''
      fi
      current_hashes["$dir"]=$new_hash
    fi
  done


  #Autostop service when everything has finished
  if [ ! -f "$savesPath/.gaming" ]; then
    echo "SERVICE - NO GAMING" >> $emudeckLogs/CloudWatcher.log
    show_notification "Uploading... don't turn off your device"
    if [ ! -f "$emudeckFolder/cloud.lock" ]; then
      echo "SERVICE - STOP WATCHING" >> $emudeckLogs/CloudWatcher.log
      show_notification "Sync Completed! You can safely turn off your device"
      rm -rf "$savesPath/.watching"
      rm -rf "$savesPath/.emuName"
      echo "SERVICE - NO LOCK - KILLING SERVICE" >> $emudeckLogs/CloudWatcher.log

      cloud_sync_stopService
    fi
  fi

  sleep 2  # Wait for 1 second before the next iteration
done
echo "SERVICE - END" >> $emudeckLogs/CloudWatcher.log
