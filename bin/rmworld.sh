#!/bin/sh
# 注意: $HOMEディレクトリのファイルが消えます
# Notice: this script, remove all files in $HOME
#
# 用法:
# 気が向いたときに$HOMEディレクトリ以下を支障のない範囲で全部消して
# 気分をリフレッシュさせると同時にファイルにアクスビリティを高めると同時に
# リビジョン管理しっかりしようねというモチベーションを発生させるためのものです

set -x

cd $HOME

# remove all files (not include dotfiles)
# rm -rf ./*

# remove synbolic links (dot files)
rm ./bin
rm ./.vimrc
rm ./.inputrc
rm ./.vimperatorrc 
rm ./.gitconfig
rm ./.gitignore
rm ./.screenrc
rm ./.zshrc
rm ./.zlogin
rm ./.bashrc
rm ./.irbrc

rm ./.vim
rm ./.subversion

rm ./.Xdefaults
rm ./.Xmodmap

rm ./.emacs.d
rm ./.emacs

# remove temp files
#rm ./.zcompdump
#rm ./.viminfo
#rm ./.zsh_history
