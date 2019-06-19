#!/bin/sh
# Created by Scott Gary
# Version History:
#      6/17/19: function for jss api call
#      6/18/19: function for AppUpdate
#      6/19/19: function for checking jss values & fixed logging
# JSS Parameters:
#   $4- Log File Name (located in /private/var/log
#   $5- JSS server address
#   $6- API auth (base 64)
#   $7- EA ID #
#   $8- Jamf Helper heading
#   $9- Jamf Helper Text
#   ${10}- JSS Trigger for update policy
#   ${11}- Application name you want to see if running
##################################################################################################################################
##################################################################################################################################
# Global Vars:
LogName="$4"
JSSServer="$5"
APIAuth=$(openssl enc -base64 -d <<< "$6")
EaId="$7"
heading="$8"
text="$9"
JSSTrigger="${10}"
process="${11}"
# Hardcode title for helper messgae
title="Acme Software Updater"
# If you are not using Yo.app with custom icons change this path to match helper icon you want to display
icon="/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns"

# Log all script output
LogPath=/private/var/log
if [ ! -d "$LogPath" ];then
mkdir /private/var/log
fi

# Set log filename and path
LogFile=$LogPath/"$LogName".log
function SendToLog ()
{

echo "$(date +"%Y-%b-%d %T") : $1" | tee -a "$LogFile"

}
#log separator
SendToLog "================Script start================"

# Check JSS Par Values:
function CheckJssPar(){
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "LogName"
  if [ "$4" != "" ] && [ "$LogName" == "" ];then
    LogName=$4
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "apiPass"
  if [ "$5" != "" ] && [ "$JSSServer" == "" ];then
    JSSServer=$5
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 6 AND, IF SO, ASSIGN TO "resetUser"
  if [ "$6" != "" ] && [ "$APIAuth" == "" ];then
    APIAuth=$6
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 7 AND, IF SO, ASSIGN TO "resetUser"
  if [ "$7" != "" ] && [ "$EaID" == "" ];then
    EaId=$7
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 8 AND, IF SO, ASSIGN TO "resetUser"
  if [ "$8" != "" ] && [ "$heading" == "" ];then
    heading=$8
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 9 AND, IF SO, ASSIGN TO "resetUser"
  if [ "$9" != "" ] && [ "$text" == "" ];then
    text=$9
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 10 AND, IF SO, ASSIGN TO "resetUser"
  if [ "${10}" != "" ] && [ "$JSSTrigger" == "" ];then
    JSSTrigger=${10}
  fi
  # CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 11 AND, IF SO, ASSIGN TO "resetUser"
  if [ "${11}" != "" ] && [ "$process" == "" ];then
    process=${11}
  fi
}

function GetUserandUDID() {
  # Get Logged in User name
  loggedInUser=$(stat -f%Su /dev/console)
  SendToLog "$loggedInUser"
  # Get Logged in User UID
  loggedInUID=$(id -u "$loggedInUser")
  SendToLog "$loggedInUID"
  # Get UDID fro API
  getudid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
  SendToLog "UDID identified for API call: $getudid"
  #if root quit
  if [[ "$loggedInUser" == "root" ]] && [[ "$loggedInUID" == 0 ]]; then
    echo "No user is logged in. Skipping display of notification until next run." && SendToLog "No user logged in, skipping"
    exit 0
  fi
}

#What results do you want
results=""

# Update JSS EA's
function JSSAPICall(){
    value="$2"
    eaID="$3"
    if [ "$1" == "" ];then
    method="GET"
    fi
    curl -s -u $APIAuth "$1" "https://$JSSServer:443/JSSResource/computers/udid/$getudid/subset/extension_attributes" \
    -H "Content-Type: application/xml" \
    -H "Accept: application/xml" \
    -d "<computer><extension_attributes><extension_attribute><id>$eaID</id><value>$value</value></extension_attribute></extension_attributes></computer>"
    SendToLog "EA # $eaID was $1 new value is: $value"

}

# Application Update
function AppUpdate(){
  #Get date info for defferal
  NextSat=$(date -v+Saturday +%s)
  RunTime=$(date +%s)
  calcdate=$(expr $NextSat - $RunTime)
  HalfCalc=$(expr $calcdate / 2)
  SendToLog "Runtime:$RunTime NextSat:$NextSat JSSHelper Values of: $calcdate $HalfCalc"
  # Is Application Open
  if [ pgrep -x "$process" > /dev/null ]; then
      echo "$process Running"
      SendToLog "$process was open at runtime; prompting user for update"
      prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$text" -alignDescription left -icon "$icon" -button1 'Update' -showDelayOptions "0, 10800, 21600, 43200, $HalfCalc, $calcdate" -timeout 3600 -countdown -lockHUD`
  else
      echo && SendToLog "$process not open; proceeding to update" && jamf policy -trigger $JSSTrigger
  fi
  #what are we doing with results
  if [ "$prompt" == "1" ]; then
      echo "User elected to start immediately, Updating.."
      jamf policy -trigger "$JSSTrigger" && SendToLog "Executing policy update for $JSSTrigger"
      SendToLog "Script exit"
  else
      #var for plist execution
      delayint=$(echo "$prompt" | /usr/bin/sed 's/.$//')
      SendToLog "$delayint"
      # write launch daemon populated with variables from jamfHelper output
      /bin/cat <<EOF > /Library/LaunchDaemons/com.jamfhelper."$JSSTrigger".plist
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      <key>Label</key>
      <string>com.jamfhelper.delay</string>
      <key>LaunchOnlyOnce</key>
      <true/>
      <key>ProgramArguments</key>
      <array>
      <string>jamf</string>
      <string>policy</string>
      <string>-trigger</string>
      <string>$JSSTrigger</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>StandardErrorPath</key>
      <string>/tmp/com.jamf.deferredupdate.err</string>
      <key>StandardOutPath</key>
      <string>/tmp/com.jamf.deferredupdate.out</string>
      <key>StartInterval</key>
      <integer>$delayint</integer>
      </dict>
      </plist>
EOF
      # set ownership on launch daemon & load
      /bin/chmod 644 /Library/LaunchDaemons/com.jamfhelper."$JSSTrigger".plist
      /usr/sbin/chown root:wheel /Library/LaunchDaemons/com.jamfhelper."$JSSTrigger".plist
      /bin/launchctl unload /Library/LaunchDaemons/com.jamfhelper."$JSSTrigger".plist
      /bin/launchctl load /Library/LaunchDaemons/com.jamfhelper."$JSSTrigger".plist

  exit 0
  fi

}

# Are we updating Jamf EA's
CheckJssPar
GetUserandUDID
AppUpdate
SendToLog "$process Update ran; results are: $prompt"
JSSAPICall PUT $results $EaId
SendToLog "# $EaId Attribute Updated with: $results"
SendToLog "===========Script Exit==========="

exit 0
