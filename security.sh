#!/bin/bash
# This script Setup Fail2Ban with SendMail
#
# Credit:
# https://www.digitalocean.com/community/tutorials/how-to-protect-an-nginx-server-with-fail2ban-on-ubuntu-14-04
# https://www.tricksofthetrades.net/2018/05/18/fail2ban-installing-bionic/
# http://johnny.chadda.se/using-fail2ban-with-nginx-and-ufw/   
# https://gist.github.com/JulienBlancher/48852f9d0b0ef7fd64c3  - check for additional jails
#
# Cloudflare API integration with Fail2Ban
# https://guides.wp-bullet.com/integrate-fail2ban-cloudflare-api-v4-guide/
# https://serverfault.com/questions/928314/nginx-req-limit-not-triggering-fail2ban-event-cloudflare-api
# 
#
# Test
# ab -c 100 -n 100 http://[your site]/
#
# Check Filters for F2B
# sudo fail2ban-client -d
#
#
clear
echo "Please provide destination email for Fail2Ban Notification"
read -p "Enter destination email, then press [ENTER] : " F2B_DEST_EMAIL
echo "Please provide sender email for Fail2Ban Notification"
read -p "Enter sender email, then press [ENTER] : " F2B_SENDER_EMAIL
echo "Please provide sender email password"
read -p "Enter sender email, then press [ENTER] : " F2B_SENDER_PASS
echo "Please provide CloudFlare Email Address"
read -p "Enter CloudFlare Account Email Address [ENTER] : " CF_ACC_EMAIL
echo "Please provide CloudFlare Global API Key"
read -p "Enter CloudFlare API Key: " CF_API_KEY
read -p "Do you have multiple URL on the same Cloudflare account? (Y/n):" ZONE_EXIST
if [[ "$ZONE_EXIST" =~ ^([yY][eE][sS]|[yY])+$ ]]
then
    read -p "Enter CloudFlare ZONEID: " CF_ZONEID
fi
echo "Please provide the domain name"
read -p "Enter domain name: " FQDN_NAME
clear
read -t 30 -p "Thank you. Please press [ENTER] continue or [Control]+[C] to cancel"
echo "Setting up Fail2Ban, Postfix and iptables"


sudo apt-get update && sudo apt-get upgrade -y

# Set up Postfix
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< "postfix postfix/mailname string $FQDN_NAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

sudo apt-get install libsasl2-modules postfix -y
echo "[smtp.gmail.com]:465 $F2B_SENDER_EMAIL:$F2B_SENDER_PASS" > /etc/postfix/sasl/sasl_passwd
sudo postmap /etc/postfix/sasl/sasl_passwd
sudo chown root:root /etc/postfix/sasl/sasl_passwd.db
sudo chmod 0600 /etc/postfix/sasl/sasl_passwd.db
rm /etc/postfix/sasl/sasl_passwd #remove plain text user & password

# Configure POSTFIX
sudo postconf -e "relayhost = [smtp.gmail.com]:465"
# Enable SASL authentication
sudo postconf -e "smtp_sasl_auth_enable = yes"
sudo postconf -e "smtp_sasl_security_options = noanonymous"
sudo postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd"

sudo postconf -e "smtpd_tls_loglevel = 1"
sudo postconf -e "smtpd_use_tls=yes"
sudo postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$FQDN_NAME/fullchain.pem"
sudo postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$FQDN_NAME/privkey.pem"
sudo postconf -e "smtpd_tls_ciphers = high"
sudo postconf -e "smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache"

sudo postconf -e "smtp_tls_CAfile = /etc/letsencrypt/live/$FQDN_NAME/cert.pem"
sudo postconf -e "smtp_tls_security_level = encrypt"
sudo postconf -e "smtp_tls_ciphers = high"
sudo postconf -e "smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache"
sudo postconf -e "smtp_tls_wrappermode = yes"

# Allow established connections, traffic generated by the server itself, 
# traffic destined for our SSH and web server ports. 
# https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-14-04
sudo apt-get install -y iptables-persistent
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 25 -j ACCEPT
sudo iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
sudo iptables -A INPUT -j DROP
sudo dpkg-reconfigure iptables-persistent -u


## Install Fail2Ban
sudo apt-get install fail2ban -y
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMP-Mariadb-Wordpress-bashscript/master/resources/jail.local
mv ./jail.local /etc/fail2ban/jail.local
chmod 640 /etc/fail2ban/jail.local

## -- Configure Filters and Jails
sed -i "s/F2B_DEST/$F2B_DEST_EMAIL/" /etc/fail2ban/jail.local
sed -i "s/F2B_SENDER/$F2B_SENDER_EMAIL/" /etc/fail2ban/jail.local
sed -i "s/CF_EMAIL/$CF_ACC_EMAIL/" /etc/fail2ban/jail.local
sed -i "s/CF_GLB_KEY/$CF_API_KEY/" /etc/fail2ban/jail.local
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/nginx-http-auth.conf
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/nginx-noscript.conf
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/wordpress.conf
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/CloudFlareMod.conf
sed -i "s/CF_GLB_KEY/$CF_API_KEY/" ./CloudFlareMod.conf
sed -i "s/CF_EMAIL/$CF_ACC_EMAIL/" ./CloudFlareMod.conf
if [[ "$ZONE_EXIST" =~ ^([yY][eE][sS]|[yY])+$ ]]
then
    CF_ZONEID="zones/$CF_ZONEID"
    sed -i "s|CF_ZONE|$CF_ZONEID|g" ./CloudFlareMod.conf
else
    sed -i "s|CF_ZONE|user|g" ./CloudFlareMod.conf
fi

#Setting up log files for Fail2Ban Filters
touch /var/log/wordpressaccess.log
chmod 666 /var/log/wordpressaccess.log
touch /var/log/nginxlimiterror.log
chmod 666 /var/log/nginxlimiterror.log
touch /var/log/nginxaccess.log
chmod 666 /var/log/nginxaccess.log
touch /var/log/sshauth.log
chmod 666 /var/log/sshauth.log
touch /var/log/nginxhttpauth.log
chmod 666 /var/log/nginxhttpauth.log

# Move filter to proper location
mv ./nginx-http-auth.conf /etc/fail2ban/filter.d/nginx-http-auth.conf
mv ./nginx-noscript.conf /etc/fail2ban/filter.d/nginx-noscript.conf
mv ./wordpress.conf /etc/fail2ban/filter.d/wordpress.conf
mv ./nginx-req-limit.conf /etc/fail2ban/filter.d/nginx-req-limit.conf
sudo cp /etc/fail2ban/filter.d/apache-badbots.conf /etc/fail2ban/filter.d/nginx-badbots.conf #enable bad-bots

# Move CloudFlare Action
mv ./CloudFlareMod.conf /etc/fail2ban/action.d/CloudFlareMod.conf

# Activate Fail2Ban
sudo systemctl service enable fail2ban
sudo systemctl service start fail2ban
echo "Fail2Ban installation completed."
read -t 2
clear

# Modify nginx.conf to include cloudflareip file for the newest ips
touch /etc/nginx/cloudflareip
sed -i '/http {/a\  ' /etc/nginx/nginx.conf #add newline
sed -i '/http {/a\       include /etc/nginx/cloudflareip;' /etc/nginx/nginx.conf
sed -i '/http {/a\       ## Include Cloudflare IP ##' /etc/nginx/nginx.conf
sed -i '/http {/a\  ' /etc/nginx/nginx.conf #add newline
sed -i '/http {/a\  ' /etc/nginx/nginx.conf #add newline

# Get CloudFlare IP and set up cronjob to run automatically
mkdir /root/scripts
wget https://raw.githubusercontent.com/ridgegate/Ubuntu18.04-LEMariaDBP-Wordpress-SSL-script/master/resources/auto-cf-ip-update.sh
mv ./auto-cf-ip-update.sh /root/scripts/auto-cf-ip-update.sh
sudo chmod +x /root/scripts/auto-cf-ip-update.sh
/bin/bash /root/scripts/auto-cf-ip-update.sh
# Added Cronjob to autoupdate IP list
(crontab -l && echo "# Update CloudFlare IP Ranges (every Sunday at 04:00)") | crontab -
(crontab -l && echo "* 4 * * 0 /bin/bash /root/scripts/auto-cf-ip-update.sh >/dev/null 2>&1") | crontab - 
echo
echo "Done"
