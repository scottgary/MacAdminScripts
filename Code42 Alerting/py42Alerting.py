#!/usr/bin/python3
###############################################################################
# Py42 Alerting Created by: Scott Gary                                        #
# 10/15/2021                                                                  #
###############################################################################

import sys
import requests
import json
import time
import py42.sdk
import py42.settings
from py42.sdk.queries.alerts.filters import *
from py42.sdk.queries.alerts.alert_query import AlertQuery


# Slack Vars:
SlackHook = "" #Webhook URL
Channel = "#it-alerts"
Username = "Code42 Alert"
EMOJI = ":code42:"

# Slack send meaage:
def slackMessages(SlackHook, Channel, Username, EMOJI, SlackMessage):
    payload = '{\"channel\": \"'+Channel+'\", \"username\": \"'+Username+'\", \"text\": \"'+SlackMessage+'\", \"icon_emoji\": \"'+EMOJI+'\"}'
    headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    }
    response = requests.post(SlackHook, headers=headers, data=payload)

# Query alerts:
filters = [AlertState.eq(AlertState.OPEN)]
query = AlertQuery(*filters)
sdk = py42.sdk.from_local_account('https://console.us.code42.com', '', '')

response = sdk.alerts.search(query)

alerts = response['alerts']

if alerts == []:
    print('No new alerts')
    sys.exit(0)


for alert in alerts:
    alertID = alert['id']
    print(alertID)
    # Get full alert Details
    alertDetails = sdk.alerts.get_aggregate_data(alertID)
    #print(alertDetails)
    # Parse call:
    actor = alertDetails['alert']['actor']
    print(actor)
    alertName = alertDetails['alert']['name']
    print(alertName)
    actorID = alertDetails['alert']['actorId']
    print(actorID)
    alertDesription = alertDetails['alert']['description']
    print(alertDesription)
    alertSeverity = alertDetails['alert']['severity']
    print(alertSeverity)
    alertURL = alertDetails['alert']['alertUrl']
    print(alertURL)
    alertState = alertDetails['alert']['state']
    print(alertState)
    alertObservations = alertDetails['alert']['observations'][0]
    #print(alertObservations)
    alertTimestamp = alertObservations['observedAt']
    print(alertTimestamp)
    alertData = alertObservations['data']
    #print(alertData)
    alertEventID = alertData.split(',')[15].split(':')[1].replace('"', '')
    print(alertEventID)
    alertFileName = alertData.split(',')[16].split(':')[1].replace('"', '')
    print(alertFileName)
    # Parse result by alert name for action: #  #  #  #
    if alertName == 'Public on Web':
        print('Public file share response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Password exfiltration':
        print('Password Sharing response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Source code exfiltration by extension':
        print('source code response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Salesforce report exfiltration':
        print('Spreadsheet exfiltration response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Cloud share permission changes':
        print('Cloud File Sharing response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Exposure on an endpoint':
        print('Exposure on an endpoint response')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Copy to external drive':
        print('Copy to external driveresponse')
        sdk.alerts.update_note(alertID, note='IT-Service Bot has reviewed this alert')
    elif alertName == 'Flight risk':
        print('adding note to alert and resolving:')
        sdk.alerts.update_state('RESOLVED', alertID, note='IT-Service Bot has reviewed this alert')
        print('adding user to High Risk grouping')
        sdk.detectionlists.high_risk_employee.add(actorID)
    elif alertName == 'Critical Alerts':
        print('adding note to alert')
        sdk.alerts.update_note(alertID, 'IT-Service Bot has reviewed this alert and will create a case from this information')
        print('Sending Slack message to alert IT')
        SlackMessage = 'Alert Name: '+alertName+' \nDescription: '+alertDesription+' \nUser: '+actor+' \nSeverity: '+alertSeverity+' \nStatus: '+alertState+' \nTimestamp: '+alertTimestamp+' \nURL: '+alertURL
        slackMessages(SlackHook, Channel, Username, EMOJI, SlackMessage)
        print('creating case from alert')
        newCase = sdk.cases.create('Critical Alert - '+actor, subject=actorID, assignee='None', description=alertDesription, findings=alertFileName)
        print('adding file activity to case')
        print(newCase.json()['number'])
        caseNumber = newCase.json()['number']
        sdk.cases.casesfileevents.add(caseNumber, alertEventID)
    time.sleep(1)

