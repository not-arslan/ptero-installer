# Ptero Installer

An all-in-one **interactive Bash installer** for [Pterodactyl Panel](https://pterodactyl.io), Wings, and Blueprint Framework.  
This script simplifies setup, configuration, and management of your Pterodactyl environment.

---

## Features

- Install **Pterodactyl Panel** with automated database setup
- Install **Wings Daemon** with optional SSL setup
- Install **Blueprint Framework** for enhanced panel features
- Run **Panel Fixer** for common issues
- Uninstall Panel, Wings, or Blueprint
- Interactive prompts with validation for database and admin credentials
- Supports Ubuntu 22.04+  

---

## System Requirements

### Minimum:

- Ubuntu 22.04 or Debian 11
- 1 CPU core
- 1 GB RAM
- 10 GB Disk
- PHP 8.3
- MariaDB / MySQL
- Nginx
- Redis
- Docker (for Wings)

### Recommended:

- Ubuntu 22.04 or Debian 11
- 2+ CPU cores
- 2+ GB RAM
- 20+ GB Disk
- PHP 8.3 with required extensions (`gd`, `mbstring`, `bcmath`, `xml`, `curl`, `zip`, `fpm`)
- MariaDB / MySQL 10.5+
- Nginx with SSL
- Redis 6+
- Docker & Docker Compose
- Node.js 20+ & Yarn (for Blueprint)

---

## Installation

Run the installer directly from GitHub with a single command:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/not-arslan/ptero-installer/main/ptero_installer.sh)
