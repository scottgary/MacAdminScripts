#!/bin/bash
################################################################################
#  Snipe-IT API Template    Created by: Scott Gary                             #
#  Version History: 02/10/2021 Create base script                              #
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
SnipeBearer=""
# Machine Serial
SerialNumber=$(ioreg -l | grep IOPlatformSerialNumber | awk -F "\"" '{print $4}')

# Pull Jamf Record for Snipe-IT:
JamfRecord=$(curl -s -H "authorization: basic $JamfApiCreds" -H "accept: application/xml" "$JamfServer/JSSResource/computers/serialnumber/$SerialNumber" | xmllint --format -)
# Get Jamf info into array
JamfInfoArray=()
# Get Jamf General info for Snipe:  MUST BE IN THE SAME ORDER AS CUSTOM FIELDSET
JamfId=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/id/text()' -)
JamfName=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/name/text()' -)
JamfInfoArray+=("$JamfName")
JamfMacAddress=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/mac_address/text()' -)
JamfInfoArray+=("$JamfMacAddress")
JamfAlternateMacAddress=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/alt_mac_address/text()' -)
JamfInfoArray+=("$JamfAlternateMacAddress")
JamfProcessorType=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_type/text()' -)
JamfInfoArray+=("$JamfProcessorType")
JamfProcessorSpeed=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_speed_mhz/text()' -)
JamfInfoArray+=("$JamfProcessorSpeed")
JamfTotalRam=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/total_ram/text()' -)
JamfInfoArray+=("$JamfTotalRam")
JamfDepStatus=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/management_status/enrolled_via_dep/text()' -)
JamfInfoArray+=("$JamfDepStatus")
JamfSipStatus=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/sip_status/text()' -)
JamfSmartStatus=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/storage/device/smart_status/text()' -)
JamfInfoArray+=("$JamfSmartStatus")
if [[ "$JamfSipStatus" == "Enabled" ]]; then
  SnipeSipStatus="true"
  JamfInfoArray+=("$SnipeSipStatus")
else
  SnipeSipStatus="false"
  JamfInfoArray+=("$SnipeSipStatus")
fi
JamfUdid=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/udid/text()' -)
JamfInfoArray+=("$JamfUdid")
JamfPublicIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/ip_address/text()' -)
JamfInfoArray+=("$JamfPublicIP")
JamfLocalIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/last_reported_ip/text()' -)
JamfInfoArray+=("$JamfLocalIP")
JamfLink="https://measuresforjustice.jamfcloud.com/computers.html?id=$JamfId"
JamfInfoArray+=("$JamfLink")

# Snipe searh for asset by serial:
SnipeSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
# Parse Snipe results to find "id":
SnipeId=$(echo "$SnipeSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')
SnipeAssetTag=$(echo "$SnipeSearch" | grep -Eo '"asset_tag"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g' )
# Gather custom field json data:
SnipeCustomFields=()
while IFS=$'\n' read -r line;do
  SnipeCustomFields+=("$line")
done < <(echo "$SnipeSearch" | grep -Eo '"field":"_snipeit_[a-zA-z]{1,100}_[0-9]{1,100}"' | awk -F ":" '{print $2}' | sed 's/"//g')
unset IFS

SnipeUpdateAsset='{"name":"'${JamfInfoArray[0]}'",'
JamfInfoArrayCounter=1
# Loop through custom fields to build payload:
for i in "${SnipeCustomFields[@]}"; do
  SnipeUpdateAsset=$SnipeUpdateAsset'"'$i'":"'${JamfInfoArray[$JamfInfoArrayCounter]}'",'
  JamfInfoArrayCounter=$((JamfInfoArrayCounter+1))
done

SnipeUpdateAsset=$(echo "$SnipeUpdateAsset" | sed 's/,$/}/')

# If no Snipe ID was found:
if [[ -z "$SnipeId" ]]; then
  echo "no asset found; needs creation"
  JamfModel=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/model/text()' -)
  JamfModelID=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/model_identifier/text()' -)
  # Search Snipe for Model:
  SnipeModel=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/models?limit=100&offset=0&search=$JamfModel")
  SnipeModelId=$(echo "$SnipeModel" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')
  if [[ -z "$SnipeModelId" ]]; then
    echo "No matching model found; needs creation"
    SnipeNewModel='{"name":"'$JamfModel'","model_number":"'$JamfModelID'","category_id":2,"manufacturer_id":1,"fieldset_id":2}'
    curl -s -X POST -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/models" -d "$SnipeNewModel"
    SnipeModel=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/models?limit=100&offset=0&search=$JamfModel")
    SnipeModelId=$(echo "$SnipeModel" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')
  fi
  # Create New Asset JSON
  SnipeNewAsset='{"status_id":1,"model_id":'$SnipeModelId',"name":"'${JamfInfoArray[0]}'","serial":"'$SerialNumber'"}'
  # Create New Asset:
  curl -s -X POST -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/hardware" -d "$SnipeNewAsset"
  # Search for new asset:
  SnipeSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
  # Parse Snipe results to find "id":
  SnipeId=$(echo "$SnipeSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')
  SnipeAssetTag=$(echo "$SnipeSearch" | grep -Eo '"asset_tag"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g' )
  # Update Custom Fields in Snipe:
  curl -s -X PUT -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/hardware/$SnipeId" -d "$SnipeUpdateAsset"
  #Update Jamf Asset Tag with Snipe info:
  /usr/local/bin/jamf recon -assetTag "$SnipeAssetTag"
else
  echo "Device found in Snipe, updating record"
  # Snipe-IT API update:
  curl -s -X PUT -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/hardware/$SnipeId" -d "$SnipeUpdateAsset"
  #Update Jamf Asset Tag with Snipe info:
  /usr/local/bin/jamf recon -assetTag "$SnipeAssetTag"
fi

exit 0
