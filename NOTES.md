# Assignment 5 Part 2 — Embedded Socket Server (Buildroot)

## What This Assignment Is

Run the `aesdsocket` TCP server from Assignment 5 Part 1 **inside a QEMU AArch64 Buildroot image**.
The CI boots QEMU and runs `sockettest.sh` from the host — connecting through QEMU's forwarded port 9000.

---

## Implementation Checklist

- [x] `base_external/external.desc` — names the Buildroot external tree (`project_base`)
- [x] `base_external/external.mk` — includes all package `.mk` files from the external tree
- [x] `base_external/Config.in` — wires `aesd-assignments` package into menuconfig
- [x] `base_external/configs/aesd_qemu_defconfig` — QEMU AArch64 defconfig with required packages
- [x] `base_external/package/aesd-assignments/aesd-assignments.mk` — builds `aesdsocket` from Part 1 repo
- [x] `base_external/package/aesd-assignments/S99aesdsocket` — init.d script that starts `aesdsocket -d` on boot
- [x] `runqemu.sh` — forwarding `hostfwd=tcp::9000-:9000` so host sockettest.sh reaches QEMU
- [x] `clean.sh` — `make -C buildroot distclean`
- [x] `github-actions.yml` — updated to `checkout@v4`, `ssh-agent@v0.9.0`, timeout 1200 min

---

## How the Test Works

```
CI host
  └── runqemu.sh (QEMU boots AArch64 image)
        └── /etc/init.d/S99aesdsocket start → /usr/bin/aesdsocket -d
              └── listens on :9000 inside QEMU

  wait_for_qemu (SSH poll) + 40s wait for init.d

  validate_assignment5_qemu
    └── ./sockettest.sh
          └── nc localhost 9000  →  hostfwd  →  aesdsocket inside QEMU
```

---

## Lessons Learned

### 1. Port Forwarding Required for Socket Test

The `sockettest.sh` runs on the CI **host** and connects to `localhost:9000`.
QEMU only forwards `10022→22` (SSH) by default.
**Fix:** Add `hostfwd=tcp::9000-:9000` to the `runqemu.sh` `-netdev` line.

Without this, `sockettest.sh` tries to connect to the host's port 9000 (nothing listening) → test fails.

---

### 2. aesdsocket Must Start on Boot via init.d

The test flow is:
1. QEMU boots
2. `wait_for_qemu` polls SSH and then sleeps 40 seconds
3. `sockettest.sh` connects to port 9000

The server must be **already running** when sockettest.sh fires.
In Buildroot's BusyBox init, scripts named `S??*` in `/etc/init.d/` are executed with `start` at boot.

**Fix:** Install `S99aesdsocket` that calls `/usr/bin/aesdsocket -d`.
The `-d` flag (from Part 1 implementation) makes aesdsocket fork, setsid, and redirect stdio to `/dev/null`.

---

### 3. external.mk Variable Name is Case-Sensitive

Buildroot derives the external tree variable name from `name:` in `external.desc`.

```
# external.desc
name: project_base
```

Produces variable: `BR2_EXTERNAL_project_base_PATH` (lowercase, exact match).

Using `BR2_EXTERNAL_PROJECT_BASE_PATH` (uppercase) causes silent failure — the package is never found.

**Fix:** Always match the case in `external.mk`:
```makefile
include $(sort $(wildcard $(BR2_EXTERNAL_project_base_PATH)/package/*/*.mk))
```

And in `Config.in`:
```
source "$BR2_EXTERNAL_project_base_PATH/package/aesd-assignments/Config.in"
```

---

### 4. aesd-assignments.mk Must Use SSH URL (Not HTTPS)

The CI runner uses SSH keys to clone private repos. HTTPS clones fail because there is no password prompt in automated builds.

```makefile
# WRONG
AESD_ASSIGNMENTS_SITE = https://github.com/user/repo.git

# CORRECT
AESD_ASSIGNMENTS_SITE = git@github.com:user/repo.git
```

The build validator explicitly checks for HTTPS and will fail with a validate error if found.

---

### 5. defconfig Must Have Three Required Options

`validate_buildroot_config()` in `script-helpers` checks:

| Option | Why |
|--------|-----|
| `BR2_PACKAGE_DROPBEAR=y` | SSH server — CI SSHes into QEMU |
| `BR2_TARGET_GENERIC_ROOT_PASSWD="root"` | Allows `sshpass -p root` authentication |
| `BR2_PACKAGE_AESD_ASSIGNMENTS=y` | Triggers our package build |

Missing any one causes a validate error (though the build may still proceed with manual injection).

---

### 6. BR2_JLEVEL=1 Prevents glibc Race Condition

glibc 2.38 has a Makefile dependency bug in `elf/` — `ld.so` may be linked before `nptl/lowlevellock.o` is ready when using parallel make (`-j > 1`).

Setting `BR2_JLEVEL=1` forces single-threaded build, eliminating the race.
On WSL2 native ext4 (not NTFS), single-threaded glibc takes ~30-60 min.

---

### 7. Executable Bits on NTFS Must Be Set via git

NTFS does not store Unix executable permissions. Git tracks them independently.

If scripts are committed without the `+x` bit, the CI validator fails with "build.sh is not executable".

```bash
git update-index --chmod=+x build.sh clean.sh runqemu.sh save-config.sh full-test.sh shared.sh
```

This stores the correct `100755` mode in git, regardless of the NTFS filesystem.

---

### 8. $(AESD_ASSIGNMENTS_PKGDIR) Resolves to the Package's .mk Directory

In Buildroot's Make system, `$(AESD_ASSIGNMENTS_PKGDIR)` expands to the directory containing `aesd-assignments.mk` in the external tree.

Use it to reference files bundled with the package (like the init script):
```makefile
$(INSTALL) -m 0755 $(AESD_ASSIGNMENTS_PKGDIR)/S99aesdsocket $(TARGET_DIR)/etc/init.d/S99aesdsocket
```

---

### 9. build.sh Runs Twice Intentionally

The build script runs twice because:
1. First run: applies defconfig (creates `.config`) but does NOT build
2. Second run: detects existing `.config` → runs actual build

This is the standard Buildroot flow with an external tree and custom defconfig.

---

### 10. GitHub Actions Version Compatibility

| Old (deprecated) | New (required for Node 20 runner) |
|---|---|
| `actions/checkout@v2` | `actions/checkout@v4` |
| `webfactory/ssh-agent@v0.5.3` | `webfactory/ssh-agent@v0.9.0` |

Old versions fail silently or with Node.js deprecation warnings that break the job.

---

## File Summary

| File | Purpose |
|------|---------|
| `base_external/external.desc` | Names external tree `project_base` |
| `base_external/external.mk` | Includes all package `.mk` files |
| `base_external/Config.in` | Exposes packages in menuconfig |
| `base_external/configs/aesd_qemu_defconfig` | Full AArch64 QEMU defconfig |
| `base_external/package/aesd-assignments/aesd-assignments.mk` | Builds aesdsocket from Part 1 repo |
| `base_external/package/aesd-assignments/S99aesdsocket` | Init script to start aesdsocket on boot |
| `runqemu.sh` | Boots QEMU with ports 10022 (SSH) and 9000 (aesdsocket) forwarded |
| `clean.sh` | Runs `make -C buildroot distclean` |
| `build.sh` | First run applies defconfig; second run builds image |
| `save-config.sh` | Saves current `.config` as `aesd_qemu_defconfig` |
| `full-test.sh` | Dispatches to `assignment5-buildroot/assignment-test.sh` |

## Build

```bash
# First run (applies defconfig, no build yet)
./build.sh

# Second run (actual build)
./build.sh

# Run QEMU (ports: 10022→SSH, 9000→aesdsocket)
./runqemu.sh
# login: root / root

# Inside QEMU - verify aesdsocket is running
ps aux | grep aesdsocket

# From host - test socket
echo "hello" | nc localhost 9000
```
