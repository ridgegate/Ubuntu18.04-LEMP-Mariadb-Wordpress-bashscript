#!/bin/bash
#
# Sendmail with gmail
#
#
clear
echo "Please provide sender email for Fail2Ban Notification"
read -p "Enter sender email, then press [ENTER] : " F2B_SENDER_EMAIL
echo "Please provide sender email password"
read -p "Enter sender email, then press [ENTER] : " F2B_SENDER_PASS
echo "Please provide test mail recipient address"
read -p "Enter reci, then press [ENTER] : " TEST_RCPT
echo

apt-get update -y
apt-get install -y sendmail mailutils sendmail-bin
mkdir /etc/mail/authinfo
chmod 700 /etc/mail/authinfo
touch /etc/mail/authinfo/smtpacct.txt
echo "AuthInfo: \"U:F2BAlert\" \"I:$F2B_SENDER_EMAIL\" \"P:$F2B_SENDER_PASS\"" > /etc/mail/authinfo/smtpacct.txt
makemap hash  /etc/mail/authinfo/smtpacct <  /etc/mail/authinfo/smtpacct.txt
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/smtprelayinfo
sed -i '/MAILER_DEFINITIONS/r smtprelayinfo' /etc/mail/sendmail.mc
#rm -f /etc/mail/authinfo/smtpacct.txt

make -C /etc/mail
/etc/init.d/sendmail reload

echo "Sendmail Setup Completed on $(date)" | mail -s "Sendmail Setup Completed" $TEST_RCPT
echo
echo
echo "Completed Sendmail Setup"
echo
echo
echo
echo
