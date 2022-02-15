#!/bin/bash
#
# 11/10/19 Scott Gary
#
# In-House Automation
################################################################################
NexusUsername=""
NexusPass=""
NexusName="" # Nexus Name for repo (i.e unbox-gui)
AppName=""
BuildNum="" # ${VERSION}
# Jamf Variables
JSSUser=""
JSSPass=""
JamfServer=""
#DevAdmin ID info
DevId=""
DevPw=""
AdminAccount=""
# Make needed DIR
mkdir -p ROOT/Applications/Research\ Tools
mkdir Scripts

# Notarize function for reuse:
NotarizeMe(){
  NotarizePath="$1"
  AppPath="$2"
  # Send Notarization
  Req=$(/usr/bin/xcrun altool --notarize-app \
    --primary-bundle-id "com.example.$AppName" \
    --username "$DevId" --password "$DevPw" \
    --file "$NotarizePath" \
    --output-format "xml")
  ReqUUID=$(echo "$Req" | awk '/RequestUUID/ {getline;print}' | awk -F "<string>" '{print $2}' | awk -F "</string>" '{print $1}')
  # Wait for reuest success
  until [ "$ReqUUID" == "success" ]
  do
    ReqUUID=$(/usr/bin/xcrun altool --notarization-info "$ReqUUID" -u "$DevId" -p "$DevPw" | grep "Status:" | awk -F " " '{print $2}')
  done
  # Step 3: staple the ticket
  sudo -u $AdminAccount /usr/bin/xcrun stapler staple "$AppPath"
}

# Download new build:
curl -s -u "$NexusUsername:$NexusPass" "https://nexus.mfj.io/repository/maven-releases/io/mfj/$NexusName/$BuildNum/$NexusName-$BuildNum-app.zip" > "$AppName.app.zip"
# Unzip download and Notarize new release:
unzip -qq "$AppName.app" -d "ROOT/Applications/Research Tools/"
# Notarize App:
NotarizeMe "$AppName.app.zip" "ROOT/Applications/Research Tools/$AppName.app"

# Upload new patch to PatchServer
curl -s -X POST \
  "https://jamf-patch.example.io/api/v1/title/$AppName/version?=" \
  -H 'Accept: */*' \
  -H "Authorization: Bearer $JamfAPIToken" \
  -H 'Content-Type: application/json' \
  -H 'Host: jamf-patch.mfj.io' \
  -d "$(python /Users/Shared/patchstarter.py ROOT/Applications/Research\ Tools/"$AppName".app --patch-only)"

# Find preinstall script
PreInstallScript=$(find /Users/Shared/PreInstallScripts/"$AppName"PreInstall.sh)
cp -f "$PreInstallScript" Scripts/preinstall
chmod a+x Scripts/preinstall

# PKG and sign
pkgbuild --quiet --root "ROOT" --sign "Measures for Justice (XUDASH3VHA)" --scripts Scripts "$AppName.$BuildNum.pkg"
cp -f "$AppName.$BuildNum.pkg" "$HOME/Desktop/$AppName.$BuildNum.pkg"

# Get pacage ready for upload:
PkgName="$AppName.$BuildNum.pkg"
PkgPath="$PWD/$AppName.$BuildNum.pkg"
# Notarize PKG
NotarizeMe "$PkgPath" "$PkgPath"

#Upload to Jamf
PkgUpload=$(curl -u $JSSUser:$JSSPass -X POST \
  "$JamfServer"/dbfileupload \
  -H 'DESTINATION: 0' \
  -H 'OBJECT_ID: -1' \
  -H 'FILE_TYPE: 0' \
  -H 'FILE_NAME: '$PkgName \
  -T $PkgPath )

# Get New Package ID
PkgId=$(echo "$PkgUpload" | awk -F "<id>" '{print $2}' | awk -F "</id" '{print $1}')

# Check for new Patch Def in JamfServer
PatchVersionId=$(cat /Users/Shared/AutoAutoPkg/InHousePatchTitles.txt | grep -i "$AppName" | awk -F " " '{print $2}' )
JamfVersion=$(curl -sv -H "Accept: application/xml" -u "$JSSUser":"$JSSPass" "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X GET)
until [ "$BuildNum" == "$JamfVersion" ]
do
  JamfVersion=$(curl -sv -H "Accept: application/xml" -u "$JSSUser":"$JSSPass" "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X GET)
done

# Update new definition:
DefPkgChange="<patch_software_title><versions><version><software_version>$JamfVersion</software_version><package><id>$PkgId</id></package></version></versions></patch_software_title>"​
curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X PUT \
-H "Content-type: application/xml" \
-d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$DefPkgChange"

# Update install policy:
InstallId=$(cat /Users/Shared/AutoAutoPkg/InHousePolicies.txt | grep -i "$AppName" | awk -F " " '{print $2}' )
InstallPkgChange="<policy><package><package_configuration><packages><package><id>$PkgId</id></package></packages></package_configuration></policy>"​
curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/policies/id/$InstallId" -X PUT \
-H "Content-type: application/xml" \
-d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$InstallPkgChange"

# Update patch policy:
PatchId=$(cat /Users/Shared/AutoAutoPkg/InHousePolicies.txt | grep -i "$AppName" | awk -F " " '{print $3}' )
PatchChange="<patch_policy><general><target_version>$JamfVersion</target_version></general></patch_policy>"​
curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/patchpolicies/id/$PatchId" -X PUT \
-H "Content-type: application/xml" \
-d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$PatchChange"
