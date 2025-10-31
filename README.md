# Arsdactyl Pterodactyl Installer

This is a fully automated installation script for the **Pterodactyl Panel and Wings** daemon, customized to use the username of your choice and the project name **`arsdactyl`**. It is compatible with AWS VPS or any Linux server.

---

## Features

- Installs **Pterodactyl Panel** with all dependencies:
  - PHP 8.3, MariaDB, Nginx, Redis
- Installs **Wings daemon** for managing game servers
- Fully supports **any installation username** (not just root)
- Configures **systemd services** for panel queues and Wings
- Prompts for database and admin credentials securely
- Sets up Nginx and SSL-ready configuration

---

## Requirements

- A Linux VPS (Ubuntu 22.04 recommended)
- A non-root user for installation (e.g., `ubuntu`, `ec2-user`)
- Access to `sudo`
- Open ports 80, 443, and 8080 (default Wings port)

---

## Installation

1. **Clone or download the script**:

```bash
git clone https://github.com/yourusername/arsdactyl-installer.git
cd arsdactyl-installer
chmod +x install.sh
