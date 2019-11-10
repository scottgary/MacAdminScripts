#!/bin/bash
#
#  8/22/19 SG notarization workflow
#DevAdmin ID info
acct=""
pw=""

# Prompt user for app path or pkg path
AppPath="$1"
PkgPath="$2"

#If run without input exit
if [ -z "$AppPath" ] && [ -z "$PkgPath" ]; then
  echo "User input empty; exiting..."
  exit 0
fi

#If just pkg is given
if [[ $AppPath == *.pkg ]]; then
  echo "PKG file specified; Attempting to notarize"
  #Notarize pkg
  xcrun altool --notarize-app --primary-bundle-id "org.MFJ.InHouse.zip" --username "$acct" --password "$pw" --file "$AppPath"
  # Step 2: check for results
  xcrun altool --notarization-history 0 -u "$acct" -p "$pw"
  # Step 3: staple the ticket $2 is path to pkg
  xcrun stapler staple "$AppPath"
fi

#If just app.zip is given
if [[ $AppPath == *.zip ]] && [[ -z $PkgPath ]]; then
  echo "app.zip Specified; attempting to notarize application"
  #Notarize pkg
  xcrun altool --notarize-app --primary-bundle-id "org.MFJ.InHouse.zip" --username "$acct" --password "$pw" --file "$AppPath"
  # Step 2: check for results
  xcrun altool --notarization-history 0 -u "$acct" -p "$pw"
  # Step 3: staple the ticket $2 is path to pkg
  xcrun stapler staple "$AppPath"
fi

if [[ $AppPath == *.zip ]] && [[ $PkgPath == *.pkg ]]; then
  echo "Pkg and .app Specified; attempting to notarize application and installer"
  #Notarize pkg
  xcrun altool --notarize-app --primary-bundle-id "org.MFJ.InHouse.zip" --username "$acct" --password "$pw" --file "$AppPath"
  # Step 2: check for results
  xcrun altool --notarization-history 0 -u "$acct" -p "$pw"
  # Step 3: staple the ticket $2 is path to pkg
  xcrun stapler staple "$AppPath"
  #Notarize pkg
  xcrun altool --notarize-app --primary-bundle-id "org.MFJ.InHouse.zip" --username "$acct" --password "$pw" --file "$PkgPath"
  # Step 2: check for results
  xcrun altool --notarization-history 0 -u "$acct" -p "$pw"
  # Step 3: staple the ticket $2 is path to pkg
  xcrun stapler staple "$PkgPath"
fi
