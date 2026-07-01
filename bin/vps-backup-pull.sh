#!/usr/bin/env bash
# Pull a backup from the Sakura VPS to ~/Backups/vps/ on this Mac.
# Run manually: vps-backup-pull.sh
# Requires SSH key auth to tk2-237-28023.vs.sakura.ne.jp.
set -euo pipefail

# Set VPS_HOST in your environment, or add a Host alias "vps-sakura" in ~/.ssh/config
VPS="${VPS_HOST:-vps-sakura}"
DEST="$HOME/Backups/vps"

rsync_or_warn() {
  rsync "$@" || {
    rc=$?
    { [ "$rc" -eq 23 ] || [ "$rc" -eq 10 ]; } \
      && echo "[warn] rsync: some files skipped (exit $rc)" \
      || exit "$rc"
  }
}

echo "=== vps-backup-pull started at $(date '+%Y-%m-%d %H:%M:%S') ==="

echo "--- [1/19] Running dump on VPS ---"
ssh "$VPS" "bash ~/bin/vps-backup-dump.sh"

mkdir -p "$DEST"

echo "--- [2/19] Pulling backup-staging (MariaDB, systemd, cron.d, sshd) ---"
rsync_or_warn -az --delete "$VPS:~/backup-staging/" "$DEST/staging/"

echo "--- [3/19] Pulling /srv/kymt.me ---"
rsync_or_warn -az --delete --rsync-path="sudo rsync" "$VPS:/srv/kymt.me/" "$DEST/srv/"

echo "--- [4/19] Pulling ~/docs (e2e, plans) ---"
rsync_or_warn -az --delete "$VPS:~/docs/" "$DEST/docs/"

echo "--- [5/19] Pulling /usr/local/nginx/conf ---"
rsync_or_warn -az --delete "$VPS:/usr/local/nginx/conf/" "$DEST/nginx-conf/"

echo "--- [6/19] Pulling ~/.ssh ---"
rsync_or_warn -az --delete "$VPS:~/.ssh/" "$DEST/ssh/"

echo "--- [7/19] Pulling ~/projects ---"
rsync_or_warn -az --delete "$VPS:~/projects/" "$DEST/projects/"

echo "--- [8/19] Pulling ~/.gnupg ---"
rsync_or_warn -az --delete "$VPS:~/.gnupg/" "$DEST/gnupg/"

echo "--- [9/19] Pulling ~/.aws ---"
rsync_or_warn -az --delete "$VPS:~/.aws/" "$DEST/aws/"

echo "--- [10/19] Pulling ~/ (all home files, excl cache) ---"
mkdir -p "$DEST/home-all"
rsync_or_warn -az --delete \
  --exclude='.cache/' \
  --exclude='.zsh-evalcache/' \
  "$VPS:~/" "$DEST/home-all/"

echo "--- [11/19] Pulling /etc/hosts ---"
rsync_or_warn -az "$VPS:/etc/hosts" "$DEST/staging/etc/"

echo "--- [12/19] Pulling /usr/local/nginx/html ---"
rsync_or_warn -az --delete --rsync-path="sudo rsync" "$VPS:/usr/local/nginx/html/" "$DEST/nginx-html/"

echo "--- [13/19] Pulling ~/.claude ---"
rsync_or_warn -az --delete "$VPS:~/.claude/" "$DEST/claude/"

echo "--- [14/19] Pulling ~/.local/share/claude (session data) ---"
rsync_or_warn -az --delete "$VPS:~/.local/share/claude/" "$DEST/local-share-claude/"

echo "--- [15/19] Pulling /usr/local/mise/data (system Ruby) ---"
rsync_or_warn -az --delete "$VPS:/usr/local/mise/data/" "$DEST/mise-system-data/"

echo "--- [16/19] Pulling /usr/local/nginx/sbin (nginx+passenger binary) ---"
rsync_or_warn -az --delete "$VPS:/usr/local/nginx/sbin/" "$DEST/nginx-sbin/"

echo "--- [17/19] Pulling ~/.local/share/mise (user mise data, excl python) ---"
rsync_or_warn -az --delete --exclude='installs/python/' "$VPS:~/.local/share/mise/" "$DEST/mise-user-data/"

echo "--- [18/19] Pulling ~/.local/share/nvim (nvim plugins) ---"
rsync_or_warn -az --delete "$VPS:~/.local/share/nvim/" "$DEST/nvim-data/"

echo "--- [19/19] Pulling ~/build (nginx source & build logs) ---"
rsync_or_warn -az --delete "$VPS:~/build/" "$DEST/build/"

echo ""
echo "=== Backup complete ==="
du -sh "$DEST"/*/
echo "Total: $(du -sh "$DEST" | cut -f1)"
