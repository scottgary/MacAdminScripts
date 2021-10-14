#!/usr/bin/python3
###############################################################################
# Code42 Alerting Created by: Scott Gary                                      #
# 10/13/2021                                                                  #
###############################################################################

import json
import requests
from requests.auth import HTTPBasicAuth
import time

# Code42 Vars:
code42Url = ''
code42Username = ''
Code42Pass=''
# Slack Vars:
SlackHook = "" #Webhook URL
Channel = "#it-alerts"
Username = "Code42 Alert"
EMOJI = ":code42:"

def slackMessages(SlackHook, Channel, Username, EMOJI, SlackMessage):
    payload = '{\"channel\": \"'+Channel+'\", \"username\": \"'+Username+'\", \"text\": \"'+SlackMessage+'\", \"icon_emoji\": \"'+EMOJI+'\"}'
    headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    }
    response = requests.post(SlackHook, headers=headers, data=payload)
    #print(response)

# Code42 get token and tenant ID:
tokenRequest = requests.get(code42Url+'/v1/auth/', auth=HTTPBasicAuth(code42Username, Code42Pass))
token = tokenRequest.text.split(':')[1].replace('"', '').replace('}', '')
#print(token)
headers = {"Authorization": "Bearer "+token}
tenantIdRequest = requests.request("GET", code42Url+'/v1/customer', headers=headers)
tenantID = tenantIdRequest.text.split(',')[2].split(':')[1].replace('"', '').replace('}', '')
#print(tenantID)

# Call for all alerts:
QueryData = '{"tenantId": "'+tenantID+'", "groups": [ { "filters": [ { "term": "State", "operator": "is", "value": "Open" } ], "filterClause": "AND" } ], "groupClause": "OR", "pgSize": "50", "pgNum": "0", "srtKey": "CreatedAt", "srtDirection": "DESC" }'
headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer '+token
}
alertsRequest = requests.post(code42Url+'/v1/alerts/query-alerts', headers=headers, data=QueryData).json()
#print(alertsRequest['alerts'])
alerts = alertsRequest['alerts']
for alert in alerts:
    alertID = alert['id']
    # Get details of alert to parse:
    data = '{"alertId": "'+alertID+'"}'
    alertDetails = requests.post(code42Url+'/v1/alerts/query-details-aggregate', headers=headers, data=data).json()
    # Gather vars from alert data:
    alertName = alertDetails['alert']['name']
    actorID = alertDetails['alert']['actorId']
    actor = alertDetails['alert']['actor']
    alertDesription = alertDetails['alert']['description']
    alertSeverity = alertDetails['alert']['severity']
    alertURL = alertDetails['alert']['alertUrl']
    alertTimeStamp = alertDetails['alert']['observation']['observedAt']
    alertData = alertDetails['alert']['observation']['data']
    alertEventID = alertData.split(',')[15].split(':')[1].replace('"', '')
    alertFilePath = alertData.split(',')[16].split(':')[1].replace('"', '')
    alertFileName = alertData.split(',')[17].split(':')[1].replace('"', '')

    # Parse alerts by name:
    if alertName == 'Flight risk':
        print('adding note to alert')
        data = '{  "tenantId": "'+tenantID+'", "alertId": "'+alertID+'", "note": "IT-Service Bot has reviewed this alert" }'
        # Add note to alert
        addNote = requests.post(code42Url+'/v1/alerts/add-note', headers=headers, data=data)
        time.sleep(1)
        print('adding user to high risk group')
        # Adding employee to high risk group:
        data = '{  "tenantId": "'+tenantID+'", "userId": "'+actorID+'"}'
        add2HighRisk = requests.post(code42Url+'/v1/detection-lists/highriskemployee/add', headers=headers, data=data)
        time.sleep(1)
        print('closing alert')
        # Closing out alert:
        data = '{  "tenantId": "'+tenantID+'", "alertIds": [ "'+alertID+'" ], "state": "RESOLVED" }'
        closeAlert = requests.post(code42Url+'/v1/alerts/update-state', headers=headers, data=data)
    # low severity alerting:
    elif alertName == 'Public on Web' or alertName == 'Cloud share permission changes' or alertName == 'Copy to external drive' or alertName == 'Exposure on an endpoint' or alertName == 'Salesforce report exfiltration' or alertName == 'Source code exfiltration by extension':
        print('adding note to alert')
        data = '{  "tenantId": "'+tenantID+'", "alertId": "'+alertID+'", "note": "IT-Service Bot has reviewed this alert and sent this information to Slack" }'
        # Add note to alert
        addNote = requests.post(code42Url+'/v1/alerts/add-note', headers=headers, data=data)
        time.sleep(1)
        print('posting slack alert for review')
        # Set message text and send to slack:
        SlackMessage = 'Alert Name: '+alert['name']+' \nDescription: '+alert['description']+' \nUser: '+alert['actor']+' \nSeverity: '+alert['severity']+' \nStatus: '+alert['state']
        slackMessages(SlackHook, Channel, Username, EMOJI, SlackMessage)
    elif alertName == 'Critical Alerts':
        print('adding note to alert')
        data = '{  "tenantId": "'+tenantID+'", "alertId": "'+alertID+'", "note": "IT-Service Bot has reviewed this alert and sent this information to Slack" }'
        # Add note to alert
        addNote = requests.post(code42Url+'/v1/alerts/add-note', headers=headers, data=data)
        time.sleep(1)
        print('posting slack alert for review')
        # Set message text and send to slack:
        SlackMessage = 'Alert Name: '+alert['name']+' \nDescription: '+alert['description']+' \nUser: '+alert['actor']+' \nSeverity: '+alert['severity']+' \nStatus: '+alert['state']
        slackMessages(SlackHook, Channel, Username, EMOJI, SlackMessage)
        time.sleep(1)
        # Creating Case out of critical alerts:
        data = '{"name": "Critical Alert - '+actor+'", "description": "'+alertName+'", "findings": "'+alertFilePath+alertFileName+'", "subject": "'+actorID+'", "assignee": null}'
        newCase = requests.post(code42Url+'/v1/cases', headers=headers, data=data).json()
        print(newCase)
        caseNumber = str(newCase['number'])
        print(caseNumber)
        # Adding file activity to alert:
        caseFileActivity = requests.post(code42Url+'/v1/cases/'+caseNumber+'/fileevent/'+alertEventID, headers)
        print(caseFileActivity.text)
    time.sleep(1)
print('No more alerts found')
