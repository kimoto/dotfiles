#!/bin/sh

set -xe

cd $HOME
git clone git://github.com/sstephenson/rbenv.git .rbenv

mkdir -p ~/.rbenv/plugins
cd ~/.rbenv/plugins
git clone git://github.com/sstephenson/ruby-build.git

echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

