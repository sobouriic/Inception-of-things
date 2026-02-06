# Inception of Things - Part 1 (K3s + Vagrant)

This folder sets up 2 VMs with Vagrant:
- `sobouricS` (server/control-plane) -> `192.168.56.110`
- `sobouricSW` (agent/worker) -> `192.168.56.111`

Both machines run CentOS 7 and are provisioned with K3s.

## Files

- `Vagrantfile` - defines both VMs and network
- `scripts/install_k3s_server.sh` - installs and configures K3s server
- `scripts/install_k3s_agent.sh` - installs and configures K3s agent

## Run

From this folder:

```bash
cd ~/Desktop/Inception-of-things/p1
vagrant destroy -f
vagrant up
```

## Mandatory Checks (Evaluation)

### 1) SSH access to both VMs

```bash
vagrant ssh sobouricS
vagrant ssh sobouricSW
```

### 2) Hostnames

```bash
vagrant ssh sobouricS -c "hostname"
vagrant ssh sobouricSW -c "hostname"
```

Expected:
- `sobouricS`
- `sobouricSW`

### 3) `eth1` IP addresses

```bash
vagrant ssh sobouricS -c "ip a show eth1"
vagrant ssh sobouricSW -c "ip a show eth1"
```

Expected:
- server has `192.168.56.110`
- worker has `192.168.56.111`

### 4) Cluster has both nodes

Run on server:

```bash
vagrant ssh sobouricS -c "sudo /usr/local/bin/kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide"
```

Expected: 2 nodes in `Ready` state (`sobourics` and `sobouricsw`).

## Troubleshooting

- Vagrant lock error:
  - Find old process: `ps -ef | grep -E "vagrant|ruby"`
  - Kill stuck PID, then retry `vagrant up` / `vagrant destroy -f`
- If cluster shows only one node:
  - Re-provision worker: `vagrant provision sobouricSW`
  - Check agent logs: `vagrant ssh sobouricSW -c "sudo journalctl -u k3s-agent -n 100 --no-pager"`
