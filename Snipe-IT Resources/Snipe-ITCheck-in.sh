#!/bin/bash
################################################################################
#  Snipe-IT API Template    Created by: Scott Gary                             #
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
SnipeBearer=""
# space seperated list of custom field names you want to update:
SnipeCustomFields=("_snipeit_public_ip_10" "_snipeit_local_ip_11" "_snipeit_os_version_15" "_snipeit_jamf_last_checkin_16")
# Machine Serial
SerialNumber=$(ioreg -l | grep IOPlatformSerialNumber | awk -F "\"" '{print $4}')
# Pull Jamf Record for Snipe-IT:
JamfRecord=$(curl -s -H "authorization: basic $JamfApiCreds" -H "accept: application/xml" "$JamfServer/JSSResource/computers/serialnumber/$SerialNumber" | xmllint --format -)
# Get Jamf info into array
JamfInfoArray=()
JamfName=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/name/text()' -)
JamfInfoArray+=("$JamfName")
JamfPublicIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/ip_address/text()' -)
JamfInfoArray+=("$JamfPublicIP")
JamfLocalIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/last_reported_ip/text()' -)
JamfInfoArray+=("$JamfLocalIP")
JamfOsVersion=$(echo "$JamfRecord" | xmllint --xpath '/computer/hardware/os_version/text()' -)
JamfInfoArray+=("$JamfOsVersion")
JamfLastCheckIn=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/last_contact_time/text()' -)
JamfInfoArray+=("$JamfLastCheckIn")

# Snipe searh for asset by serial:
SnipeSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
# Parse Snipe results to find "id":
SnipeId=$(echo "$SnipeSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')

# JSON Payload:
SnipeUpdateAsset='{"name":"'${JamfInfoArray[0]}'", "'${SnipeCustomFields[0]}'":"'${JamfInfoArray[1]}'","'${SnipeCustomFields[1]}'":"'${JamfInfoArray[2]}'","'${SnipeCustomFields[2]}'":"'${JamfInfoArray[3]}'","'${SnipeCustomFields[3]}'":"'${JamfInfoArray[4]}'"}'
# Update Snipe custom fields:
curl -s -X PUT -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/hardware/$SnipeId" -d "$SnipeUpdateAsset"

exit 0
