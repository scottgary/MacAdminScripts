#!/bin/bash
################################################################################
#  Snipe-IT License Requests                                                   #
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
# Jamf Helper variables:
Title=""
Heading=""
HelperBinary="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
HelperIcon=""

# Slack Webook variables:
SlackHook="" #Webhook URL
Channel=""
Username=""
EMOJI=""

CurrentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

# Get user search terms:
SearchTerms=$(/usr/bin/osascript -e 'tell application "System Events" to text returned of (display dialog "Please enter Software Name:" default answer "Software Name" with title "Measures for Justice IT" buttons {"OK"} default button 1)')
# Search Snipe-IT for user query
SnipeLicenseSearch=$(curl -s -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/licenses?search=$SearchTerms")
# Get total number of results
SnipeLicenseSearchTotal=$(echo "$SnipeLicenseSearch" | grep -Eo '"total"[^,]*' | awk -F ":" '{print $2; exit}' | sed 's/"//g')
# Logic by search total:
if [[ "$SnipeLicenseSearchTotal" == 0 ]]; then
  echo "No results found for: $SearchTerms"
  Message="No software matching your search was found."
  "$HelperBinary" -windowType hud -title "$Title" -heading "$Heading" -alignHeading justified -description "$Message" -alignDescription left -icon "$HelperIcon" -button1 "Okay" -timeout 120 -lockHUD
elif [[ "$SnipeLicenseSearchTotal" == 1 ]]; then
  echo "1 result found for: $SearchTerms"
  SnipeLicenseName=$(echo "$SnipeLicenseSearch" | grep -Eo '"name"[^,]*' | awk -F ":" '{print $2; exit}' | sed 's/"//g')
  SnipeLicenseTotalSeats=$(echo "$SnipeLicenseSearch" | grep -Eo '"seats"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  SnipeLicenseFreeSeats=$(echo "$SnipeLicenseSearch" | grep -Eo '"free_seats_count"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  Message="""$SnipeLicenseName
              Total Seats: $SnipeLicenseTotalSeats
              Total Available: $SnipeLicenseFreeSeats"""
  if [[ "$SnipeLicenseFreeSeats" == 0 ]]; then
    # No Available
    echo "No Available Licenses for: $SearchTerms"
    "$HelperBinary" -windowType hud -title "$Title" -heading "$Heading" -alignHeading justified -description "$Message" -alignDescription left -icon "$HelperIcon" -button1 "Okay" -timeout 120 -lockHUD
  else
    Prompt=$("$HelperBinary" -windowType hud -title "$Title" -heading "$Heading" -alignHeading justified -description "$Message" -alignDescription left -icon "$HelperIcon" -button1 "Okay" -button2 "Request" -timeout 120 -lockHUD)
    if [[ "$Prompt" == 2 ]]; then
      echo "User request for: $SearchTerms"
      # Setup Slack hook for request:
      SlackMessage="$CurrentUser has requested a license for: \n$Message"
      Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
      # Slack API call
      curl -s -X POST --data-urlencode "$Payload" "$SlackHook"
    fi
  fi
elif [[ "$SnipeLicenseSearchTotal" -gt 1 ]]; then
  echo "Multiple results found for: $SearchTerms"
  SnipeIds=()
  SnipeLicensesNames=()
  SnipeLicensesTotalSeats=()
  SnipeLicensesFreeSeats=()
  while IFS=$'\n' read -r line;do
    SnipeIds+=("$line")
  done < <(echo "$SnipeLicenseSearch" | grep -Eo '"id"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  for((n=0;n<${#SnipeIds[@]};n++)); do
          if (( $((n % 3 )) == 0 )); then
            # Individual machine id's:
            Software=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $SnipeBearer" "$SnipeServer/licenses/${SnipeIds[$n]}" | grep -Eo '"name"[^,]*' | awk -F ":" '{print $2; exit}' | sed 's/"//g')
            SnipeLicensesNames+=("$Software")
          fi
  done
  while IFS=$'\n' read -r line;do
    SnipeLicensesTotalSeats+=("$line")
  done < <(echo "$SnipeLicenseSearch" | grep -Eo '"seats"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  while IFS=$'\n' read -r line;do
    SnipeLicensesFreeSeats+=("$line")
  done < <(echo "$SnipeLicenseSearch" | grep -Eo '"free_seats_count"[^,]*' | awk -F ":" '{print $2}' | sed 's/"//g')
  unset IFS
  # Build message payload
  Message="""The following software matches your query:
          To request a license please refine your search
  """
  ArrayCounter=0
  # Loop through custom fields to build payload:
  for i in "${SnipeLicensesNames[@]}"; do
    Message=$Message"""
    Software Name: $i
    Total Seats: ${SnipeLicensesTotalSeats[$ArrayCounter]}
    Available Seats: ${SnipeLicensesFreeSeats[$ArrayCounter]}
    """
    ArrayCounter=$((ArrayCounter+1))
  done
  "$HelperBinary" -windowType hud -title "$Title" -heading "$Heading" -alignHeading justified -description "$Message" -alignDescription left -icon "$HelperIcon" -button1 "Okay" -timeout 120 -lockHUD
fi

exit 0
