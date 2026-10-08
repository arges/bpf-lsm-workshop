#!/bin/sh
# SSH into a running workshop VM as the workshop user.
#
#   scripts/ssh-vm.sh [command...]        (port: $SSH_PORT, default 2222)
#
# Supplies the (public) password through SSH_ASKPASS so that sshpass is not
# needed, and keeps the VM's throwaway host key out of ~/.ssh/known_hosts.
set -eu

askpass=$(mktemp)
trap 'rm -f "$askpass"' EXIT
printf '#!/bin/sh\necho workshop\n' >"$askpass"
chmod 0700 "$askpass"

SSH_ASKPASS=$askpass SSH_ASKPASS_REQUIRE=force ssh \
	-p "${SSH_PORT:-2222}" \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o PreferredAuthentications=password \
	-o PubkeyAuthentication=no \
	-o NumberOfPasswordPrompts=1 \
	-o ConnectTimeout=5 \
	workshop@127.0.0.1 "$@"
