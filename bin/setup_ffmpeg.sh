#!/bin/sh

REPO="/etc/yum.repos.d/CentOS-Base.repo"
TMP_FILE=`basename "$REPO"`

set -x

sudo yum -y install yum-plugin-priorities

ruby "$HOME/bin/setup_ffmpeg_fix.rb" "$REPO" > "$TMP_FILE"
sudo cp "$TMP_FILE" "$REPO"

sudo rpm -ivh http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.2-2.el6.rf.i686.rpm

sudo yum -y update rpmforge-release
sudo yum -y install ffmpeg

sudo yum -y install lame lame-devel faac faac-devel opencore-amr opencore-amr-devel amrnb amrnb-devel amrwb amrwb-devel yasm yasm-devel x264 x264-devel xvidcore xvidcore-devel libogg libogg-devel libvorbis libvorbis-devel libtheora libtheora-devel gsm gsm-devel openjpeg openjpeg-devel nut nut-devel a52dec a52dec-devel libvpx libvpx-devel 

# install x264
git clone git://git.videolan.org/x264.git
cd ./x264
./configure --prefix=/usr/local --enable-shared
make
sudo make install

# uninstall rpmforge ffmpeg and x264
sudo yum remove -y ffmpeg
sudo yum remove -y x264 x264-devel

# install latest ffmpeg
git clone git://source.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
./configure --prefix=/usr/local --enable-gpl --enable-libmp3lame --enable-libxvid --enable-libfaac --enable-libx264 --enable-shared --enable-nonfree

make -j2 # 2 core compile
sudo make install

echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf
sudo ldconfig

ffmpeg -v
ffmpeg -i mmsh://URL

