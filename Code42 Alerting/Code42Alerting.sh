#!/bin/bash
################################################################################
#  Code42Alerting    Created by: Scott Gary                                    #
#  Version History:                                                            #
#                  9/24/2021 original structure and design                     #
#  Looks for Open alerts and parse for item to acknowledge and close           #
# Requires [jq](https://stedolan.github.io/jq/download/) to parse json         #
################################################################################
# Code42 Variables
Code42Server="https://api.us.code42.com"
username=""
password=""
# Slack Variables
SlackHook="" #Webhook URL
Channel="#it-alerts"
Username="Code42 Alert"
EMOJI=":code42:" # Used as user icon

# Check for jq and quit if not installed
CheckJQ=$(which jq)
if [[ -z "$CheckJQ" ]]; then
  echo "jq not installed; installing from source"
  JqPath="/usr/local/bin/jq"
  curl -sLo "$JqPath" "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64" && chmod +x "$JqPath"
  # Check jq installed correctly:
  echo "You will need to approve jq in System Preferences < Security & Privacy and rerun"
  CheckJQ=$(which jq)
  exit 0
fi

# If you want new runs posted in a Slack Channel:
SlackNotify(){
  AlertSlackNotification="$1"
  if [[ -z "$SlackHook" ]] || [[ -z "$Channel" ]] || [[ -z "$Username" ]] || [[ -z "$EMOJI" ]] || [[ -z "$AlertSlackNotification" ]]; then
    echo "Slack Variables missing; skipping"
  else
    SlackMessage="Alert Details: \n$AlertSlackNotification"
    Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
    curl -s -X POST --data-urlencode "$Payload" "$SlackHook"
  fi
}

# Get new Bearer Token (Valid for 30 mins)
BearerToken=$(curl -sk -X GET -u "$username:$password" -H "Accept: application/json" "$Code42Server"/v1/auth/ | awk -F ":" '{print $2}' | sed 's/\"//g' | sed 's/\}//g')

# Get Tenant ID (needed for future calls)
TenantID=$(curl -sk -X GET -H "Authorization: Bearer $BearerToken" -H "Accept: application/json" "$Code42Server"/v1/customer | awk -F "," '{print $3}' | awk -F ":" '{print $2}' | sed 's/\"//g' | sed 's/\}//g')

# query alerts:
QueryData='{ "tenantId": "'$TenantID'", "groups": [ { "filters": [ { "term": "State", "operator": "is", "value": "Open" } ], "filterClause": "AND" } ], "groupClause": "OR", "pgSize": "50", "pgNum": "0", "srtKey": "CreatedAt", "srtDirection": "DESC" }'
AlertsSearch=$(curl -sk -X POST "$Code42Server"/v1/alerts/query-alerts \
-H "accept: text/plain" \
-H "Authorization: Bearer $BearerToken" \
-H "Content-Type: application/json" \
-d "$QueryData")

# Loop thorugh results and get IDs:
AlertIDs=()
ArrayCounter=0
while [[ "$ArrayCounter" -lt 50 ]]; do
  #echo "Counter is at: $ArrayCounter"
  AlertID=$(echo "$AlertsSearch" | jq '.alerts['$ArrayCounter'] .id')
  AlertIDs+=("$AlertID")
  ArrayCounter=$((ArrayCounter+1))
done

for AlertID in "${AlertIDs[@]}"; do
  # Get alert details:
  # Kill loop if null alerts:
  if [[ "$AlertID" == "null" ]]; then
    echo "No Code42 alerts found!"
    break
  fi
  data='{ "alertId": '$AlertID'}'
  AlertDetails=$(curl -sk -X POST "$Code42Server"/v1/alerts/query-details-aggregate \
  -H "accept: text/plain" \
  -H "Authorization: Bearer $BearerToken" \
  -H "Content-Type: application/json" \
  -d "$data")

  sleep 1
  # Determine what type of alert and how important it is:
  AlertName=$(echo "$AlertDetails" | jq '.alert .name' | sed 's/\"//g')
  AlertDesription=$(echo "$AlertDetails" | jq '.alert .description' | sed 's/\"//g')
  AlertActor=$(echo "$AlertDetails" | jq '.alert .actor' | sed 's/\"//g')
  AlertActorID=$(echo "$AlertDetails" | jq '.alert .actorId' | sed 's/\"//g')
  AlertSeverity=$(echo "$AlertDetails" | jq '.alert .severity' | sed 's/\"//g')
  AlertStatus=$(echo "$AlertDetails" | jq '.alert .state' | sed 's/\"//g')
  AlertTimestamp=$(echo "$AlertDetails" | jq '.alert .observation .observedAt' | sed 's/\"//g')
  AlertURL=$(echo "$AlertDetails" | jq '.alert .alertUrl' | sed 's/\"//g')
  AlertEventID=$(echo "$AlertDetails" | jq '.alert .observation .data' | awk -F 'eventId' '{print$2}' | awk -F ':\"' '{print $1}' | awk -F ':' '{print $2}' | awk -F ',' '{print $1}'| sed 's/\\"//g')
  AlertEventPath=$(echo "$AlertDetails" | jq '.alert .observation .data' | awk -F 'path' '{print$2}' | awk -F ':\"' '{print $1}' | awk -F ':' '{print $2}' | awk -F ',' '{print $1}'| sed 's/\\"//g')

#Parse by Alert Type:
  # Flight Risk Alerts
  if [[ "$AlertName" == "Flight risk" ]]; then
    # Add note to alert that this was seen:
    echo "Adding note to ticket for acknowledgment"
    data='{  "tenantId": "'$TenantID'", "alertId": '$AlertID', "note": "IT-Service Bot has reviewed this alert" }'
    AddNote=$(curl -sk -X POST "$Code42Server"/v1/alerts/add-note \
    -H "accept: text/plain" \
    -H "Authorization: Bearer $BearerToken" \
    -H "Content-Type: application/json" \
    -d "$data")
    #echo "$AddNote"
    sleep 1
    # Place user in High Risk Grouping:
    echo "adding user to High-Risk grouping"
    data='{  "tenantId": "'$TenantID'", "userId": "'$AlertActorID'"}'
    curl -X POST "$Code42Server"/v1/detection-lists/highriskemployee/add \
    -H 'content-type: application/json' \
    -H "authorization: Bearer $BearerToken" \
    -d "$data"
    sleep 1
    # Close alert
    echo "Dismiss alert once seen and action has been taken"
    data='{  "tenantId": "'$TenantID'", "alertIds": [ '$AlertID' ], "state": "RESOLVED" }'
    DismissAlert=$(curl -sk -X POST "$Code42Server"/v1/alerts/update-state \
    -H "accept: text/plain" \
    -H "Authorization: Bearer $BearerToken" \
    -H "Content-Type: application/json" \
    -d "$data")
    #echo "$DismissAlert"
  # Rules for Slack alerts:
  elif [[ "$AlertName" == "Salesforce report exfiltration" ]] || [[ "$AlertName" == "Copy to external drive" ]] || [[ "$AlertName" == "Source code exfiltration by extension" ]] || [[ "$AlertName" == "Public on Web" ]] || [[ "$AlertName" == "Exposure on an endpoint" ]] || [[ "$AlertName" == "Cloud share permission changes" ]]; then
    # Slack alerting for issue:
    AlertSlackNotification="Alert Name: $AlertName \nDescription: $AlertDesription \nUser: $AlertActor \nSeverity: $AlertSeverity \nStatus: $AlertStatus \nTimestamp: $AlertTimestamp \nURL: $AlertURL"
    SlackNotify "$AlertSlackNotification"
    # Add note to alert that this was seen:
    echo "Adding note to ticket for acknowledgment"
    data='{  "tenantId": "'$TenantID'", "alertId": '$AlertID', "note": "IT-Service Bot has reviewed this alert and sent this infomration to Slack" }'
    AddNote=$(curl -sk -X POST "$Code42Server"/v1/alerts/add-note \
    -H "accept: text/plain" \
    -H "Authorization: Bearer $BearerToken" \
    -H "Content-Type: application/json" \
    -d "$data")
    #echo "$AddNote"
  elif [[ "$AlertName" == "Critical Alerts" ]]; then
    # Add note to alert that this was seen:
    echo "Adding note to ticket for acknowledgment"
    data='{  "tenantId": "'$TenantID'", "alertId": '$AlertID', "note": "IT-Service Bot has reviewed this alert and will create a case from this information" }'
    curl -sk -X POST "$Code42Server"/v1/alerts/add-note \
    -H "accept: text/plain" \
    -H "Authorization: Bearer $BearerToken" \
    -H "Content-Type: application/json" \
    -d "$data"
    # Create case from data
    CaseData='{"name": "Critical Alert - '$AlertActor'", "description": "'$AlertName'", "findings": "'$AlertEventPath'", "subject": "'$AlertActorID'", "assignee": null}'
    NewCase=$(curl -sk -X POST "$Code42Server"/v1/cases \
    -H "content-type: application/json" \
    -H "authorization: Bearer $BearerToken" \
    -d "$CaseData")
    #echo "$NewCase" | jq '.'
    CaseNumber=$(echo "$NewCase" | jq '.number')
    #echo "$CaseNumber"
    # Populate case from Alert
    curl -X POST "$Code42Server/v1/cases/$CaseNumber/fileevent/$AlertEventID" \
    -H "content-type: application/json" \
    -H "authorization: Bearer $BearerToken"
    # Slack message for alerting:
    AlertSlackNotification="Alert Name: $AlertName \nDescription: $AlertDesription \nUser: $AlertActor \nSeverity: $AlertSeverity \nStatus: $AlertStatus \nTimestamp: $AlertTimestamp \nURL: $AlertURL"
    SlackNotify "$AlertSlackNotification"
  fi
done

exit 0
