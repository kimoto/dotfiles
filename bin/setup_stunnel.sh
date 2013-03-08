#!/bin/sh

YOUR_HOSTNAME="kymt.me"

sudo yum install -y stunnel
cd /etc/pki/tls/certs; sudo make "$YOUR_HOSTNAME.pem"
sudo cp $HOME/dotfiles/stunnel.conf /etc/stunnel/stunnel.conf
sudo cp $HOME/dotfiles/stunnel /etc/init.d/stunnel

sudo service stunnel start && sudo service stunnel stop

sudo chkconfig --add stunnel
sudo chkconfig --list | grep stunnel

