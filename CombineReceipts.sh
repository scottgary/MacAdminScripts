#!/bin/bash

#  combine.receipts.sh
#
#
#  Created by Scott Gary on 1/4/19.
#      # Updated 11/15/19 for docx suppport (LibreOffice Required)
# Slack Variables
SlackHook="" #Webhook URL
Channel=""
Username=""
EMOJI="" # Used as user icon
#
CurrentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
MSG="Help make this tool even better!

Installing Libre Office will allow you to also convert .docx (Word Documents) with your receipts too! Click Install Now to install LibreOffice and continue or install in Self-Service later under the Office Category

*NOTE* Installation requires user approval for access to your Documents folder.

Once LibreOffice is installed please grant the application access to your Documents Folder by:

1. Open System Preferences > Security & Privacy
2. Navigate to the Privacy tab and select Files and Folders from the left
3. Allow LibreOffice access to your Documents."

SlackNotify(){
  User="$1"
  SlackMessage="New receipts proccessed by $User \nSee: https://drive.google.com/drive/u/0/folders/1-fjg4Fk1KWGXt7kcJJp7w_dNjF2tbym1"
  Payload="payload={\"channel\": \"$Channel\", \"username\": \"$Username\", \"text\": \"$SlackMessage\", \"icon_emoji\": \"$EMOJI\"}"
  curl -s -X POST --data-urlencode "$Payload" "$SlackHook"

}

ConvertPNG(){
  # Check for PNGs
  NewPngs=$(find /Users/"$CurrentUser"/Documents/Receipts/*.png )
  if [ -z "$NewPngs" ]; then
    echo "No new pngs found for report; skipping"
  else
    # Convert png files to PDF for concatenate
    for i in $NewPngs
    do
      sips -s format pdf  "${i}" --out /Users/"$CurrentUser"/Documents/Receipts/
    done
  fi

}

ConvertJPG(){
  # Check for JPGs
  NewJpgs=$(find /Users/"$CurrentUser"/Documents/Receipts/*.jpg )
  NewJpegs=$(find /Users/"$CurrentUser"/Documents/Receipts/*.jpeg )
  if [ -z "$NewJpgs" ]; then
    echo "No new jpg pictures found for report; skipping"
  else
    if [ -z "$NewJpegs" ]; then
      echo "No new jpeg pictures found for report; skipping"
    else
      # Convert jpg files to png for concatenate
      for i in /Users/"$CurrentUser"/Documents/Receipts/*.jpg
        do sips -s format png -s formatOptions 70 "${i}" --out "${i%jpg}png"
      done
      for i in /Users/"$CurrentUser"/Documents/Receipts/*.jpeg
        do sips -s format png -s formatOptions 70 "${i}" --out "${i%jpeg}png"
      done
    fi
  fi
}

ConvertDOC(){
  # Check for LibreOffice:
  LibreCheck=$(find /Applications/LibreOffice.app )
  if [ -z "$LibreCheck" ]; then
    echo "Libre Office not installed; promting for install"
    prompt=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "Measures for Justice IT" -heading "Install Recommendation" -alignHeading justified -description "$MSG" -alignDescription justified -icon '/Applications/Utilities/yo.app/Contents/Resources/AppIcon.icns' -button1 'Install Now' -button2 'Later' )
    #what are we doing with results
    if [ "$prompt" == "0" ]; then
        echo "User requested install; Installing.."
        jamf policy -trigger LibreOffice
    else
        echo "User elected to not install; continuing run"
    fi
  else
    NewDocxs=$(find /Users/"$CurrentUser"/Documents/Receipts/*.docx )
    if [ -z "$NewDocxs" ]; then
      echo "No .docx files found for report; skipping run"
    else
      for i in $NewDocxs
       do
          /Applications/LibreOffice.app/Contents/MacOS/soffice --invisible --headless --convert-to pdf "${i}" --outdir /Users/"$CurrentUser"/Documents/Receipts/
       done
    fi
  fi
}

ZipArchive(){
  #Compress currernt files in folder
  zip -q -r  "/Users/$CurrentUser/Documents/Receipts/Receipts-$(date +"%Y-%m-%d").zip" /Users/"$CurrentUser"/Documents/Receipts/
  #Move zip for save
  mv "/Users/$CurrentUser/Documents/Receipts/Receipts-$(date +"%Y-%m-%d").zip" /Users/"$CurrentUser"/Documents/Receipt\ Archive

}

ConvertDOC
ConvertJPG
ConvertPNG
#Concatenate PDFs
"/System/Library/Automator/Combine PDF Pages.action/Contents/Resources/join.py" -o "/Volumes/GoogleDrive/Shared drives/General/ExpenseReceipts/$CurrentUser.Receipts-$(date +"%m-%Y").pdf"  /Users/"$CurrentUser"/Documents/Receipts/*.pdf
SlackNotify "$CurrentUser"
ZipArchive

#clean up receipt folder
rm -rf /Users/"$CurrentUser"/Documents/Receipts/*

exit 0
