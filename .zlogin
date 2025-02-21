# show banner
if command -v fortune &> /dev/null &&
   command -v lolcat &> /dev/null &&
   command -v cowsay &> /dev/null; then
  if [[ $SHLVL -eq 1 ]]; then
    fortune | cowsay -r -C | lolcat
  fi
fi
