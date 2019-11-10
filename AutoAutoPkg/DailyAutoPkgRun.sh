#!/bin/bash
################################################################################
#  AutoAutoPkg    Created by: Scott Gary                                       #
#  Version History:                                                            #
#                  11/7/19 inital structure and design                         #
#                  11/10/19 Better error handling                              #
################################################################################

# Jamf Variables:
JamfServer="" # full https:// address with :{port}
JSSUser="" # Must have permissions for packages, polices, patch policies and Patch Management Software Titles c,r,u
JSSPass=""

# Patch Server Variables:
PatchServer="" # "/$AppName/Version" will be called after
PatchBearer="" # API Token
PatchScript="/Users/Shared/patchstarter.py"

# Slack Variables
SlackHook="" #Webhook URL
Channel=""
Username=""
EMOJI="" # Used as user icon

# AutoPkg Variables:
SoftwareTitles="/Users/Shared/AutoAutoPkg/AutoAutoPkgSoftwareTitles.txt"
JamfPolicyList="/Users/Shared/AutoAutoPkg/AutoAutoPkgPolicies.txt"
ReportList="/Users/Shared/AutoAutoPkg/AutoPkgRun.plist"
recipe_list="/Users/Shared/AutoAutoPkg/recipe_list.txt"  # see https://github.com/autopkg/autopkg/wiki/Running-Multiple-Recipes for setup of .txt file

JamfCheck(){
  if [ -z "$JamfServer" ]; then
    echo "No Jamf server found; exiting"
    exit 1
  else
    if [ -z "$JSSUser" ]; then
      echo "No Jamf user account found; exiting"
      exit 1
    else
      if [ -z "$JSSPass" ]; then
        echo "No Jamf user password found; exiting"
        exit 1
      else
        echo "Checking JSS Permissions"
        SwTitlesCheck=$(curl -s -u "$JSSUser:$JSSPass" -X GET "$JamfServer/JSSResource/patchsoftwaretitles")
        PatchCheck=$(curl -s -u "$JSSUser:$JSSPass" -X GET "$JamfServer/JSSResource/patchpolicies")
        PolicyCheck=$(curl -s -u "$JSSUser:$JSSPass" -X GET "$JamfServer/JSSResource/policies")
        if [ -z "$SwTitlesCheck" ]; then
          echo "Permissions to Software Titles not set; exiting"
          exit 1
        else
          if [ -z "$PatchCheck" ]; then
            echo "Permissions to Patch Policies not set; exiting"
            exit 1
          else
            if [ -z "$PolicyCheck" ]; then
              echo "Permissions to Policies not set; exiting"
              exit 1
            else
              echo "All Jamf read permissions set"
            fi
          fi
        fi
      fi
    fi
  fi
}

SlackNotify(){
  AppAndVersion="$1"
  if [ -z "$SlackHook" ]; then
    echo "No webhook url found; skipping"
  else
    if [ -z "$Channel" ]; then
      echo "No Slack desination found; skipping"
    else
      if [ -z "$Username" ]; then
        echo "No Slack name specified; skipping"
      else
        if [ -z "$EMOJI" ]; then
          echo "No user icon specified; skipping"
        else
          if [ -z "$AppAndVersion" ]; then
            SlackMessage="Daily AutoPkg Run:\nNo new titles"
            Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
            curl -s -X POST --data-urlencode "$Payload" "$SlackHook"
          else
            SlackMessage="New Software Available: \n$AppAndVersion"
            Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
            curl -s -X POST --data-urlencode "$Payload" "$SlackHook"
          fi
        fi
      fi
    fi
  fi
}

AutoPkgCheck(){
  if [ -z "$SoftwareTitles" ]; then
    echo "No software titles list found; exiting"
    exit 1
  else
    if [ -z "$JamfPolicyList" ]; then
      echo "No Jamf Policy list found; exiting"
      exit 1
    else
      if [ -z "$ReportList" ]; then
        echo "No outpput path found; exiting"
        exit 1
      else
        if [ -z "$recipe_list" ]; then
          echo "No recipe list found; exiting"
          exit 1
        else
          AutoPkgRepo=$(defaults read com.github.autopkg CACHE_DIR)
          if [ -z "$AutoPkgRepo" ]; then
            AutoPkgRepo="$HOME/Library/AutoPkg/Cache"
            export AutoPkgRepo="$AutoPkgRepo"
          else
            echo "All AutoPkg veriables verified"
            export AutoPkgRepo="$AutoPkgRepo"
          fi
        fi
      fi
    fi
  fi
}

PkgUpload(){
  PkgName="$1"
  PkgPath="$2"
  if [ -z "$PkgPath" ]; then
    echo "Only download policy found; skipping Jamf upload"
  else
    #Upload to Jamf
    PkgUpload=$(curl -u $JSSUser:$JSSPass -X POST \
      "$JamfServer"/dbfileupload \
      -H 'DESTINATION: 0' \
      -H 'OBJECT_ID: -1' \
      -H 'FILE_TYPE: 0' \
      -H 'FILE_NAME: '$PkgName \
      -T $PkgPath)
    # Get New Package ID
    PkgId=$(echo "$PkgUpload" | awk -F "<id>" '{print $2}' | awk -F "</id" '{print $1}')
    export PkgId="$PkgId"
  fi
}

PatchDef(){
  # Patch Server Update
  AppName="$1"
  AppPath="$2"
  if [ -z "$PatchServer" ]; then
    echo "No patch server defined; skipping"
  else
    if [ -z "$PatchBearer" ]; then
      echo "No API token found; skippimg"
    else
      if [ -z "$PatchScript" ]; then
        echo "No patching script found; skipping"
      else
        if [ -z "$AppPath" ]; then
          echo "No .app found; skipping Path Def"
        else
          curl -s -X POST \
            "$PatchServer/$AppName/version?=" \
            -H 'Accept: */*' \
            -H "Authorization: Bearer $PatchBearer" \
            -H 'Content-Type: application/json' \
            -H 'Host: jamf-patch.mfj.io' \
            -d "$(python "$PatchScript" "$AppPath" --patch-only)"
        fi
      fi
    fi
  fi
}

PatchUpdate(){
  # Find ID's
  AppName="$1"
  ReleaseVersion="$2"
  PatchVersionId=$(cat "$SoftwareTitles" | grep -i "$AppName" | awk -F " " '{print $2}')
  if [ -z "$PatchVersionId" ]; then
    echo "No software title id found; skipping patch definition update"
  else
    PatchId=$(cat "$JamfPolicyList" | grep -i "$AppName" | awk -F " " '{print $3}' )
    # Get Jamf Version
    JamfVersion=$(curl -sv -H "Accept: application/xml" -u "$JSSUser":"$JSSPass" "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X GET)
    until [ "$ReleaseVersion" == "$JamfVersion" ]
    do
      JamfVersion=$(curl -sv -H "Accept: application/xml" -u "$JSSUser":"$JSSPass" "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X GET)
    done
    # Update Patch Def
    DefPkgChange="<patch_software_title><versions><version><software_version>$JamfVersion</software_version><package><id>$PkgId</id></package></version></versions></patch_software_title>"​
    curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/patchsoftwaretitles/id/$PatchVersionId" -X PUT \
    -H "Content-type: application/xml" \
    -d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$DefPkgChange"
    # Update Patch Policy
    PatchChange="<patch_policy><general><target_version>$JamfVersion</target_version></general></patch_policy>"​
    curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/patchpolicies/id/$PatchId" -X PUT \
    -H "Content-type: application/xml" \
    -d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$PatchChange"
  fi
}

InstallUpdate(){
  # Update Install Policy
  PkgId="$1"
  AppName="$2"
  InstallId=$(cat "$JamfPolicyList" | grep -i "$AppName" | awk -F " " '{print $2}' )
  if [ -z "$InstallId" ]; then
    echo "No Jamf install policy id found; skipping update"
  else
    InstallPkgChange="<policy><package><package_configuration><packages><package><id>$PkgId</id></package></packages></package_configuration></policy>"​
    curl -s -u $JSSUser:$JSSPass "$JamfServer/JSSResource/policies/id/$InstallId" -X PUT \
    -H "Content-type: application/xml" \
    -d "<?xml version=\"1.0\" encoding=\"UTF-8\"?>$InstallPkgChange"
  fi
}

AutoPkgRun(){
  # AutoPkg Run:
  /usr/local/bin/autopkg run --recipe-list="$recipe_list" --report-plist "$ReportList"

  # Check for new pkgs:
  AutoPkgResults=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3}')
  # If nothing we are sending a slack notification and exiting:
  if [ -z "$AutoPkgResults" ]; then
    # Slack Webhook
    SlackNotify
    exit 0
  else
    # If we made it here there are new builds. Make array of new run:
    declare -a ResultArray
    mapfile -t ResultArray < <(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | awk -F "/" '{print $6}' | awk -F "-" '{print $1}')
    for i in "${ResultArray[@]}"
    do
      AppName="$i"
      AppPath=$(find "$AutoPkgRepo" -iname "$AppName.app")
      PkgPath=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | grep "$AppName")
      PkgName=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | grep "$AppName" | awk -F "/" '{print $6}')
      AppAndVersion=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | awk -F "/" '{print $6}' | awk -F "-" '{print $1,$2}' | sed 's/\.pkg//g' | grep "$AppName")
      ReleaseVersion=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | awk -F "/" '{print $6}' | awk -F "-" '{print $1,$2}' | sed 's/\.pkg//g' | grep "$AppName" | awk '{print $2}')
      PkgUpload "$PkgName" "$PkgPath"
      PatchDef "$AppName" "$AppPath"
      PatchUpdate "$AppName" "$ReleaseVersion"
      InstallUpdate "$PkgId" "$AppName"
    done
    #Slack Notification
    AppAndVersion=$(/usr/libexec/PlistBuddy -c "Print :summary_results:pkg_creator_summary_result" "$ReportList" | grep "pkg_path" | awk '{print $3, $4}' | awk -F "/" '{print $6}' | awk -F "-" '{print $1,$2}' | sed 's/\.pkg//g')
    SlackNotify "$AppAndVersion"
  fi
}

JamfCheck
AutoPkgCheck
AutoPkgRun

exit 0
