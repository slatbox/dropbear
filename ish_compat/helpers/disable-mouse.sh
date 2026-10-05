#!/bin/sh
# Reset terminal mouse-reporting modes on login.
#
# Some PC terminals keep mouse tracking enabled after a program (vim, htop,
# tmux, ...) exits without restoring modes. With mouse tracking on, moving
# the mouse sends "ESC [ M ..." sequences into the SSH session, which a
# plain shell echoes as garbage input. Turning all mouse modes off at login
# avoids that.
#
# Install as /etc/profile.d/disable-mouse.sh (sourced by /etc/profile).

printf '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l\033[?1015l'
