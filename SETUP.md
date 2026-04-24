# Assignment 5 Part 2 — Setup & Debug Guide

## Step 1: Fix SSH Key Access

### 1a. Test key works for GitHub

```bash
ssh -T git@github.com -i ~/.ssh/github_actions_key
```

Expected output:
```
Hi mohamed-soubhi! You've successfully authenticated, but GitHub does not provide shell access.
```

If it fails → key not in GitHub account. Add it:

```bash
cat ~/.ssh/github_actions_key.pub
```

Copy output → go to `https://github.com/settings/keys` → **New SSH key** → paste → Save.

---

### 1b. Test clone of Part 1 repo

```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/github_actions_key -o StrictHostKeyChecking=no" \
  git clone git@github.com:mohamed-soubhi/Assignment5Part1_MSoubhi.git /tmp/test_a5p1
```

If this fails with **Permission denied** even though step 1a passed → Part 1 repo is private and needs a deploy key.

Add deploy key to Part 1 repo:
- Go to `https://github.com/mohamed-soubhi/Assignment5Part1_MSoubhi/settings/keys`
- Click **Add deploy key**
- Paste contents of `~/.ssh/github_actions_key.pub`
- Title: `CI Key`
- Read-only is fine (no write access needed)
- Save

---

### 1c. Add SSH_PRIVATE_KEY secret to Part 2 repo

```bash
cat ~/.ssh/github_actions_key
```

Copy full output (including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`).

Go to:
`https://github.com/mohamed-soubhi/Assignment5Part2_EmbeddedSocketServer/settings/secrets/actions`

Click **New repository secret**:
- Name: `SSH_PRIVATE_KEY`
- Value: paste the private key content
- Save

---

## Step 2: Build Locally on Native ext4

**Must build on WSL2 native ext4 — NOT on `/mnt/c/` (NTFS).**

```bash
cd ~/assignment5p2/Assignment5Part2_EmbeddedSocketServer

# Strip Windows paths that break Buildroot
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/mnt/c/' | tr '\n' ':' | sed 's/:$//')

# Set SSH key for Buildroot git downloads
export GIT_SSH_COMMAND="ssh -i ~/.ssh/github_actions_key -o StrictHostKeyChecking=no"

# Clean any previous failed state
rm -rf buildroot/output buildroot/.config

# Run 1: applies defconfig (fast)
./build.sh

# Run 2: full build (~30-60 min on ext4)
./build.sh
```

Build success looks like:
```
>>> aesd-assignments ... Cloning into ...
>>> linux 6.1.44 Installing to images directory
Image: rootfs.ext4
```

Verify images exist:
```bash
ls -lh buildroot/output/images/
# Must show: Image  rootfs.ext2  rootfs.ext4 -> rootfs.ext2
```

---

## Step 3: Test QEMU Locally

### 3a. Start QEMU

Open **Terminal 1**:
```bash
cd ~/assignment5p2/Assignment5Part2_EmbeddedSocketServer
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/mnt/c/' | tr '\n' ':' | sed 's/:$//')
./runqemu.sh
```

Wait for boot messages to appear (~20-30 seconds). You will see Linux kernel boot log.

### 3b. SSH into QEMU

Open **Terminal 2**:
```bash
ssh -o StrictHostKeyChecking=no -p 10022 root@localhost
# password: root
```

### 3c. Verify aesdsocket is running inside QEMU

```bash
# Inside QEMU
ps aux | grep aesdsocket
# Expected: aesdsocket process running (started by /etc/init.d/S99aesdsocket)

netstat -tlnp | grep 9000
# Expected: aesdsocket listening on 0.0.0.0:9000
```

### 3d. Test socket from host

Open **Terminal 3** (on host, not inside QEMU):
```bash
echo "hello" | nc localhost 9000
# Expected: echoes "hello" back

echo "world" | nc localhost 9000
# Expected: echoes "hello\nworld" back (full file since last start)
```

---

## Step 4: Run Full Socket Test Locally

```bash
cd ~/assignment5p2/Assignment5Part2_EmbeddedSocketServer
sudo bash assignment-autotest/test/assignment5-buildroot/sockettest.sh
# Expected: Tests complete with success!
```

---

## Step 5: Trigger CI

Once local test passes, push to trigger CI:

```bash
cd ~/assignment5p2/Assignment5Part2_EmbeddedSocketServer
git push origin main
```

Watch CI at:
`https://github.com/mohamed-soubhi/Assignment5Part2_EmbeddedSocketServer/actions`

Expected final CI output:
```
Test of assignment assignment5-buildroot complete with success
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Permission denied (publickey)` during build | SSH key not authorized | Steps 1a–1c |
| `Could not open rootfs.ext4` in QEMU | Build failed, no rootfs generated | Fix SSH key → rebuild |
| `Your PATH contains spaces` | Windows PATH leaking into WSL2 | Export clean PATH (Step 2) |
| glibc build race / `ld.so Error 1` | Building on NTFS | Move to native ext4 (Step 2) |
| `Connection refused` on port 10022 | QEMU not started | Check images exist; check QEMU error output |
| Port 10022 open but login fails | Wrong password or Dropbear not built | Verify `BR2_PACKAGE_DROPBEAR=y` in defconfig |
