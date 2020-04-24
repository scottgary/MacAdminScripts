#!/bin/bash

###############################################################################
# 4/22/20 - Scott Gary                                                        #
# Delete (Legacy) copy of Harvest app for VPP install                         #
###############################################################################
CurrUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

HarvestPath=$(ls /Applications | grep -i "Harvest")
if [ -z "$HarvestPath" ]; then
  echo "No Harvest Install found"
else
  echo "Harvest found: $HarvestPath"
fi
HarvestVersion=$(defaults read /Applications/Harvest.app/Contents/info.plist | grep "CFBundleShortVersionString" | awk -F "=" {'print $2'} | awk -F "\"" {'print $2'})
if [ "$HarvestVersion" == "2.2.1" ]; then
  echo "User on newest release"
else
  echo "User needs updated App Store app; deleting old copy"
  rm -rf /Applications/Harvest.app
fi

OldHarvest=$(ls /Applications | grep -i "Harvest(Legacy)")
if [ -z "$OldHarvest" ]; then
  echo "No Legacy install found; exiting"
else
  echo "Legacy install found; deleting"
  rm -rf /Applications/Harvest\(Legacy\).app
fi

NewHarvest=$(ls /Applications | grep -i "Harvest")

sudo -u "$CurrUser" defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>/Applications/Harvest.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"; killall Dock

# Update inventory before quitting
/usr/local/bin/jamf recon

exit 0
