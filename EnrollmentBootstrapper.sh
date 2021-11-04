#!/bin/bash
################################################################################
#  Automated Enrollment  Created by: Scott Gary                                #
#  Find computer info for classifcation                                        #
#  Jamf API usage needed for gathering and placing info                        #
#  Snipe IT API can be used for automated inventory management                 #
################################################################################
# Global vars
JamfServer=""
JamfPass=""
# Title for Jamf Helper & osascript
title=""
# Arrays for triggered Policies
# As Apple silicon appplication versions become available they need to be added to this array:
M1Software=("ZoomM1" "ChromeM1")
AllCompanySoftware=("Chrome" "Firefox" "Yo" "Zoom" "install-code42" "1Password" "Slack")
EngSoftware=("iTerm2" "DevTools" "Docker" "Atom" "Tuple")
SupportSoftware=("MicrosoftOffice") # Steve Input: Office 365
WorkplaceHRSoftware=("Dropbox")
ITSoftware=("JamfPro" "Postman" "Atom")

# Get the currently logged in user
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
echo "Current user is $loggedInUser"

# get UID for current User
currentUID=$(id -u "$loggedInUser")
echo "$loggedInUser UID is $currentUID"

# Check and see if we're currently running as the user we want to setup - pause and wait if not
while [ "$currentUID" -ne 502 ] && [ "$currentUID" -ne 501 ]; do
    echo "Currently logged in user is NOT the 501 or 502 user. Waiting."
    sleep 2
    loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
    currentUID=$(id -u "$loggedInUser")
    echo "Current user is $loggedInUser with UID $currentUID"
done

# Now that we have the correct user logged in - need to wait for the login to complete so we don't start too early
dockStatus=$(pgrep -x Dock)
echo "Waiting for Desktop"
while [ "$dockStatus" == "" ]; do
  echo "Desktop is not loaded. Waiting."
  sleep 2
  dockStatus=$(pgrep -x Dock)
done

# Determine if we are on M1 or not:
# Save current IFS state
OLDIFS=$IFS
# Determine OS version
IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"
# restore IFS to previous state
IFS=$OLDIFS
# Check to see if the Mac is reporting itself as running macOS 11
if [[ ${osvers_major} -ge 11 ]]; then
  # Check to see if the Mac needs Rosetta installed by testing the processor
  processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string | grep -o "Intel")
  if [[ -n "$processor" ]]; then
    echo "$processor processor installed. No need to install Rosetta."
    IsM1Mac="No"
  else
    IsM1Mac="Yes"
    # Check Rosetta LaunchDaemon. If no LaunchDaemon is found,
    # perform a non-interactive install of Rosetta.
    if [[ ! -f "/Library/Apple/System/Library/LaunchDaemons/com.apple.oahd.plist" ]]; then
        /usr/sbin/softwareupdate –install-rosetta –agree-to-license
        if [[ $? -eq 0 ]]; then
        	echo "Rosetta has been successfully installed."
        else
        	echo "Rosetta installation failed!"
        fi
    else
    	echo "Rosetta is already installed. Nothing to do."
    fi
  fi
  else
    echo "Mac is running macOS $osvers_major.$osvers_minor.$osvers_dot_version."
    echo "No need to install Rosetta on this version of macOS."
fi


# Get serial number
NewSerial=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')

# User GUI for entering hover.to email with regex checker; Spit out file > /private/var/localuser.txt
UserEmail=$(/usr/bin/osascript << EOF
tell application "System Events" to text returned of (display dialog "Please enter your HOVER email:" default answer "first.last@hover.to" buttons {"OK"} default button 1)
EOF
)
echo "User Input: $UserEmail"
# Check to make sure user didn't just cick okay with example text:
until [[ "$UserEmail" != "first.last@hover.to" ]]; do
  echo "User is pulling a sneaky on ya"
  sleep 2
  UserEmail=$(/usr/bin/osascript << EOF
  tell application "System Events" to text returned of (display dialog "Good One! But, please enter your valid HOVER email:" default answer "first.last@hover.to" buttons {"OK"} default button 1)
EOF
)
  echo "User Input: $UserEmail"
done
# REGEX checker for valid @hover.to email
while [[ ! "${UserEmail}" =~ ^[a-z]{2,10}\.[a-z]{2,10}@hover\.to$ ]] || [[ ! "${UserEmail}" =~ ^[a-z]{2,10}@hover\.to$ ]]; do
  echo "User did not enter valid email"
  sleep 2
  UserEmail=$(/usr/bin/osascript << EOF
  tell application "System Events" to text returned of (display dialog "Please enter your HOVER email:" default answer "first.last@hover.to" buttons {"OK"} default button 1)
EOF
)
  echo "User Input: $UserEmail"
  # Check to make sure user didn't just cick okay with example text:
  if [[ "$UserEmail" == "first.last@hover.to" ]]; then
    echo "User is pulling a sneaky on ya Part2"
    until [[ "$UserEmail" != "first.last@hover.to" ]]; do
      sleep 2
      UserEmail=$(/usr/bin/osascript << EOF
      tell application "System Events" to text returned of (display dialog "Good One! But, please enter your valid HOVER email:" default answer "first.last@hover.to" buttons {"OK"} default button 1)
EOF
)
      echo "User Input: $UserEmail" >> /private/var/UserInfo.txt
    done

  fi

done

# Udate Jamf user:
/usr/local/bin/jamf recon -email "${UserEmail}"


# Installing all-org Apps
echo "Installing all org Apps"
# Full Screen Window blocks user while all org software installs
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -title "$title" -heading "Please wait while IT installs software" -alignHeading justified -description "This process will automatically configure your Mac for MFJ use. Please do not power off your Mac and report any issues to IT immediately. This screen will automatically close once organizational apps are installed. Please do not turn off your Mac." -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FinderIcon.icns -windowType hud &
# Check for M1 status and deploy all company apps:
if [[ "$IsM1Mac" == "Yes" ]]; then
  echo "Deploying Apple Silicon versions"
  for i in "${M1Software[@]}"; do
    echo "Deploying $i"
    /usr/local/bin/jamf policy -event "$i"
    # Sleep between runs
    sleep 3
   done
# Deploy Intel version of all company apps:
else
  for i in "${AllCompanySoftware[@]}"
  do
   echo "Deploying $i"
   /usr/local/bin/jamf policy -event "$i"
   # Sleep between runs
   sleep 3
  done
fi
# Kill fullscreen helper Screen
killall jamfHelper

# Get Computer Dept
JamfDepartment=$(curl -ksH "authorization: Basic $JamfPass" \
-X GET \
-H "accept: text/xml" \
"$JamfServer"/JSSResource/computers/serialnumber/"$NewSerial" | xmllint --xpath '/computer/location/department/text()' -)
echo "Jamf Dept: $JamfDepartment"

## buid computer name
computerName="${loggedInUser}-${JamfDepartment}"
echo "Set computer name to: $computerName"
# update Jamf
/usr/local/bin/jamf setComputerName -name "${computerName}"

# Install Eng Apps
if [ "${JamfDepartment}" == "Engineering" ] || [ "${JamfDepartment}" == "DevOps" ]; then
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -title "$title" -heading "Installing Departmental Apps" -description "Your Mac will need to restart once complete to begin disk encryption." -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -timeout 20 -lockHUD
  echo "Install Engineering Apps"
  for i in "${EngSoftware[@]}"
  do
   echo "Deploying $i"
   /usr/local/bin/jamf policy -event "$i"
   # Sleep between runs
   sleep 3
  done
# Install Support Apps
elif [ "${JamfDepartment}" == "Customer Support" ] || [ "${JamfDepartment}" == "Sales" ]; then
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -title "$title" -heading "Installing Departmental Apps" -description "Your Mac will need to restart once complete to begin disk encryption." -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -timeout 20 -lockHUD
  echo "Installing support/sales Apps"
  for i in "${SupportSoftware[@]}"
  do
   echo "Deploying $i"
   /usr/local/bin/jamf policy -event "$i"
   # Sleep between runs
   sleep 3
  done
# Install Workplace/HR Apps
elif [ "${JamfDepartment}" == "HR" ] || [ "${JamfDepartment}" == "Finance" ] || [ "${JamfDepartment}" == "Accounting" ] || [ "${JamfDepartment}" == "Recruiting" ]; then
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -title "$title" -heading "Installing Departmental Apps" -description "Your Mac will need to restart once complete to begin disk encryption." -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -timeout 20 -lockHUD
  echo "Installing Workplace Apps"
  for i in "${WorkplaceHRSoftware[@]}"
  do
   echo "Deploying $i"
   /usr/local/bin/jamf policy -event "$i"
   # Sleep between runs
   sleep 3
  done
# Install Sales Apps
elif [ "${JamfDepartment}" == "IT" ]; then
  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -title "$title" -heading "Installing Departmental Apps" -description "Your Mac will need to restart once complete to begin disk encryption." -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -timeout 20 -lockHUD
  echo "Installing IT Apps"
  for i in "${ITSoftware[@]}"
  do
   echo "Deploying $i"
   /usr/local/bin/jamf policy -event "$i"
   # Sleep between runs
   sleep 3
  done
fi

# Restart required for FileVault
/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType hud -title "$title" -heading "Enrollment Complete" -description "Your Mac will now restart to begin encryption" -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -timeout 10 -lockHUD
/usr/local/bin/jamf reboot & exit 0
