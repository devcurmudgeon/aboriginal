#!/bin/ash

export HOME=/home

# Populate /dev
mountpoint -q proc || mount -t proc proc proc
mountpoint -q sys || mount -t sysfs sys sys
mountpoint -q dev || mount -t devtmpfs dev dev || mdev -s
mkdir -p dev/pts
mountpoint -q dev/pts || mount -t devpts dev/pts dev/pts

# If nobody said how many CPUS to use in builds, try to figure it out.
if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1
fi
export PS1='($HOST:$CPUS) \w \$ '

# Make sure $PATH is exported, even if not set on kernel command line.
# (The shell gives us a default, but it's local, not exported.)
export PATH

# If we're running under qemu, do some more setup
if [ $$ -eq 1 ]
then

  # Note that 10.0.2.2 forwards to 127.0.0.1 on the host.

  # Setup networking for QEMU (needs /proc)
  ifconfig eth0 10.0.2.15
  route add default gw 10.0.2.2

  # If we have no RTC, try rdate instead:
  [ "$(date +%s)" -lt 1000 ] && rdate 10.0.2.2 # or time-b.nist.gov

  mount -t tmpfs /tmp /tmp

  # If there's a /dev/hdb or /dev/sdb, mount it on home, else tmpfs

  [ -b /dev/[hsv]db ] && HOMEDEV=/dev/[hsv]db
  if [ ! -z "$HOMEDEV" ]
  then
    mount -o noatime $HOMEDEV /home
  else
    # Only mount a tmpfs if / isn't writeable.
    touch /.temp 2>/dev/null
    [ $? -ne 0 ] && mount -t tmpfs /home /home || rm /.temp
  fi
  cd /home

  # If there's a /dev/hdc mount it on /mnt

  [ -b /dev/[hsv]dc ] && MNTDEV=/dev/[hsv]dc
  [ ! -z "$MNTDEV" ] && mount -o ro $MNTDEV /mnt

  [ -z "$CONSOLE" ] &&
    CONSOLE="$(sed -n 's@.* console=\(/dev/\)*\([^ ]*\).*@\2@p' /proc/cmdline)"
  [ -z "$CONSOLE" ] && CONSOLE=console

  if [ -z "$DISTCC_HOSTS" ]
  then
    echo "Not using distcc."
  else
    echo "Distcc acceleration enabled."
  fi
  echo Type exit when done.

  HANDOFF=/bin/ash
  if [ -e /mnt/init ]
  then
    X=xx
    echo "Press any key for command line..."
    read -t 3 -n 1 X
    if [ "$X" == xx ]
    then
      echo "Running automated build."
      HANDOFF=/mnt/init
    fi
  fi
  exec /sbin/oneit -c /dev/"$CONSOLE" "$HANDOFF"

# If we're not PID 1, it's probably a chroot.
else
  [ ! -z "$(grep "default for QEMU" /etc/resolv.conf)" ] &&
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

  # If we have no RTC, try using ntp to set the clock
  [ "$(date +%s)" -lt 10000000 ] && ntpd -nq -p north-america.pool.ntp.org

  # Switch to a shell with command history.

  echo Type exit when done.
  /bin/ash
  cd /
  umount ./dev/pts
  umount ./dev
  umount ./sys
  umount ./proc
  sync
fi
