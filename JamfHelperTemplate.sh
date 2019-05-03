#!/bin/sh

#  JamfHelperTemplate.sh
#
#  Scott Gary on 5/2/19.
#
#define JSS variables
heading="$4"
text="$5"
JSSTrigger="$6"
process="$7"

# Log all script output
LogPath=/tmp/log
if [ ! -d "$LogPath" ];then
mkdir /tmp/log
fi

# Set log filename and path
LogFile=$LogPath/JSSHelper."$JSSTrigger".log
function SendToLog ()
{

echo "$(date +"%Y-%b-%d %T") :$1" | tee -a "$LogFile"

}

#log separator
SendToLog "###############################################################"

# Log start of script
SendToLog "Script start"

## Get Logged in User name
loggedInUser=$(stat -f%Su /dev/console)
SendToLog "$loggedInUser"

## Get Logged in User UID
loggedInUID=$(id -u "$loggedInUser")
SendToLog "$loggedInUID"

## Make sure someone is logged in or no message display is possible
if [[ "$loggedInUser" == "root" ]] && [[ "$loggedInUID" == 0 ]]; then
    echo && SendToLog "No user is logged in. Skipping display of notification until next run." |  exit 0
else

#Get date info for defferal
NextSat=$(date -v+Saturday +%s)

RunTime=$(date +%s)

calcdate=$(expr $NextSat - $RunTime)

HalfCalc=$(expr $calcdate / 2)

SendToLog "Runtime:$RunTime NextSat:$NextSat JSSHelper Values of: $calcdate $HalfCalc"

fi
#See if Application is open
if pgrep -x "$process" > /dev/null; then
    echo "$process Running"
    SendToLog "$process was open at runtime; prompting user for update"
    prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "Measures for Justice Software Updater" -heading "$heading" -alignHeading justified -description "$text" -alignDescription left -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -button1 'Update' -showDelayOptions "0, 10800, 21600, 43200, $HalfCalc, $calcdate" -timeout 3600 -countdown -lockHUD`
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
