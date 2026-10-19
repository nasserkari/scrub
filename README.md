```text

      ██╗    ██╗██████╗ ███████╗███╗   ██╗
      ██║    ██║██╔══██╗██╔════╝████╗  ██║
      ██║ █╗ ██║██████╔╝█████╗  ██╔██╗ ██║
      ██║███╗██║██╔══██╗██╔══╝  ██║╚██╗██║
      ╚███╔███╔╝██║  ██║███████╗██║ ╚████║
       ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

```

A shell script to clean your Linux

## Requirements

```text
bash, curl, sudo (not needed as root)
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nasserkari/wren/main/install | bash
```

To review the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/nasserkari/wren/main/install -o install
less install
bash install
```

## Usage

```bash
wren                 # Show available commands
wren --clean         # Clean cache, trash, logs, packages and more (see below)
wren --update        # Update to the latest version
wren --uninstall     # Uninstall wren
wren --version       # Show version (-v)
wren --help          # Show help (-h)
```

## What it cleans

```text
Cache      thumbnails, browser caches, npm, yarn and pip caches
Trash      files and info in the user trash
Logs       systemd journal older than 14 days
Packages   package cache, unused packages, Flatpak runtimes, old Snap revisions
Disk       SSD trim
```

## Supported package managers

```text
apt, dnf, pacman, zypper, apk
```

## Safety

```text
Never touches your documents or other personal files.
Emptying the trash, deleting old logs and removing unused packages
are permanent, so check that you no longer need them before running wren --clean.
```
