# Arsdactyl Pterodactyl Installer

This is a fully automated installation script for **Pterodactyl Panel and Wings**, customized to use any username and configured with the project name **arsdactyl**.

It allows easy setup on AWS VPS or any Linux server.

---

## Features

- Installs **Pterodactyl Panel** with PHP 8.3, MariaDB, Nginx, and Redis.
- Installs **Wings daemon** for managing game servers.
- Fully supports **any installation username** (not just root).
- Configures **systemd services** for panel queues and Wings.
- Prompts for database and admin credentials securely.
- Sets up Nginx configuration ready for SSL.

---

## Requirements

- Linux VPS (Ubuntu 22.04 recommended)
- Sudo access
- Open ports 80, 443, 8080 (default Wings port)
- Non-root user preferred (the installer allows custom username)

---

## Quick Installation

Run the installer in **one command**:

```bash
curl -sSL https://github.com/not-arslan/ptero-installer/raw/main/main-installer.sh | bash
