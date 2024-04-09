#!/bin/bash
set -exuo pipefail

######### Jamf Vars #########
JamfServer=""
# Use base64 creds
JAMF_API_TOKEN=""
AppName=""
gitVersion=""

################################################################################################
################################ FUNCTIONS #####################################################

InstallPolicyUpdate(){
	# Update Install Policy
	PkgId="$1"
	AppName="$2"
	PkgName="$3"
  # install policy ID 152, push install policy ID 156 (this needs a flush by IT id deploying to push latest update)
	InstallId="$4"
    JamfToken="$5"
	if [ -z "$InstallId" ]; then
		echo "No Jamf install policy id found; skipping update"
	else
		# Get policy XML to edit and update
		curl -s -X "GET" \
          -H "Authorization: Bearer ${JamfToken}" \
          -H "Accept: application/xml" \
          "${JamfServer}/JSSResource/policies/id/${InstallId}" | /usr/bin/xmllint --format - > "./policy-${InstallId}.xml"

		policyName=$(/usr/bin/xmllint --xpath "/policy/general/name/text()" "./policy-${InstallId}.xml")
		currentPackageID=$(/usr/bin/xmllint --xpath "/policy/package_configuration/packages/package/id/text()"  "./policy-${InstallId}.xml")
		currentPackageName=$(/usr/bin/xmllint --xpath "/policy/package_configuration/packages/package/name/text()"  "./policy-${InstallId}.xml")
		newPackageName="$PkgName"
		newPackageID="$PkgId"
		PolicyPkgNameChange=$(cat "./policy-${InstallId}.xml" | /usr/bin/sed "s|$currentPackageName|$newPackageName|")
		PolicyPkgIdChange=$(echo "$PolicyPkgNameChange" | /usr/bin/sed "s|$currentPackageID|$newPackageID|")
		echo "$PolicyPkgIdChange" | /usr/bin/xmllint --format - > "./policy-${InstallId}.xml"
		#cat "./policy-$InstallId.xml" | /usr/bin/sed "s|<package><name>${currentPackageName}|<package><name>${newPackageName}|"
  	curl -s -X PUT \
      -H "Authorization: Bearer ${JamfToken}" \
      -H "Accept: application/xml" \
      -T ./policy-$InstallId.xml \
      "${JamfServer}/JSSResource/policies/id/${InstallId}"
	fi
}

jamfToken(){
  # Get Jamf token for calls
  jamfGetToken=$(curl -s -X POST \
    -H 'Accept: application/json' \
    -H "Authorization: Basic ${JAMF_API_TOKEN}" \
    -d '' \
    "${JamfServer}/api/v1/auth/token" | jq .token | tr -d '"')
  echo $jamfGetToken
}

################################################################################################
################################ MAIN ##########################################################

# Get Jamf token for calls
JamfToken=$(jamfToken)

# get S3 credentials from Jamf for upload
awsOutput=$(curl --request POST \
  --silent \
  --header "authorization: Bearer ${JamfToken}" \
  --header 'Accept: application/json' \
  "${JamfServer}/api/v1/jcds/files"
)

# get aws creds
awsAccessKey=$(echo $awsOutput | jq .accessKeyID | tr -d '"')
awsSecretKey=$(echo $awsOutput | jq .secretAccessKey | tr -d '"')
awsSessionToken=$(echo $awsOutput | jq .sessionToken | tr -d '"')
awsBucket=$(echo $awsOutput | jq .bucketName | tr -d '"')
awsRegion=$(echo $awsOutput | jq .region | tr -d '"')
awsPath=$(echo $awsOutput | jq .path | tr -d '"')
awsUUID=$(echo $awsOutput | jq .uuid | tr -d '"')

# Set AWS creds
aws configure set aws_access_key_id "$awsAccessKey"
aws configure set aws_secret_access_key "$awsSecretKey"
aws configure set aws_session_token "$awsSessionToken"
aws configure set default.region "$awsRegion"

# Upload to S3
aws s3 cp "${AppName}-$gitVersion.pkg" "s3://$awsBucket/$awsPath/$AppName.$gitVersion.pkg"

# upload metadata to Jamf
pkg_data="<package>
    <name>${AppName}-${gitVersion}.pkg</name>
    <filename>${AppName}-${gitVersion}.pkg</filename>
</package>"


PkgUpload=$(curl --request "POST" \
  --header "authorization: Bearer ${JamfToken}" \
  --header 'Content-Type: application/xml' \
  --data "$pkg_data" \
  "${JamfServer}/JSSResource/packages/id/0" | awk -F "<id>" '{print $2}' | awk -F "</id" '{print $1}'
)

echo "New Pkg ID: $PkgUpload" 
# Update self install policy (152)
InstallPolicyUpdate "${PkgUpload}" "${AppName}" "${AppName}.${gitVersion}.pkg" "152" "${JamfToken}"
# Update auto-install policy (156)
InstallPolicyUpdate "${PkgUpload}" "${AppName}" "${AppName}.${gitVersion}.pkg" "156" "${JamfToken}"

# Update Jamf smart group criteria for new version

# Get Smart Group info by ID
SmartGroupXML=$(curl -s -X "GET" \
          -H "Authorization: Bearer ${JamfToken}" \
          -H "Accept: application/xml" \
          "${JamfServer}/JSSResource/computergroups/id/122" | /usr/bin/xmllint --format - > "./smartGroup-122.xml"
)

currentVersion=$(/usr/bin/xmllint --xpath "/computer_group/criteria/criterion[2]/value/text()"  "./smartGroup-122.xml")

# Make changes to XML for upload
SmartGroupCriteriaChange=$(cat "./smartGroup-122.xml" | /usr/bin/sed "s|$currentVersion|$gitVersion|")
# Save changes back to file
echo $SmartGroupCriteriaChange | /usr/bin/xmllint --format - > "./smartGroup-122.xml"

# Upload new XML to Jamf
SmartGroupUpdate=$(curl -s -X "PUT" \
  -H "Authorization: Bearer ${JamfToken}" \
  -H "Accept: application/xml" \
  -T ./smartGroup-122.xml \
  "${JamfServer}/JSSResource/computergroups/id/122"
)


# Cleanup Desktop XML: (When running off Jenkins we set to ephermeral so this step could be skipped)
rm -rf "./policy-152.xml"
rm -rf "./policy-156.xml"
rm -rf "./ROOT"
rm -rf "./infractl_Darwin_all.tar.gz"
rm -rf "./infractl.$gitVersion.pkg"
rm -rf "./smartGroup-122.xml"

exit 0
