#!/bin/bash
################################################################################
#  Snipe-IT API Template    Created by: Scott Gary                             #
#  Version History: 02/10/2021 Create base script                              #
#                                                                              #
#                                                                              #
################################################################################
# Global Vars                                                                  #
################################################################################
set -x
# Jamf Variables:
JamfServer=""
JamfApiCreds=""
# Snipe-IT Variables:
SnipeServer=""
SnipeBearer=""
# Machine Serial
SerialNumber=$(ioreg -l | grep IOPlatformSerialNumber | awk -F "\"" '{print $4}')
# Local MacOS version
LocalOsVersion=$(sw_vers | grep "ProductVersion" | awk -F " " '{print $2}')

# Pull Jamf Record for Snipe-IT:
JamfRecord=$(curl -s -H "authorization: basic $JamfApiCreds" -H "accept: application/xml" "$JamfServer/JSSResource/computers/serialnumber/$SerialNumber" | xmllint --format -)
# Get Jamf General info for Snipe:
JamfId=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/id/text()' -)
JamfName=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/name/text()' -)
JamfMacAddress=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/mac_address/text()' -)
JamfAlternateMacAddress=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/alt_mac_address/text()' -)
JamfUdid=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/udid/text()' -)
JamfDepStatus=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/management_status/enrolled_via_dep/text()' -)
JamfPublicIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/ip_address/text()' -)
JamfLocalIP=$(echo "$JamfRecord" | xmllint --xpath '/computer/general/last_reported_ip/text()' -)

# Get Jamf Hardware info for Snipe:
JamfModel=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/model/text()' -)
JamfModelID=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/model_identifier/text()' -)
JamfProcessorType=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_type/text()' -)
JamfProcessorSpeed=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/processor_speed_mhz/text()' -)
JamfTotalRam=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/total_ram/text()' -)
JamfSipStatus=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/sip_status/text()' -)
JamfSmartStatus=$(echo "$JamfRecord" | xmllint --xpath 'computer/hardware/storage/device/smart_status/text()' -)
if [[ "$JamfSipStatus" == "Enabled" ]]; then
  SnipeSipStatus="true"
else
  SnipeSipStatus="false"
fi
echo "Snipe SIP: $SnipeSipStatus"
JamfLink="https://acme.jamfcloud.com/computers.html?id=$JamfId"

# Snipe searh for asset by serial:
SnipeSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/hardware?limit=2&offset=0&search=$SerialNumber")
echo "$SnipeSearch"
# Parse Snipe results to find "id":
SnipeId=$(echo "$SnipeSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2; exit}')
echo "$SnipeId"
SnipeAssetTag=$(echo "$SnipeSearch" | grep -Eo '"asset_tag"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g' )
echo "$SnipeAssetTag"

#Update Jamf Asset Tag with Snipe info:
#/usr/local/bin/jamf recon -assetTag "$SnipeAssetTag"

if [[ -z "$SnipeId" ]]; then
  echo "no asset found; needs creation"
  # Match JamfModel with Snipe model ID:
  #SnipeModel=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/api/v1/models?limit=100&offset=0&search=$JamfModel")

  # New asset json
  #SnipeNewAsset='{"status_id":1,"model_id":'$SnipeModel',"name":"'$JamfName'","serial":"'$SerialNumber'"}'

  # Make changes in Snipe:
  #curl -s -X POST -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/api/v1/hardware" -d "$SnipeNewAsset"
else
  echo "Device found in Snipe, updating record"
  # Snipe-IT Payload templates as Vars:
  SnipeUpdateAsset1='{"name":"'$JamfName'","custom_fields":{"MAC":{"field":"_snipeit_mac_1","value":"'$JamfMacAddress'","field_format":"MAC"},"alt_mac":{"field":"_snipeit_alt_mac_3","value":"'$JamfAlternateMacAddress'","field_format":"MAC"},"processor_type":{"field":"_snipeit_processor_type_4","value":"'$JamfProcessorType'","field_format":"ANY"},"processor_speed":{"field":"_snipeit_processor_speed_5","value":"'$JamfProcessorSpeed'","field_format":"NUMERIC"},"total_ram":{"field":"_snipeit_total_ram_6","value":"'$JamfTotalRam'","field_format":"NUMERIC"},"dep_status":{"field":"_snipeit_dep_status_8","value":"'$JamfDepStatus'","field_format":"ANY"},"sip_status":{"field":"_snipeit_sip_status_7","value":"'$SnipeSipStatus'","field_format":"ANY"},"smart_status":{"field":"_snipeit_smart_status_12","value":"'$JamfSmartStatus'","field_format":"ANY"},"udid":{"field":"_snipeit_udid_9","value":"'$JamfUdid'","field_format":"ANY"},"public_ip":{"field":"_snipeit_public_ip_10","value":"'$JamfPublicIP'","field_format":"IP"},"local_ip":{"field":"_snipeit_local_ip_11","value":"'$JamfLocalIP'","field_format":"IP"},"jamf_url":{"field":"_snipeit_jamf_url_2","value":"'$JamfLink'","field_format":"URL"}},"available_actions":{"checkout":true,"checkin":true,"clone":true,"restore":false,"update":true,"delete":false}}]}'

  SnipeUpdateAsset='{"name":"'$JamfName'","_snipeit_mac_1":"'$JamfMacAddress'","_snipeit_alt_mac_3":"'$JamfAlternateMacAddress'","_snipeit_processor_type_4":"'$JamfProcessorType'","_snipeit_processor_speed_5":"'$JamfProcessorSpeed'","_snipeit_total_ram_6":"'$JamfTotalRam'","_snipeit_dep_status_8":"'$JamfDepStatus'","_snipeit_sip_status_7":"'$SnipeSipStatus'","_snipeit_smart_status_12":"'$JamfSmartStatus'","_snipeit_udid_9":"'$JamfUdid'","_snipeit_public_ip_10":"'$JamfPublicIP'","_snipeit_local_ip:"'$JamfLocalIP'","_snipeit_jamf_url_2":"'$JamfLink'"}'

  # Snipe-IT API update:
  curl -s -X PUT -H "Authorization: Bearer $SnipeBearer" -H "Content-Type: application/json" "$SnipeServer/hardware/$SnipeId" -d "$SnipeUpdateAsset1"
fi


exit 0
