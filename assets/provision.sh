#!/usr/bin/env bash
set -euo pipefail

linux_user="$1"
ide_port="$2"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git gh sudo

if ! id "$linux_user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$linux_user"
fi

usermod --append --groups sudo "$linux_user"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$linux_user" > "/etc/sudoers.d/$linux_user"
chmod 0440 "/etc/sudoers.d/$linux_user"

if ! command -v code-server >/dev/null 2>&1; then
    installer="$(mktemp)"
    curl -fsSL https://code-server.dev/install.sh -o "$installer"
    sh "$installer"
    rm -f "$installer"
fi

install -d -m 0700 -o "$linux_user" -g "$linux_user" "/home/$linux_user/.config"
install -d -m 0700 -o "$linux_user" -g "$linux_user" "/home/$linux_user/.config/code-server"
config_file="/home/$linux_user/.config/code-server/config.yaml"

ide_password=""
if [[ -f "$config_file" ]]; then
    ide_password="$(sed -n 's/^password: //p' "$config_file" | head -n 1)"
fi
if [[ -z "$ide_password" ]]; then
    ide_password="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
fi

cat > "$config_file" <<EOF
bind-addr: 127.0.0.1:$ide_port
auth: password
password: $ide_password
cert: false
EOF
chown "$linux_user:$linux_user" "$config_file"
chmod 0600 "$config_file"

cat > /etc/wsl.conf <<EOF
[automount]
enabled=false

[interop]
enabled=false
appendWindowsPath=false

[boot]
systemd=true

[user]
default=$linux_user
EOF

code_server_path="$(command -v code-server)"
cat > /etc/systemd/system/gitcage-ide.service <<EOF
[Unit]
Description=GitCage loopback IDE
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$linux_user
Group=$linux_user
WorkingDirectory=/home/$linux_user/workspace
ExecStart=$code_server_path
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitcage-ide.service

install -d -m 0755 -o "$linux_user" -g "$linux_user" "/home/$linux_user/workspace"
install -d -m 0700 -o "$linux_user" -g "$linux_user" "/home/$linux_user/.config/gh"

runuser -u "$linux_user" -- git config --global init.defaultBranch main
runuser -u "$linux_user" -- git config --global pull.ff only
runuser -u "$linux_user" -- git config --global fetch.prune true
runuser -u "$linux_user" -- git config --global --unset-all credential.helper >/dev/null 2>&1 || :
