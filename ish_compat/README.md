# dropbear on iSH (Minis) — ish-compat branch

This branch adds a small set of source patches so that
[dropbear](https://github.com/mkj/dropbear) runs as a login SSH server
inside **iSH**, the Linux emulator used by the iOS app
[Minis](https://github.com/OpenMinis/OpenMinis).

Upstream dropbear builds fine but every
interactive session dies right after authentication:

```
ioctl(TIOCSCTTY): I/O error
/dev/pts/N: I/O error
open /dev/tty failed - could not set controlling tty
```

These patches fix that and make password / public-key logins with a full
interactive PTY shell work.

## Why not OpenSSH?

OpenSSH 9.x uses a privileged monitor process and passes the PTY file
descriptor to the unprivileged session child over a Unix socket with
`SCM_RIGHTS`. iSH does not implement `recvmsg()` control messages
(`EINVAL`), so the session child never receives the PTY and the server
logs `mm_pty_allocate: receive fds failed` and aborts the connection
*after* a successful password/public-key authentication. This is
architectural — providing a key does **not** help. dropbear does not use
a privilege-separated fd hand-off, so it can work.

## The iSH pty bug these patches work around

In `fs/pty.c` of iSH, `pty_slave_close()` hangs up the pty **master**
whenever the last non-master slave fd is closed:

```c
static int pty_slave_close(struct tty *tty) {
    // If userland's reference count on the pty slave will go to 0,
    // hang up the pty master. ...
    if (tty->refcount - 1 == (tty->session ? 2 : 1))
        pty_hangup_other(tty);
    return 0;
}
```

Once the master is marked `hung_up`, `tty_ioctl()` returns `EIO` for
every ioctl and reads/writes fail — the pty is dead for good. Upstream
dropbear closes the slave fd in the parent right after `fork()`, which
triggers exactly this hangup before the child has finished
`pty_make_controlling_tty()`. Hence `TIOCSCTTY` -> `EIO`.

The patches keep a slave fd (and a redundant master dup) alive so the
refcount never drops to the point that would hang up the pty.

## Patches (relative to upstream `main`)

The same patches apply to tag `DROPBEAR_2024.86`; this branch tracks
upstream `main`.

### `src/svr-chansession.c`

1. **Child: don't close the master before `TIOCSCTTY`.**
   `close(chansess->master)` -> `fcntl(chansess->master, F_SETFD, FD_CLOEXEC)`.
   Keeps the master alive until `exec()` instead of closing it during
   session setup.

2. **Parent: don't close the slave.**
   `close(chansess->slave)` is commented out so the slave refcount never
   drops low enough to hang up the master while the child is setting up.

3. **Parent: keep a redundant `CLOEXEC` dup of the master.** Protects
   against the master fd being closed behind dropbear's back (an
   iSH quirk observed while tracing fds with an LD_PRELOAD shim).

4. **Skip utmp/wtmp accounting** (`login_login` / `login_logout`).
   iSH has no working utmp file (`wtmp_write: problem writing
   /dev/null/wtmp: Not a directory`); the calls only emit errors.

### `src/default_options.h`

5. **`DROPBEAR_REEXEC 0`.** iSH's `fexecve()` fails with `EFAULT`
   (`fexecve failed, disabling re-exec: Bad address`). The re-exec
   optimisation cannot work there; use the plain fork path.

## Building

```sh
./configure CFLAGS="-Os" --disable-zlib
make -j4 dropbear
install -m 755 dropbear /usr/local/sbin/dropbear-ish
```

(`--disable-zlib` because iSH's Alpine rootfs does not ship zlib headers
by default; dropbear works fine without compression.)

Host keys:

```sh
mkdir -p /etc/dropbear
dropbearkey -t rsa     -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa   -f /etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
```

## Running

See the helper scripts in `helpers/`:

- `install-sshd.sh`  — install the binary, host keys and helpers.
- `start-sshd.sh`    — start the server on a free port.
- `restart-sshd.sh`  — restart the server, picking a new port if
  the old one is stuck.
- `disable-mouse.sh` — `/etc/profile.d` snippet that resets terminal
  mouse-reporting modes on login.

## Notes / gotchas

- **iSH leaks listening ports.** After a dropbear process is killed, the
  emulated TCP stack often refuses to `bind()` the same port again
  (`Address in use`) even though nothing is listening. The helper
  scripts therefore walk upward from a base port until `bind()` succeeds.
- **Testing with piped stdin gives false failures.** `sshpass ... ssh -tt
  host 'cmd'` with stdin from a pipe immediately sends `CHANNEL_EOF`;
  dropbear's `close_chan_fd()` then (correctly) closes the pty master
  and the session drops instantly. Use a real terminal, or keep stdin
  open, e.g. `(echo 'cmd; exit'; sleep 3) | ssh ...`.
- The service dies whenever iOS suspends the Minis app (screen lock /
  app switch). Restart it with `restart-sshd` after returning to the
  app; there is no true background persistence on iOS.
