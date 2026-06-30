#!/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VSCODE_SETTING_DIR=~/Library/Application\ Support/Code/User

rm "$VSCODE_SETTING_DIR/settings.json"
ln -s "$SCRIPT_DIR/settings.json" "${VSCODE_SETTING_DIR}/settings.json"

rm "$VSCODE_SETTING_DIR/keybindings.json"
ln -s "$SCRIPT_DIR/keybindings.json" "${VSCODE_SETTING_DIR}/keybindings.json"

# install extensions
while read -r line
do
    code --install-extension "$line"
done < extensions

code --list-extensions > extensions
