# Snipe-IT Resources

Using [Snipe-IT](https://snipeitapp.com/) as small organization has been a great add to our overall inventory and an easy way to not be dependent on spreadsheets. Using the Snipe-IT [API Documentation](https://snipe-it.readme.io/reference#api-overview) we can easily update existing custom field attributes in Snipe as well as automate the inventory process during automated enrollment. Global Variables can be passed as Jamf `$4`-`$7` or hard-coded while testing for your environment. Jamf credentials should be base64 encoded for obfuscation. That can be done using:
```
# Obscure API creds:
echo -n "jamfapiuser:password" | base64
```
To decode the obfuscation to verify you can use:
```
# decode
echo -n "amFtZmFwaXVzZXI6cGFzc3dvcmQ=" | base64 --decode
```
If you do not already have an API token for your Snipe-IT instance one can be generated using [these](https://snipe-it.readme.io/reference#generating-api-tokens) instructions.

```
# Jamf Variables:
JamfServer="https://example.jamfcloud.com"
# Jamf credentials base64 encoded
JamfApiCreds="amFtZmFwaXVzZXI6cGFzc3dvcmQ="
# Snipe-IT Variables:
SnipeServer="https://example.snipe-it.io/api/v1"
SnipeBearer=""

```

## Snipe-ITCheck-In.sh

The `SnipeCustomFields` array will build the JSON payload for the update call. The custom fields names within the array should mirror the JSON custom field data in Snipe-IT. Name format will always appear as `_snipeit_${NAME}_${IDNUMBER}`

```
# space seperated list of custom field names you want to update:
SnipeCustomFields=("_snipeit_public_ip_10" "_snipeit_local_ip_11" "_snipeit_os_version_15" "_snipeit_jamf_last_checkin_16")
```
This also updates the Snipe-IT `name` field to the current machine name in Jamf.

### Snipe-ITEnrollment.sh

The `JamfInfoArray` array will build the JSON payload for the update call. The custom fields you are looking to update should be pulled from jamf in the same order they appear in Snipe-IT. This also updates the Snipe-IT `name` field to the current machine name in Jamf as well as the Jamf Asset Tag field to match Snipe-IT. If no device is found in Snipe-It matching the device unique serial number the device will be created and assigned the next available asset tag using the Jamf Model information.

**Currently working on creating new model if model id does not already exist in Snipe-IT**
