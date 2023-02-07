#!/bin/bash

#Quick script to shutdown a laptop when AC power is no longer being supplied and the battery is low.
#Can optionally send an alert out via Pushover or email (Need a functioning mail server for this)
#Tested on Proxmox VE. Needs the following packages installed on the target server: curl util-linux

#Set alerting method (telegram/pushover/email/off)
#a value of 'off' here will disable all alerts

#Alerting method
ALERT_METHOD='telegram'

#Critical battery threshold. Sets the capacity value where the battery is considered to be critically low
#Value is read from /sys/class/power_supply/BAT0/capacity
CRITICAL_BATTERY_THRESHOLD=3

#Pushover credentials
PUSHOVER_USER_TOKEN=""
PUSHOVER_API_TOKEN=""

#Telegram credentials
TELEGRAM_BOT_TOKEN=""
TELEGRAM_GROUP_ID=""


#Settings for email alerts
ALERT_EMAIL_RECIPIENT=""

shutdown_server () {
  #echo "shutdown_server() called"
  #Runs commands for shutting down the server
  /usr/sbin/shutdown -h now
}


send_alert () {
 #Handles sending out of alerts via telegram, email or pushover

 #echo "send_alert() called"

# local CURRENT_DATETIME=`date +%F\ %H:%M:%S`
# local ALERT_MESSAGE="${SYSTEM_HOSTNAME} - ${CURRENT_DATETIME} ALERT: battery is low and mains power is not present. will shut down soon if ac power is not restored" 

   if [[ $ALERT_METHOD == 'telegram' ]]; then
    /usr/bin/curl -s \
      --data "chat_id=${TELEGRAM_GROUP_ID}" \
      --data "text=${ALERT_MESSAGE}" \
       'https://api.telegram.org/bot'${TELEGRAM_BOT_TOKEN}'/sendMessage' > /dev/null
  fi

  if [[ $ALERT_METHOD == 'pushover' ]]; then
    /usr/bin/curl -q -s \
      -F "token=${PUSHOVER_API_TOKEN}" \
      -F "user=${PUSHOVER_USER_TOKEN}" \
        --form-string "message=${ALERT_MESSAGE}" \
        https://api.pushover.net/1/messages.json
  fi

  if [[ $ALERT_METHOD == 'email' ]]; then
    echo $ALERT_MESSAGE | mail -s "Power Loss Alert" $ALERT_EMAIL_RECIPIENT
  fi

  #check the alert has been sent ok. if it has then create the lock file so we don't send out anymore alerts
  # until the event has cleared. Only set if the previous alert was sent ok
  if [ $? -eq 0 ]; then
    touch /tmp/.alert-sent
    return 0
  fi

}


#Grab the hostname
SYSTEM_HOSTNAME=`cat /etc/hostname`

#BATTERY_ALARM=`cat /sys/class/power_supply/BAT0/alarm`
BATTERY_CAPACITY=`cat /sys/class/power_supply/BAT0/capacity`

#Check whether ac power is being applied
# Store the return value in a variable (0 means ac power is applied, 1 means it isn't)
#/usr/sbin/on_ac_power
#AC_POWER_STATE=$?
AC_POWER_STATE=`cat /sys/class/power_supply/ACAD/online`

#Delete the lock file to re-enable sending of alerts if it exists and everything is ok
# By ok, we mean that AC power is applied
if [ $AC_POWER_STATE -eq 1 ] && [ -f /tmp/.alert-sent ]; then
	CURRENT_DATETIME=`date +%F\ %H:%M:%S`
	ALERT_MESSAGE="${SYSTEM_HOSTNAME} - ${CURRENT_DATETIME} ПОПЕРЕДЖЕННЯ: живлення відновлено"
	send_alert
	rm /tmp/.alert-sent
fi

# if no ac power and battery very low
if [ $AC_POWER_STATE -eq 0 ] && [ $BATTERY_CAPACITY -le $CRITICAL_BATTERY_THRESHOLD ]; then
    #check for ac power again. If ac power still isn't being applied then
    #Send alert via pushover. don't send an alert if the lock file exists
    sleep 2 #Wait for a bit to rule out any brief mains power losses

     #get the current state of the AC power supply again
     AC_POWER_STATE=`cat /sys/class/power_supply/ACAD/online`

     #Still no AC power yet. Send an alert (if enabled) as we haven't done already and shutdown the server
     if [ ! -f /tmp/.alert-sent ] && [ $AC_POWER_STATE -eq 0 ]; then
       if [ $ALERT_METHOD != 'off' ]; then #Send an alert if enabled
		CURRENT_DATETIME=`date +%F\ %H:%M:%S`
		ALERT_MESSAGE="${SYSTEM_HOSTNAME} - ${CURRENT_DATETIME} ПОПЕРЕДЖЕННЯ: батарея розряджена, а мережеве живлення відсутнє. незабаром вимкнеться, якщо живлення змінного струму не буде відновлено" 	
        send_alert
       fi
       #Shutdown the server
       shutdown_server
       
     fi

fi
