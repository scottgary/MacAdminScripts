#!/bin/bash
################################################################################
#  Snipe-IT Requestable Devices                                                #
#  Created by: Scott Gary                                                      #
#  Version History: 02/25/2021 Create base script                              #
#                                                                              #
#                                                                              #
################################################################################
# Global Vars                                                                  #
################################################################################
# Snipe-IT Variables:
SnipeServer=""
SnipeBearer=""
# Slack Webook variables:
SlackHook="" #Webhook URL
Channel=""
Username=""
EMOJI=""

# Title for GUI popup:
GuiTitle=""
# Machine Serial
SerialNumber=$(ioreg -l | grep IOPlatformSerialNumber | awk -F "\"" '{print $4}')

# Snipe find user by requesting machine:
SnipeSerialSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
SnipeUsername=$(echo "$SnipeSerialSearch" | grep -Eo '"username"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')

# Snipe find devices marked Requestable:
SnipeRequestableSearch=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?status=Requestable")

# Setup arrays for data:
RequestableIds=()
RequestableDevices=()
RequestableSerials=()
RequestableProcessors=()
RequestableRam=()
RequestableModels=()
SnipeRequestableMachines=()
# Parse Snipe results:
# ID fields are in this order: DeviceID > ModelID > StatusID > CategoryID > manufacturerID > locationID > rtd_locationID
while IFS=$'\n' read -r line;do
  RequestableIds+=("$line")
done < <(echo "$SnipeRequestableSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2}')
unset IFS

# Run every 7th entry in array to grab each machine
for((n=0;n<${#RequestableIds[@]};n++)); do
        if (( $((n % 7 )) == 0 )); then
          # Individual machine id's:
          Device=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware/${RequestableIds[$n]}")
          RequestableDevices+=("$Device")
        fi
done

# Loop through Requestable devices:
for i in "${RequestableDevices[@]}"; do
  while IFS=$'\n' read -r line;do
    RequestableProcessors+=("$line")
  done < <(echo "$i" | grep -Eo '"_snipeit_processor_type_4","value"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  while IFS=$'\n' read -r line;do
    RequestableSerials+=("$line")
  done < <(echo "$i" | grep -Eo '"serial"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  while IFS=$'\n' read -r line;do
    RequestableRam+=("$line")
  done < <(echo "$i" | grep -Eo '"_snipeit_total_ram_6","value"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  while IFS=$'\n' read -r line;do
    RequestableModels+=("$line")
  done < <(echo "$i" | grep -Eo '"model":{"id":[0-9]{1,100},"name"[^,]*' | awk -F ":" '{print $4}' | sed 's/"//g' | sed 's/}//g')
  unset IFS
done

for ((i=0; i<"${#RequestableModels[@]}"; i++)); do
  SnipeRequestableMachines[$i]+="${RequestableModels[$i]} Processor: ${RequestableProcessors[$i]} RAM: ${RequestableRam[$i]} ${RequestableSerials[$i]}"
done

#setup GUI for user to select devies:
UserSelection=$(/usr/bin/osascript -e 'return choose from list {"'"${SnipeRequestableMachines[0]}"'", "'"${SnipeRequestableMachines[1]}"'", "'"${SnipeRequestableMachines[2]}"'"} with title "'"$GuiTitle"'"')
UserSelectedSerialNumber=$(echo "$UserSelection" | awk -F " " '{print $12}')
UserSerialSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$UserSelectedSerialNumber")
UserSelectedId=$(echo "$UserSerialSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')

SlackMessage="New hardware request by $SnipeUsername \n$SnipeServer/hardware/$UserSelectedId"
Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
curl -s -X POST --data-urlencode "$Payload" "$SlackHook"


exit 0
