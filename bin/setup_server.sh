#!/bin/sh

set -xe

which rbenv || ./dotfiles/bin/setup_rbenv.sh
which ruby || ./dotfiles/bin/setup_ruby.sh
which mysql || ./dotfiles/bin/setup_mysql.sh
which ffmpeg || ./dotfiles/bin/setup_ffmpeg.sh
which $HOME/projects/peercast/ui/linux/peercast || ./dotfiles/bin/setup_peercast.sh
./dotfiles/bin/setup_peercast.in.sh
which /usr/local/nginx/sbin/nginx || ./dotfiles/bin/setup_nginx.sh

sudo chkconfig --add nginx
sudo chkconfig --add mysqld
sudo chkconfig --add httpd

