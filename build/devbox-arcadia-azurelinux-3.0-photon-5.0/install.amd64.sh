# Arcadia install script (example)
# Extract tarballs into system root.
#
# Usage:
#   sudo ./install.amd64.sh

set -e

tar zxf amd64.arcadia.dev.base.azl3.0.tar.gz -C /
tar zxf amd64.arcadia.emacs30.1_azl3.0.tar.gz -C /

# Keep consistent with existing pattern
source ~/.bashrc
