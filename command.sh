case $SSH_ORIGINAL_COMMAND in
  lock) pmset displaysleepnow ;;
  shutdown) sudo -n -l /sbin/shutdown -h now >/dev/null || exit 1; nohup sudo -n /sbin/shutdown -h now </dev/null >/dev/null 2>&1 & ;;
  *) echo 'usage: lock | shutdown' >&2; exit 1 ;;
esac
