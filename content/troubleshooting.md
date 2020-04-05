# Troubleshooting
Changing TLS certificates on the apiserver, you'll need to refresh the service accounts as they contain invalid tokens.

    kubectl delete serviceaccount default
    kubectl delete serviceaccount --namespace=kube-system default

Check service logs by 

    journalctl -xeu kube-apiserver
    journalctl -xeu kube-controller-manager
    journalctl -xeu kube-scheduler
    journalctl -xeu kubelet
    journalctl -xeu kube-proxy

Starting from Kubernetes 1.8, the nodes running kubelet have to be swap disabled

The assigned swap memory can be disabled by using swapoff command. You can list all currently mounted and active swap partition by a following command:

    cat /proc/swaps
    Filename                                Type            Size    Used    Priority
    /dev/dm-0                               partition       1679356 600     -1

To temporarely switch off swap use the following command

    swapoff -a

    cat /proc/swaps
    Filename                                Type            Size    Used    Priority

To defenively disable swap, modify the fstab file by commenting the swap mounting

    /dev/mapper/os-root     /                         xfs     defaults        1 1
    UUID=49e78f32-2e92-4acd-9b8b-ef41b13c3a7d /boot   xfs     defaults        1 2
    # /dev/mapper/os-swap     swap                    swap    defaults        0 0

Check the disk usage of the worker nodes

    find / -printf '%s %p\n'| sort -nr | head -10
    
When disk usage is reaching 80%, worker nodes become unschedulable. Check this by:

    # download and install jq
    wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
    chmod +x jq-linux64 && mv jq-linux64 /usr/bin/jq
    
    # query kube nodes
    kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.status == "True") | select(.type == "DiskPressure")) | .metadata.name'

