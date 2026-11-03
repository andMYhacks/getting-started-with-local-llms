# Linux Dev Server Setup Guide

A reference guide for setting up your own Ubuntu 24.04 LTS headless development server for remote software development and security research, with NVIDIA GPU support, local LLM inference, and secure remote access.

**Reference Hardware:** 6TB storage · 64GB RAM · EVGA GeForce RTX 3080 Ti

**Reference client:** MacBook Air via Tailscale SSH

---

## Table of Contents

1. Choosing a Linux Distribution
2. Writing the Installation Image on macOS
3. Disk Partitioning and Encryption
4. 1Password CLI for Secrets Management
5. Adding the Server to Tailscale
6. SSH Key Setup and Troubleshooting
7. Install tooling

---

## 1. Choosing a Linux Distribution

**Recommended:** Ubuntu Server LTS (currently running 24.04, Noble Numbat)

### Why Ubuntu 24.04 LTS

- **NVIDIA/CUDA support** is strongest on Ubuntu. Ollama, CUDA, cuDNN, and the NVIDIA container toolkit all target Ubuntu as their primary platform—it provides zero friction getting the RTX 3080 Ti working for local LLM inference.
- **Long-term stability.** Five years of security patches and kernel updates. No mandatory OS upgrades every 6–13 months as with Fedora.
- **Dominant ecosystem.** When you hit issues with Ollama, CUDA, or security tooling, community responses to issues will almost always have an Ubuntu-specific answer.
- **Security research compatibility.** AppArmor out of the box, good UFW firewall tooling, broad compatibility with Metasploit, Burp Suite, Wireshark, and most other CTF tooling.

### Install the Server Edition

Install **Ubuntu Server 24.04 LTS** (not Desktop) — it's lighter, has no display manager overhead, and is purpose-built for remote access over SSH.

### Storage Notes

With 6TB of storage, use a separate `/data` partition for LLM model weights and project files so OS reinstalls never touch them. Large Ollama models (30B+ parameter files) can easily consume hundreds of GBs.

### Ollama Security Note

By default, Ollama is only available to users directly logged into the system. Exposing it outside the server presents a security risk since Ollama has no built-in authentication. Plan your network exposure carefully, especially given the security research context.

---

## 2. Writing the Installation Image on macOS

### Step 1: Identify the Disk

Plug in your target USB drive, then run:

```bash
diskutil list
```

Look for a disk marked **external, physical** whose size matches your drive. Example output:

```
/dev/disk0 (internal, physical):   # Your Mac's internal drive — DO NOT USE
/dev/disk4 (external, physical):   # Your USB drive
   #:    TYPE    NAME     SIZE
   0:    GUID             32.0 GB   disk4
```

> ⚠️ **Double-check the disk identifier and size before proceeding.** Writing to the wrong disk will destroy its data.
> 

### Step 2: Unmount the Disk

macOS auto-mounts external drives. Unmount it before writing (this keeps it available to `dd` without macOS interfering):

```bash
diskutil unmountDisk /dev/disk4
```

Replace `disk4` with your actual disk identifier.

### Step 3: Write the Image

Use `dd` with the **raw disk path** (`rdisk4` not `disk4`) for significantly faster writes:

```bash
sudo dd if=/path/to/ubuntu-24.04-live-server-amd64.iso \
        of=/dev/rdisk4 \
        bs=1m \
        status=progress
```

- `if=` — path to your downloaded Ubuntu ISO
- `of=` — raw disk device (`rdisk` prefix, not `disk`)
- `bs=1m` — 1MB block size for efficient writing
- `status=progress` — shows live progress

> If your download ends in `.iso.gz` or `.xz`, decompress it first. The standard Ubuntu download from ubuntu.com is a plain `.iso` and can be written directly.
> 

### Step 4: Eject When Done

```bash
diskutil eject /dev/disk4
```

The drive is ready to boot from. In your desktop's BIOS/UEFI (usually F2, F12, or DEL on boot), set USB as the first boot device.

---

## 3. Disk Partitioning and Encryption

### Recommended Partition Layout

| Mount Point | Size | Purpose |
| --- | --- | --- |
| `/boot/efi` | 1 GB | UEFI boot partition (must be unencrypted) |
| `/boot` | 2 GB | Kernel and initrd (must be unencrypted) |
| `/` | 100 GB | OS and system packages |
| `/home` | 500 GB | User files, dotfiles, SSH keys |
| `/var` | 200 GB | Logs, Docker images, package cache |
| `/tmp` | 20 GB | Temporary files |
| `swap` | 64 GB | Match RAM size for hibernation support |
| `/data` | ~5.1 TB (remainder) | LLM model weights, research data, projects |

### Encryption Strategy

Use **LUKS2** (Linux Unified Key Setup), the standard Linux full-disk encryption. A single LUKS container wraps an LVM volume group, so one passphrase unlocks everything at boot. Later on you’ll learn how to unlock the drive remotely if there’s an unexpected restart while you’re away from home.

Note that only `/boot/efi` and `/boot` must remain unencrypted—the firmware needs to read these before decryption can happen. Everything else, including swap, lives inside the encrypted container.

### Step-by-Step in the Ubuntu Installer (Subiquity)

#### 1. Select Custom Storage Layout

On the storage screen, choose **Custom storage layout** → Done.

#### 2. Create the Unencrypted Boot Partitions

Select free space → **Add GPT Partition** for each:

- **Partition 1:** Size `1G`, Format `fat32`, Mount `/boot/efi`
- **Partition 2:** Size `2G`, Format `ext4`, Mount `/boot`

#### 3. Create the LUKS Device on Remaining Space

Select remaining free space → **Add GPT Partition**:

- Size: everything remaining
- Format: **Leave unformatted**
- Hit Create

Then select that unformatted partition and choose **"Format: dm-crypt"** or **"Make LUKS Volume"** from its action menu. You'll be prompted to set and confirm your encryption passphrase. This creates a new `dm-crypt` device in the list.

#### 4. Create an LVM Volume Group on the LUKS Device

Select the `dm-crypt` device → **"Create LVM volume group"** → name it `ubuntu-vg`.

#### 5. Create Logical Volumes

Select the volume group → **"Create logical volume"** for each:

| Name | Size | Format | Mount |
| --- | --- | --- | --- |
| `lv-root` | 100G | ext4 | `/` |
| `lv-home` | 500G | ext4 | `/home` |
| `lv-var` | 200G | ext4 | `/var` |
| `lv-tmp` | 20G | ext4 | `/tmp` |
| `lv-swap` | 64G | swap | — |
| `lv-data` | remaining | ext4 | `/data` |

#### 6. Verify the Layout

Before confirming, the storage tree should look like this:

```
/dev/sda
  ├── sda1    fat32      /boot/efi    ← UNENCRYPTED
  ├── sda2    ext4       /boot        ← UNENCRYPTED
  └── sda3    dm-crypt               ← LUKS container
        └── ubuntu-vg   LVM
              ├── lv-root    ext4    /
              ├── lv-home    ext4    /home
              ├── lv-var     ext4    /var
              ├── lv-tmp     ext4    /tmp
              ├── lv-swap    swap
              └── lv-data    ext4    /data
```

Only `/boot/efi` and `/boot` should sit outside the LUKS layer.

---

## 4. 1Password CLI for Secrets Management

### The Challenge

The 1Password desktop app's SSH agent and GUI-based unlock won't work on a headless server. Instead, use **1Password Service Accounts** with the `op` CLI.

### Architecture

| Use Case | Method |
| --- | --- |
| API keys, tokens, passwords on the server | `op` CLI + Service Account token |
| SSH key auth (GitHub, other servers) | SSH agent forwarding from your Mac |
| Secrets in scripts / systemd services | `op run` with secret references |
| Secrets in config files | `op inject` with templates |

### Step 1: Create a Dedicated Vault

Create a vault named `dev-server` (or similar) at 1password.com. Service accounts cannot access your personal/private vault, so this is required.

### Step 2: Create a Service Account

Go to `my.1password.com → Developer → Infrastructure Secrets → Service Accounts`. Create one with read access to your `dev-server` vault. Copy the token — it starts with `ops_` and is shown **only once**.

### Step 3: Install the `op` CLI on the Server

```bash
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
  https://downloads.1password.com/linux/debian/amd64 stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list

sudo apt update && sudo apt install 1password-cli
```

### Step 4: Configure the Service Account Token

Store the token in a root-only file rather than your shell profile:

```bash
# /etc/environment or a 600-permission file loaded by systemd
OP_SERVICE_ACCOUNT_TOKEN="ops_xxxxxxxxxxxx"
```

### Step 5: Pull Secrets on Demand

```bash
# Read a single secret
op read "op://dev-server/my-api-key/credential"

# Inject secrets as environment variables before running a command
op run --env-file=".env.tpl" -- python my_script.py
```

### Using Secret References

Store references instead of plaintext values in your `.env` files:

```bash
ANTHROPIC_API_KEY=op://dev-server/claude-api/credential
DATABASE_URL=op://dev-server/postgres/password
```

Then inject at runtime:

```bash
op run --env-file=.env -- ./your-app
```

### SSH Agent Forwarding from Your Mac

Since your Mac runs the full 1Password app, you can forward its SSH agent to the server for key operations (e.g. pushing to GitHub). Add this to `~/.ssh/config` on your Mac:

```
Host desktop.tail1ab858.ts.net
    ForwardAgent yes
    IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

Auth prompts for SSH key use will route back to your Mac's 1Password for biometric approval. The private key never touches the server.

---

## 5. Adding your Server(s) to Tailscale

### How It Works with GitHub Auth

The GitHub OAuth login is only needed for the interactive browser-based flow. For a headless server you bypass that entirely using an **auth key** generated from the admin console.

### Step 1: Generate an Auth Key (on your Mac)

Go to login.tailscale.com/admin/settings/keys → **Generate auth key**:

- **Reusable:** No (one-time use for a single server)
- **Expiry:** 1–90 days (only affects adding new devices, not how long the server stays connected)
- **Pre-approved:** Yes
- **Tags:** `tag:server` (recommended for ACL rules)

Store this key in your 1Password `dev-server` vault immediately.

### Step 2: Install Tailscale on the Server

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
```

### Step 3: Connect Using the Auth Key

```bash
# Directly:
sudo tailscale up --auth-key=tskey-auth-xxxxxxxxxxxxxxxx

# Or pulling from 1Password:
sudo tailscale up --auth-key=$(op read "op://dev-server/tailscale-authkey/credential")
```

### Step 4: Disable Key Expiry for the Server

In the Tailscale admin console → Machines page → select your server → **Disable key expiry**. This prevents the server from requiring re-authentication after 180 days.

### Step 5: Enable Tailscale SSH (Easiest option)

```bash
sudo tailscale up --auth-key=tskey-auth-xxxxxxxxxxxxxxxx --ssh
```

This lets Tailscale manage SSH access using your Tailscale identity, without exposing SSH to the public internet at all.

---

## 6. SSH Key Setup and Troubleshooting

### Fixing `Permission denied (publickey)`

This error means SSH is rejecting the connection before `ssh-copy-id` can deliver the key. You need an existing valid authentication method to bootstrap key delivery.

#### Most Likely Cause: Password Auth is Disabled

Ubuntu Server 24.04 disables password authentication by default. Check:

```bash
grep -i passwordauthentication /etc/ssh/sshd_config
grep -i passwordauthentication /etc/ssh/sshd_config.d/*.conf
```

If either returns `PasswordAuthentication no`, temporarily enable it:

```bash
sudo nano /etc/ssh/sshd_config.d/60-temp-password.conf
```

Add the following, but make a note to go back and turn it off later!

```
PasswordAuthentication yes
```

Then:

```bash
sudo systemctl restart ssh
```

### Create an SSH key on your laptop

Add an SSH key on the system you plan to SSH in from

```bash
ssh-keygen -t ed25519 -C "comment which system this key came from"
```

Copy the key over from your Mac with `scp`. Once key-based login is confirmed working, remove the temporary config from your remote system:

```bash
scp ~/.ssh/filename.pub user@remote_system:~/.ssh/
sudo rm /etc/ssh/sshd_config.d/60-temp-password.conf
sudo systemctl restart ssh
```

#### Alternative: Copy the Key Manually

If you have any way to run commands on the server directly (physically, or via the Tailscale SSH console in the admin panel):

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
# Paste the contents of ~/.ssh/tailscale.pub from your Mac
chmod 600 ~/.ssh/authorized_keys
```

Get your public key on the Mac with:

```bash
cat ~/.ssh/tailscale.pub
```

#### Other Things to Check

**Verify the correct key is being offered:**

```bash
ssh -i ~/.ssh/tailscale -v kyouma@desktop.tail1ab858.ts.net 2>&1 | grep "Offering\|denied"
```

**Confirm both key files exist on the Mac:**

```bash
ls -la ~/.ssh/tailscale ~/.ssh/tailscale.pub
```

**Fix permissions on the Mac:**

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/tailscale
```

SSH is strict about key file permissions — if they're too open it will silently refuse to use the key.

### Configure SSH on Your Mac

Add this to `~/.ssh/config` on your Mac so you don't have to specify the key manually each time:

```
Host hostname.tailscale-instance.ts.net
    User username
    IdentityFile ~/.ssh/tailscale_keyname
    IdentitiesOnly yes
    ForwardAgent yes
    IdentityAgent "~/Library/Group Containers/path.to.com.1password/t/agent.sock"
```

### Remote Unlocking at Boot (Dropbear)

Because this is a headless server, an unexpected reboot will leave it sitting at a LUKS passphrase prompt — SSH won't be available until you physically type it. Fix this with **Dropbear**, a tiny SSH server that runs in the early boot environment:

```bash
sudo apt install dropbear-initramfs
```

Add your SSH public key to Dropbear's authorized keys:

```bash
sudo nano /etc/dropbear/initramfs/authorized_keys
# Paste your public key, save and exit

```

Update `dropbear` so that it doesn’t allow password authentication:

```bash
sudo nvim /etc/dropbear/initramfs/config
DROPBEAR_OPTIONS="-s -j -k -I 300"
# Save and exit, then run:
sudo update-initramfs -u
```

### Add `tailscale-initramfs` so that you can access over Tailscale

Add the repo and give it an auth key

```bash
sudo mkdir -p --mode=0755 /usr/local/share/keyrings
curl -fsSL https://darkrain42.github.io/tailscale-initramfs/keyring.asc \
  | sudo tee /usr/local/share/keyrings/tailscale-initramfs-keyring.asc >/dev/null

printf 'Types: deb\nURIs: https://darkrain42.github.io/tailscale-initramfs/repo\nSuites: stable\nComponents: main\nSigned-By: /usr/local/share/keyrings/tailscale-initramfs-keyring.asc\n' \
  | sudo tee /etc/apt/sources.list.d/tailscale-initramfs.sources >/dev/null

sudo apt update && sudo apt install tailscale-initramfs
```

Add a Tailscale auth key:

```bash
sudo nvim /etc/tailscale/initramfs/config   # set the authkey line per the template
sudo chmod 600 /etc/tailscale/initramfs/config
```

Then, rebuild the `initramfs` by running:

```bash
sudo update-initramfs -u -k all
```

### Final steps

Then update `grub` to make sure you can get a public IP address:

```bash
sudo nvim /etc/default/grub
# append ip=dhcp inside the quotes, e.g.:
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ip=dhcp"
sudo update-grub
```

After this, when the server boots you can SSH in during the pre-boot phase and unlock remotely:

```bash
ssh -p 22 root@server-name.tail1ab858.ts.net
# Then at the Dropbear shell:
cryptroot-unlock
```

### Important: Store Your Passphrase in 1Password

Store your LUKS passphrase in 1Password immediately. If you lose it, the encrypted data is completely unrecoverable.

## Install Drivers & Tooling

You’re going to need some tools installed to make use of local LLMs. Here’s a starter kit:

First, after you’ve tested and confirmed that everything is working with your SSH key, turn off Password authentication:

Check if `PasswordAuthentication` is still enabled:

```bash
grep -i passwordauthentication /etc/ssh/sshd_config
grep -i passwordauthentication /etc/ssh/sshd_config.d/*.conf
```

If either returns `PasswordAuthentication yes`, disable it:

```bash
sudo nano /etc/ssh/sshd_config.d/60-temp-password.conf
```

Change the following and save it

```
PasswordAuthentication no
```

Then install `pipx` so that you can install `uv`

```bash
sudo apt install pipx && pipx install uv
```

Add the following to the end of your `.bashrc` to always login to the system in a `venv` (be sure to first setup a virtual environment with `uv venv --seed`)

```bash
if [ -f "$HOME/.venv/bin/activate" ]; then
    source "$HOME/.venv/bin/activate"
fi

```

You’re also going to need `nvidia-smi` and drivers (check which version you need for your card)

```bash
sudo apt install nvidia-utils-580 && \
sudo apt install nvidia-driver-580
```

You’ll need to reboot after this, and if you’ve setup LVM on LUKS you’re going to need to SSH in and run `cryptroot-unlock` .

After this unlocks, confirm your drivers and CUDA version with `nvidia-smi` . It should look something like this:

```bash
+------------------------------------------------------------------------------+
| NVIDIA-SMI 580.173.02    Driver Version: 580.173.02       CUDA Version: 13.0 |
+------------------------+------------------------------+----------------------+
```

After you’ve confirmed which CUDA version you’re on, install vLLM

```bash
uv pip install vllm --torch-backend auto
```

Homewbrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Colima:

```bash
brew install colima
```

Install Ollama (you never know if you’ll want / need it later)

```bash
curl -fsSL https://ollama.com/install.sh | sh

#set Ollama's download location to /data/ollama
mkdir /data/ollama
```

Then run `sudo systemctl edit ollama` and add the following

```bash
[Service]
Environment="OLLAMA_MODELS=/data"
```

Then reload the daemon’s

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Install HuggingFace CLI

```bash
sudo mkdir /data && \
export HF_HOME=/data/huggingface && \
sudo chown -R $USER:$USER /data && \
chmod 755 /data && \
curl -LsSf https://hf.co/cli/install.sh | bash
```

Install `neovim` on your system

- `sudo apt install neovim`
- `brew install neovim`
- . . . (something else)

Install LazyVim, first by backing up old configs if they exist

```bash
# required
mv ~/.config/nvim{,.bak}
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}
```

- Then install LazyVIM with
`git clone https://github.com/LazyVim/starter ~/.config/nvim`
- Clean up the install folder with `rm -rf ~/.config/nvim/.git`
- Finalize setup with `nvim`
