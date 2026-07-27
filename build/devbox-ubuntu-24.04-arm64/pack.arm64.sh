#!/bin/bash
export CSHARP_PKG=/opt/arm64.dev.cs.24.04.tar.gz
export DEV_PKG=/opt/arm64.dev.base.24.04.tar.gz

# HOST-SAFETY: this tarball is extracted with `tar -C /` on a live host, so it
# must NEVER carry server-owned SSH identity/config or /etc/passwd. We:
#   - drop /etc/passwd from the list (was clobbering host accounts),
#   - stage the dev key as /root/.ssh/authorized_keys.devbox (install merges it),
#   - replace `find /etc/ssh` with an exclusion form (no sshd_config, ssh_config,
#     moduli, ssh_host_*), and
#   - run a defence-in-depth grep filter before tar.
cat \
  <(apt list --installed 2>/dev/null|grep -E "ssh|libwrap0"|awk -F"/" '{print $1}'|xargs dpkg -L 2>/dev/null|sort|uniq|grep -v man1|grep -v man5|grep -v man8|grep -v "usr/share/doc"|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|awk '{print $2}' | sed '$a /root/.ssh/authorized_keys.devbox' | sed '$a /bin/entry' ) \
  <(apt list --installed 2>/dev/null|grep git|awk -F"/" '{print $1}'|xargs dpkg -L 2>/dev/null|sort|uniq|grep -v "usr/share/doc"|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|awk '{print $2}'|sed '$a /root/.gitconfig'|sed '$a /root/local/bin/install.arm64.sh' |sed '$a /etc/timezone' |sed '$a /root/.bashrc') \
  <(find /etc/ssh -type f ! -name 'sshd_config' ! -name 'ssh_config' ! -name 'moduli' ! -name 'ssh_host_*') \
  | sort | uniq \
  | grep -vE '^/etc/passwd$' \
  | grep -vE '^/root/\.ssh/config$' \
  | grep -vE '^/etc/ssh/(sshd_config|ssh_config|moduli)$' \
  | grep -vE '^/etc/ssh/ssh_host_' \
  | grep -vE '^/etc/pam\.d/sshd$' \
  | sed 's#^/##' \
  | tar -C / -czf $DEV_PKG -T -
