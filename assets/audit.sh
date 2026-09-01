#!/usr/bin/env bash
set -euo pipefail

linux_user="$1"
ide_port="$2"
expected_github="${3:-}"

emit() {
    local check="$1"
    local status="$2"
    local detail="$3"
    printf '%s\t%s\t%s\n' "$check" "$status" "$detail"
}

ini_value() {
    local section="$1"
    local key="$2"
    awk -v wanted_section="$section" -v wanted_key="$key" '
        /^[[:space:]]*\[/ {
            current = $0
            gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", current)
            next
        }
        current == wanted_section && $0 ~ "^[[:space:]]*" wanted_key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print tolower(value)
            exit
        }
    ' /etc/wsl.conf
}

check_ini() {
    local check="$1"
    local section="$2"
    local key="$3"
    local expected="$4"
    local actual
    actual="$(ini_value "$section" "$key")"
    if [[ "$actual" == "$expected" ]]; then
        emit "$check" PASS "$section.$key=$actual"
    else
        emit "$check" FAIL "expected $section.$key=$expected, found ${actual:-missing}"
    fi
}

check_ini automount.disabled automount enabled false
check_ini interop.disabled interop enabled false
check_ini interop.windows_path interop appendWindowsPath false
check_ini default.user user default "$linux_user"

if findmnt -rn -t drvfs,9p -o TARGET 2>/dev/null | grep -Eq '^/mnt/[A-Za-z]($|/)'; then
    emit windows.drives FAIL 'a Windows drive is mounted below /mnt'
else
    emit windows.drives PASS 'no Windows drive mounts detected'
fi

if [[ -n "${WSL_INTEROP:-}" ]]; then
    emit windows.interop_env FAIL 'WSL_INTEROP is present'
else
    emit windows.interop_env PASS 'WSL_INTEROP is absent'
fi

if [[ ":$PATH:" =~ :/mnt/[A-Za-z](/|:) ]]; then
    emit windows.path FAIL 'PATH contains a Windows drive path'
else
    emit windows.path PASS 'PATH has no Windows drive entries'
fi

config_file="/home/$linux_user/.config/code-server/config.yaml"
expected_bind="127.0.0.1:$ide_port"
actual_bind="$(sed -n 's/^bind-addr:[[:space:]]*//p' "$config_file" | head -n 1)"
if [[ "$actual_bind" == "$expected_bind" ]]; then
    emit ide.loopback PASS "bind-addr=$actual_bind"
else
    emit ide.loopback FAIL "expected bind-addr=$expected_bind, found ${actual_bind:-missing}"
fi

if grep -Eq '^auth:[[:space:]]+password$' "$config_file"; then
    emit ide.authentication PASS 'password authentication enabled'
else
    emit ide.authentication FAIL 'password authentication is not enabled'
fi

config_mode="$(stat -c '%a' "$config_file")"
config_owner="$(stat -c '%U:%G' "$config_file")"
if [[ "$config_mode" == '600' && "$config_owner" == "$linux_user:$linux_user" ]]; then
    emit ide.config_permissions PASS "$config_owner mode=$config_mode"
else
    emit ide.config_permissions FAIL "$config_owner mode=$config_mode"
fi

workspace="/home/$linux_user/workspace"
workspace_owner="$(stat -c '%U:%G' "$workspace")"
if [[ "$workspace_owner" == "$linux_user:$linux_user" ]]; then
    emit workspace.owner PASS "$workspace_owner"
else
    emit workspace.owner FAIL "$workspace_owner"
fi

credential_config="$(git config --global --get-regexp '^credential\.' 2>/dev/null || :)"
if grep -Eqi '(manager|wincred|osxkeychain)' <<<"$credential_config"; then
    emit git.windows_helper FAIL 'a host credential helper is configured'
else
    emit git.windows_helper PASS 'no host credential helper configured'
fi

git_name="$(git config --global --get user.name 2>/dev/null || :)"
git_email="$(git config --global --get user.email 2>/dev/null || :)"
if [[ -n "$git_name" && -n "$git_email" ]]; then
    emit git.identity PASS "$git_name <$git_email>"
else
    emit git.identity SKIP 'Git identity is set during login'
fi

if [[ -z "$expected_github" ]]; then
    emit github.account SKIP 'cage has not been bound to a GitHub account'
    emit github.token_permissions SKIP 'no bound account to verify'
else
    actual_github="$(gh api user --jq .login 2>/dev/null || :)"
    if [[ "$actual_github" == "$expected_github" ]]; then
        emit github.account PASS "authenticated as $actual_github"
    else
        emit github.account FAIL "expected $expected_github, found ${actual_github:-unauthenticated}"
    fi

    hosts_file="/home/$linux_user/.config/gh/hosts.yml"
    if [[ -f "$hosts_file" ]]; then
        hosts_mode="$(stat -c '%a' "$hosts_file")"
        hosts_owner="$(stat -c '%U:%G' "$hosts_file")"
        if [[ "$hosts_mode" == '600' && "$hosts_owner" == "$linux_user:$linux_user" ]]; then
            emit github.token_permissions PASS "$hosts_owner mode=$hosts_mode"
        else
            emit github.token_permissions FAIL "$hosts_owner mode=$hosts_mode"
        fi
    else
        emit github.token_permissions FAIL 'hosts.yml is missing'
    fi
fi
