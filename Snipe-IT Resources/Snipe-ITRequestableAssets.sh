#!/bin/bash
################################################################################
#  Snipe-IT Requestable Devices                                                #
#  Created by: Scott Gary                                                      #
#  Version History: 02/22/2021 Create base script                              #
#                                                                              #
#                                                                              #
################################################################################
# Global Vars                                                                  #
################################################################################
# Jamf Variables:
JamfServer="https://example.jamfcloud.com"
# Jamf credentials base64 encoded
JamfApiCreds=""
# Snipe-IT Variables:
SnipeServer="https://example.snipe-it.io/api/v1"
SnipeBearer=""# Machine Serial
SerialNumber=$(ioreg -l | grep IOPlatformSerialNumber | awk -F "\"" '{print $4}')


JamfPull(){
  SnipeSerialNumber="$1"
  # Pull Jamf Record for Snipe-IT:
  JamfRecord=$(curl -s -H "authorization: basic $JamfApiCreds" -H "accept: application/xml" "$JamfServer/JSSResource/computers/serialnumber/$SnipeSerialNumber" | xmllint --format -)
  # Get Jamf info into array
  JamfInfoArray=()
  # Get Jamf General info for Snipe:  MUST BE IN THE SAME ORDER AS CUSTOM FIELDSET
  JamfName=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/name/text()' -)
  JamfInfoArray+=("$JamfName")
  JamfModel=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/model/text()' -)
  JamfInfoArray+=("$JamfModel")
  JamfProcessorType=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_type/text()' -)
  JamfInfoArray+=("$JamfProcessorType")
  JamfProcessorSpeed=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_speed_mhz/text()' -)
  JamfInfoArray+=("$JamfProcessorSpeed")
  JamfTotalRam=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/total_ram/text()' -)
  JamfInfoArray+=("$JamfTotalRam")

}


# Snipe find user by requesting machine:
SnipeSerialSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
SnipeUsername=$(echo "$SnipeSerialSearch" | grep -Eo '"username"[^,]*' | awk -F ":" '{print $2}')
echo "User: $SnipeUsername"

# Snipe find devices marked Requestable:
SnipeRequestableSearch=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?status=Requestable")

# Setup arrays for data:
RequestableIds=()
RequestableDevices=()
RequestableSerials=()
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
    RequestableSerials+=("$line")
  done < <(echo "$i" | grep -Eo '"serial"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
done

for i in "${RequestableSerials[@]}";do
  JamfPull "$i"
  echo "${JamfInfoArray[@]}"
done

exit 0
