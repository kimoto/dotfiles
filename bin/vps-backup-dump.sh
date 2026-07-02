#!/usr/bin/env bash
# Run on the VPS to collect root-owned files into ~/backup-staging/ for rsync pull.
set -euo pipefail

STAGING="$HOME/backup-staging"
# Root-staged files get chowned to this user so the rsync pull can read them.
OWNER="${BACKUP_OWNER:-$(id -un):$(id -gn)}"

echo "[dump] Preparing $STAGING"
mkdir -p "$STAGING/systemd" "$STAGING/cron.d" "$STAGING/etc/ssh" \
         "$STAGING/etc/my.cnf.d" "$STAGING/etc/sysctl.d" \
         "$STAGING/etc/sudoers.d" "$STAGING/etc/profile.d" \
         "$STAGING/letsencrypt" "$STAGING/nginx-disabled-vhosts" \
         "$STAGING/nginx-logs"

echo "[dump] MariaDB full dump..."
sudo mysqldump --all-databases --single-transaction --routines --events \
  | gzip > "$STAGING/mariadb-all.sql.gz"
echo "[dump] MariaDB: $(du -sh "$STAGING/mariadb-all.sql.gz" | cut -f1)"
if ! zcat "$STAGING/mariadb-all.sql.gz" | tail -3 | grep -q "Dump completed"; then
  echo "[dump] WARNING: MariaDB dump may be incomplete - check manually!"
fi

echo "[dump] systemd custom units..."
sudo cp /etc/systemd/system/*.service "$STAGING/systemd/" 2>/dev/null || true
sudo cp /etc/systemd/system/*.timer   "$STAGING/systemd/" 2>/dev/null || true
sudo chown "$OWNER" "$STAGING/systemd/"* 2>/dev/null || true

echo "[dump] cron.d..."
sudo cp -r /etc/cron.d/. "$STAGING/cron.d/" 2>/dev/null || true
sudo chown -R "$OWNER" "$STAGING/cron.d"

echo "[dump] sshd_config..."
sudo cp /etc/ssh/sshd_config "$STAGING/etc/ssh/"
sudo chown "$OWNER" "$STAGING/etc/ssh/sshd_config"

echo "[dump] MariaDB config..."
sudo cp /etc/my.cnf.d/server.cnf "$STAGING/etc/my.cnf.d/" 2>/dev/null || true
sudo chown "$OWNER" "$STAGING/etc/my.cnf.d/"* 2>/dev/null || true

echo "[dump] sysctl security config..."
sudo cp /etc/sysctl.d/99-security.conf "$STAGING/etc/sysctl.d/" 2>/dev/null || true
sudo chown "$OWNER" "$STAGING/etc/sysctl.d/"* 2>/dev/null || true

echo "[dump] sudoers.d..."
sudo cp -r /etc/sudoers.d/. "$STAGING/etc/sudoers.d/" 2>/dev/null || true
sudo chown -R "$OWNER" "$STAGING/etc/sudoers.d"

echo "[dump] profile.d (custom)..."
sudo cp /etc/profile.d/mise-system.sh /etc/profile.d/mise.sh "$STAGING/etc/profile.d/" 2>/dev/null || true
sudo chown "$OWNER" "$STAGING/etc/profile.d/"* 2>/dev/null || true

echo "[dump] firewalld rules..."
sudo firewall-cmd --list-all 2>/dev/null | tee "$STAGING/firewalld-rules.txt" > /dev/null || true

echo "[dump] sshd effective config..."
sudo sshd -T 2>/dev/null | tee "$STAGING/sshd-T.txt" > /dev/null || true

echo "[dump] letsencrypt certs..."
sudo cp -r /etc/letsencrypt/. "$STAGING/letsencrypt/" 2>/dev/null || true
sudo chown -R "$OWNER" "$STAGING/letsencrypt"

echo "[dump] nginx disabled vhosts..."
sudo cp -r /root/nginx-disabled-vhosts/. "$STAGING/nginx-disabled-vhosts/" 2>/dev/null || true
sudo chown -R "$OWNER" "$STAGING/nginx-disabled-vhosts"

echo "[dump] /etc full tarball..."
sudo tar -czf "$STAGING/etc-all.tar.gz" /etc 2>/dev/null || true
sudo chown "$OWNER" "$STAGING/etc-all.tar.gz" 2>/dev/null || true
echo "[dump] /etc: $(du -sh "$STAGING/etc-all.tar.gz" | cut -f1)"

echo "[dump] crontabs..."
crontab -l 2>/dev/null | tee "$STAGING/crontab-kimoto.txt" > /dev/null \
  || echo "(no crontab for kimoto)" > "$STAGING/crontab-kimoto.txt"
sudo crontab -l 2>/dev/null | tee "$STAGING/crontab-root.txt" > /dev/null \
  || echo "(no crontab for root)" > "$STAGING/crontab-root.txt"

echo "[dump] installed packages..."
rpm -qa --queryformat "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort > "$STAGING/rpm-qa.txt"
dnf repolist > "$STAGING/dnf-repolist.txt" 2>/dev/null || true

echo "[dump] nginx logs..."
sudo cp -r /usr/local/nginx/logs/. "$STAGING/nginx-logs/" 2>/dev/null || true
sudo chown -R "$OWNER" "$STAGING/nginx-logs" 2>/dev/null || true

echo "[dump] Done. $(du -sh "$STAGING" | cut -f1) in $STAGING"
