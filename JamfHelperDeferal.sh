#!/bin/bash

#########################################################################################################################################################################################################
# Jamf Helper Template Deferral Script                                                                                                                                                                  #
#  ScottGary 10/14/2020                                                                                                                                                                                 #
#  Triggered policy should have "Files & Processes" enabled and execute:                                                                                                                                #
#  `launchctl bootout system /Library/LaunchDaemons/com.jamfsoftware.PolicyDeferal.{YOUR_TRIGGER}.plist | rm -rf /Library/LaunchDaemons/com.jamfsoftware.PolicyDeferal.{YOUR_TRIGGER}.plist'            #
#                                                                                                                                                                                                       #
#########################################################################################################################################################################################################
# Global Vars:
title="$4"
heading="$5"
text="$6"
Defer1="$7"
Defer2="$8"
Defer3="$9"
Defer4="${10}"
Trigger="${11}"
PlistName="com.jamfsoftware.PolicyDeferal.$Trigger.plist"
##############################################################################
##############################################################################
# Var error handling
if [[ -z "$title" ]] || [[ -z "$heading" ]] || [[ -z "$text" ]] || [[ -z "$Defer1" ]] || [[ -z "$Defer2" ]] || [[ -z "$Defer3" ]] || [[ -z "$Defer4" ]] || [[ -z "$Trigger" ]] || [[ -z "$PlistName" ]]; then
  echo "Jamf Parameters Missing; exiting..."
  exit 0
fi

# Fuction for getting epoch time into daemon:
TimeForDaemon(){
  InputTime="$1"
  Epoch=$(date '+%s')
  Epoch2=$(( Epoch + InputTime ))
  NewMonth=$(date -jf %s "$Epoch2" "+%m")
  NewDay=$(date -jf %s "$Epoch2" "+%d")
  NewHour=$(date -jf %s "$Epoch2" "+%H")
  NewMinute=$(date -jf %s "$Epoch2" "+%M")
}

# Jamf Helper binary: Change -title to fit your org. This uses the -icon for Self Service for custom branding.
buttonWithDelay=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$text" -alignDescription left -icon /Applications/Self\ Service.app/Contents/Resources/AppIcon.icns -button1 'Select' -showDelayOptions "0, $Defer1, $Defer2, $Defer3, $Defer4" -timeout 120 -countdown -lockHUD)
echo "$buttonWithDelay"
# Take off Jamf Helper Button Return Code
SelectedTime=${buttonWithDelay%?}
echo "$SelectedTime"

TimeForDaemon "$SelectedTime"

# Write out Launch Daemon using StartCalendarInterval instead of StartInterval to make sure it still runs on time if computer rebooted
LaunchDaemon='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jamfsoftware.PolicyDeferal.'$Trigger'</string>
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

# If user selected to delay:
if [[ "$SelectedTime" == "$Defer1" ]] || [[ "$SelectedTime" == "$Defer2" ]] || [[ "$SelectedTime" == "$Defer3" ]] || [[ "$SelectedTime" == "$Defer4" ]]; then
  /usr/bin/tee "/Library/LaunchDaemons/$PlistName" << EOF
  $(echo "$LaunchDaemon")
EOF
  # Daemon Permissions:
  /usr/sbin/chown root:wheel "/Library/LaunchDaemons/$PlistName"
  /bin/chmod 644 "/Library/LaunchDaemons/$PlistName"
  /bin/launchctl bootstrap system "/Library/LaunchDaemons/$PlistName"
elif [[ "$SelectedTime" = 0 ]]; then
  # User selected to run immediately
  echo "executing policy now"
  /usr/local/bin/jamf policy -event "$Trigger"
else
  # If countdown runs out or other errors exist
  echo "Something went wrong!"
fi

exit 0
