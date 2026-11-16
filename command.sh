case $SSH_ORIGINAL_COMMAND in
	lock) pmset displaysleepnow || exit 1; case $(sysadminctl -screenLock status 2>&1) in
		*immediate*) ;;
		*) echo 'display is off, but screen lock is not immediate' >&2; exit 1 ;;
	esac ;;
	shutdown) sudo -n -l /sbin/shutdown -h now >/dev/null || exit 1; nohup sudo -n /sbin/shutdown -h now </dev/null >/dev/null 2>&1 & ;;
	*) echo 'usage: lock | shutdown' >&2; exit 1 ;;
esac
