#!/bin/sh
# target: marverics
set -e

## Config
RUBY_VERSION="2.0.0-p451"

## Functions
function die(){
	echo "died: $1"
	exit 1
}

function install_xcode(){
	xcode-select --install
	echo "wait for installer"
	while true
	do
		sleep 1
		pgrep 'Install Command Line Developer Tools' >/dev/null 2>&1
		if [ $? != 0 ]; then
			break;
		fi
	done;

	xcode-select -p
	if [ $? != 0 ]; then
		die "xcode-select failed!!"
	fi
}

# 1. Install CommandLine Developer Tools
xcode-select -p >/dev/null 2>&1
if [ $? != 0 ]; then
	install_xcode
else
	echo "already installed xcode"
fi

# 2. Install HomeBrew
which brew
if [ $? != 0 ]; then
	ruby -e "$(curl -fsSL https://raw.github.com/mxcl/homebrew/go/install)"
else
	echo "already installed brew"
fi
brew doctor
brew update

if [ ! $(brew tap | grep phinze/cask) ]; then
	brew tap phinze/homebrew-cask
fi
brew install brew-cask

brew install jq
brew install nkf
brew install watch
brew install wget
brew install rbenv
brew install rbenv-gem-rehash
brew install rbenv-gemset
brew install ruby-build
brew install readline
brew install the_silver_searcher

brew cask install virtualbox
brew cask install firefox
brew cask install google-chrome
brew cask install google-drive
brew cask install google-japanese-ime
brew cask install limechat
brew cask install alfred
brew cask alfred link #### 
brew cask install skype
brew cask install onepassword
brew cask install iterm2
brew cask install gyazo
#brew cask install usb-overdrive
brew cask install keyremap4macbook

# 3. Install Ruby
if [ ! $(rbenv versions | grep "$RUBY_VERSION") ]; then
	rbenv install $RUBY_VERSION
fi
echo "setup done"

