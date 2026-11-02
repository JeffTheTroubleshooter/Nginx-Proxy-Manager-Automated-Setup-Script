# Nginx Proxy Manager Automated Setup Script

Installs [Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager) with Docker Compose. If Docker isn't installed, the script installs it.

## Automatic Install

```bash
bash npm-install.sh
```

The script asks for an install directory (default `/opt/nginx-proxy-manager`) and the ports to use: HTTP `80`, HTTPS `443` and admin `81`. When it finishes, open the admin panel at `http://<server-ip>:81`.

**Default login:** `admin@example.com` / `changeme`. Change both the first time you sign in.

Ports 80 and 443 must be free, so stop any other web server on the machine first. If firewalld is running, the script opens the ports.

## Managing the Stack

```bash
sudo docker compose -f /opt/nginx-proxy-manager/docker-compose.yml ps
sudo docker compose -f /opt/nginx-proxy-manager/docker-compose.yml logs
sudo docker compose -f /opt/nginx-proxy-manager/docker-compose.yml restart
```

Your settings are in `data/` and your certificates are in `letsencrypt/` inside the install directory. Back them up.

## Uninstall

```bash
bash npm-install.sh uninstall
```

This stops the stack, and you can choose whether to also remove its data.

## Supported Distros

| Distro | Status |
|---|---|
| Fedora | Tested, works |
| Debian / Ubuntu (and Mint, Pop!_OS, Zorin, elementary) | Not tested, need feedback |
| RHEL / Rocky / AlmaLinux / CentOS | Not tested, need feedback |
| Arch / Manjaro / EndeavourOS / Garuda | Not tested, need feedback |
| openSUSE / SLES | Not tested, need feedback |
| Alpine | Not tested, need feedback |

If you try it on a distro that isn't tested, please open an issue and say how it went.

## Part of the Proxmox Homelab setup

This installer is used by [Proxmox-Homelab-Automated-Setup-Script](https://github.com/JeffTheTroubleshooter/Proxmox-Homelab-Automated-Setup-Script), which creates an LXC for each app on a Proxmox host and runs this script inside it.
