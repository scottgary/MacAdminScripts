#!/bin/bash

##############################################################################
# Jamf Helper Template Deferral Script                                       #
#  ScottGary 10/14/2020                                                      #
#                                                                            #
##############################################################################
# Global Vars:
title="$4"
heading="$5"
text="$6"
Defer1="$7"
Defer2="$8"
Defer3="$9"
Defer4="${10}"
Trigger="${11}"
AppName=""
PlistName="com.jamfsoftware.SoftwareUpdater$AppName.plist"
##############################################################################
##############################################################################
# Var error handling
if [[ -z "$title" ]] || [[ -z "$heading" ]] || [[ -z "$text" ]] || [[ -z "$Defer1" ]] || [[ -z "$Defer2" ]] || [[ -z "$Defer3" ]] || [[ -z "$Defer4" ]] || [[ -z "$Trigger" ]] || [[ -z "$PlistName" ]]; then
  echo "blank vars! exiting"
  exit 0
fi

# defer options
buttonWithDelay=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "Adjust your System Power Manager" -heading "$heading" -alignHeading justified -description "$text" -alignDescription left -icon /Applications/Self\ Service.app/Contents/Resources/AppIcon.icns -button1 'Select' -showDelayOptions "0, $Defer1, $Defer2, $Defer3, $Defer4" -timeout 120 -countdown -lockHUD)
echo "$buttonWithDelay"
SelectedTime=${buttonWithDelay%?}
echo "$SelectedTime"
# Get Date for Daemon
Epoch=$(date '+%s')
Epoch2=$(( Epoch + SelectedTime ))
NewMonth=$(date -jf %s "$Epoch2" "+%m")
NewDay=$(date -jf %s "$Epoch2" "+%d")
NewHour=$(date -jf %s "$Epoch2" "+%H")
NewMinute=$(date -jf %s "$Epoch2" "+%M")


LaunchDaemon='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jamfsoftware.task.MacOSUpdates</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/jamf/bin/jamf</string>
    <string>policy</string>
    <string>-event</string>
    <string>'$Trigger'</string>
  </array>
  <key>StartCalendarInterval</key>
	<dict>
    <key>Month</key>
    <integer>'$NewMonth'</integer>
		<key>Hour</key>
		<integer>'$NewHour'</integer>
    <key>Minute</key>
    <integer>'$NewMinute'</integer>
		<key>Weekday</key>
		<integer>'$NewDay'</integer>
	</dict>
  <key>UserName</key>
  <string>root</string>
</dict>
</plist>'

if [[ "$SelectedTime" == "$Defer1" ]] || [[ "$SelectedTime" == "$Defer2" ]] || [[ "$SelectedTime" == "$Defer3" ]] || [[ "$SelectedTime" == "$Defer4" ]]; then
  /usr/bin/tee "/Library/LaunchDaemons/$PlistName" << EOF
  $(echo "$LaunchDaemon")
EOF
elif [[ "$SelectedTime" = 0 ]]; then
  echo "running now"
  /usr/local/bin/jamf policy -event "$Trigger"
else
  echo "Something went wrong!"
fi
# Daemon Permissions:

/usr/sbin/chown root:wheel "/Library/LaunchDaemons/$PlistName"
/bin/chmod 644 "/Library/LaunchDaemons/$PlistName"
/bin/launchctl bootstrap system "/Library/LaunchDaemons/$PlistName"
