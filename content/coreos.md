# Setup CoreOS Kubernetes
**Tectonic** by **CoreOS** is a Kubernetes ditribution based on **Container Linux**, a minimalistic Linux distribution well designed to run containers. In addition to vanilla Kubernetes, Tectonic comes with a Container Management Platform built on top of kubernetes.

In this section, we're going to setup a Kubernetes cluster on virtual machines using a PXE infrastructure. The same should be easly ported in a bare metal environment. Our cluster will be made of a single master node and three worker nodes:

  * core00.noverit.com (master)
  * core01.noverit.com (worker)
  * core02.noverit.com (worker)
  * core03.noverit.com (worker)

These are the minimum requirements for Container Linux machines:

 * 2 Core CPU
 * 8 GB RAM
 * 32 GB HDD

An additional machine with any Linux OS will be used as provisioner machine.

## Preflight
To setup a Tectonic cluster on virtual or bare metal nodes, we'll require the following items:

 * Bare metal or virtual machines with BIOS options set to boot from hard disk and then network
 * PXE network boot environment with DHCP, TFTP, and DNS services
 * [Matchbox](https://github.com/coreos/matchbox) server that provisions Container Linux on the nodes
 * [Tectonic](https://coreos.com/tectonic) installer
 * SSH keypair to login into Container Linux nodes

### Bare metal or virtual machines
Configure the machines to boot from disk first and then from network via PXE boot. Take note of the MAC address of each machine.

### PXE network environment
Login to the provisioner machine and configure DHCP, TFTP, and DNS services to make machines bootable from PXE boot. You can go with a dnsmasq service implementing all the functions you nedd.

In some cases, you already have a DHCP and DNS servers in your environment. In that case, run only proxy DHCP and TFTP services on the host network instead. Make sure to configure your DHCP to assign static IPs to the machines and make your DNS aware of all machines names. Also you nedd to add DNS names for the control plane (i.e. the master node) and for the data plane (i.e. a load balancer on top of the worker nodes, otherwise one of the worker nodes).

Install dnsmasq on the provisioner machine

    yum install -y dnsmasq

Configure the services by editing the ``/etc/dnsmasq.conf`` configuration file:

    # DHCP mode
    interface=ens33
    domain=noverit.com
    # dhcp range used only during the pxe booting
    dhcp-range=10.10.10.200,10.10.10.250
    enable-tftp
    tftp-root=/var/lib/tftpboot
    # set boot options
    dhcp-match=set:bios,option:client-arch,0 
    dhcp-boot=tag:bios,undionly.kpxe 
    dhcp-match=set:efi32,option:client-arch,6
    dhcp-boot=tag:efi32,ipxe.efi 
    dhcp-match=set:efibc,option:client-arch,7 
    dhcp-boot=tag:efibc,ipxe.efi 
    dhcp-match=set:efi64,option:client-arch,9 
    dhcp-boot=tag:efi64,ipxe.efi 
    dhcp-userclass=set:ipxe,iPXE 
    dhcp-boot=tag:ipxe,http://matchbox.noverit.com:8080/boot.ipxe 
    # static mapping for the name of the master node
    dhcp-host=core00.noverit.com,10.10.10.190 
    # static mapping for the names of the worker nodes
    dhcp-host=core01.noverit.com,10.10.10.191 
    dhcp-host=core02.noverit.com,10.10.10.192 
    dhcp-host=core03.noverit.com,10.10.10.193
    # matchbox machine
    address=/matchbox.noverit.com/10.10.10.2
    # control plane machine
    address=/master.noverit.com/10.10.10.190
    # data plane load balance machine
    address=/tectonic.noverit.com/10.10.10.2
    log-queries 
    log-dhcp

Alternatively:

    # DHCP proxy mode
    interface=ens33
    domain=noverit.com
    dhcp-range=10.10.10.0,proxy,255.255.255.0
    enable-tftp
    tftp-root=/var/lib/tftpboot
    dhcp-userclass=set:ipxe,iPXE
    pxe-service=tag:#ipxe,x86PC,"PXE chainload to iPXE",undionly.kpxe
    pxe-service=tag:ipxe,x86PC,"iPXE",http://matchbox.noverit.com:8080/boot.ipxe
    log-queries
    log-dhcp
    # In case, avoid to send default gateway in DHCP offers
    # dhcp-option=3
    # In case, avoid to send nameserver in DHCP offers
    # dhcp-option=6

Download the PXE boot files from [here]() and move to the proper TFTP boot location, eg. ``/var/lib/tftpboot``.

Start and enable the dnsmasq service

    systemctl start dnsmasq
    systemctl enable dnsmasq

Make sure the network addresses above match with your environment. Also make sure no firewall is blocking DHCP, DNS and TFTP traffic on the host network.

### Matchbox
We're going to setup the Matchbox service on the provisioner machine. Matchbox is a service for network booting and provisioning machines to create CoreOS Container Linux clusters.

Download the latest matchbox to the provisioner machine

     MATCHBOX=v0.7.0
     wget https://github.com/coreos/matchbox/releases/download/$MATCHBOX/matchbox-$MATCHBOX-linux-amd64.tar.gz

and install under the appropriate path

    tar xzvf matchbox-$MATCHBOX-linux-amd64.tar.gz
    cd matchbox-$MATCHBOX-linux-amd64
    cp matchbox /usr/local/bin

The matchbox service should be run by a non-root user with access to the matchbox ``/var/lib/matchbox`` data directory 

    useradd -U matchbox
    mkdir -p /var/lib/matchbox/assets
    chown -R matchbox:matchbox /var/lib/matchbox
    cp contrib/systemd/matchbox-local.service /etc/systemd/system/matchbox.service

Customize matchbox system file as following:

    [Unit]
    Description=CoreOS matchbox Server
    Documentation=https://github.com/coreos/matchbox

    [Service]
    User=matchbox
    Group=matchbox
    Environment="MATCHBOX_ADDRESS=0.0.0.0:8080"
    Environment="MATCHBOX_LOG_LEVEL=debug"
    Environment="MATCHBOX_RPC_ADDRESS=0.0.0.0:8081"
    ExecStart=/usr/local/bin/matchbox

    # systemd.exec
    ProtectHome=yes
    ProtectSystem=full

    [Install]
    WantedBy=multi-user.target

The Matchbox RPC APIs allow clients to create and update resources in Matchbox through a secure channel. TLS credentials are needed for client authentication. Please note, that PXE booting machines use the HTTP APIs and do not use credentials.

Create a self-signed Certification Authority and a keys pair

    cd ./scripts/tls
    export SAN=DNS.1:matchbox.noverit.com,IP.1:10.10.10.2
    ./cert-gen

The above will produce the following

    ls -l 
    -rw-r--r-- 1 root root 1814 Apr 11 09:51 ca.crt
    -rw-r--r-- 1 root root 1679 Apr 11 09:51 server.crt
    -rw-r--r-- 1 root root 1679 Apr 11 09:51 server.key
    -rw-r--r-- 1 root root 1578 Apr 11 09:52 client.crt
    -rw-r--r-- 1 root root 1679 Apr 11 09:52 client.key

Copy the server credentials to the matchbox default location

    mkdir -p /etc/matchbox
    cp ca.crt server.crt server.key /etc/matchbox

Copy the client credentials to the home location of the current user

    mkdir -p ~/.matchbox
    cp client.crt client.key ca.crt ~/.matchbox/

Start, enable, and verify the matchbox service

    systemctl daemon-reload 
    systemctl start matchbox
    systemctl enable matchbox
    systemctl status matchbox

Make sure the matchbox service is reachable by name

    nslookup matchbox.noverit.com

Verify the service can be reachable by clients

    curl http://matchbox.noverit.com:8080    
    openssl s_client -connect matchbox.noverit.com:8081 \
            -CAfile ~/.matchbox/ca.crt \
            -cert ~/.matchbox/client.crt \
            -key ~/.matchbox/client.key

Download the Container Linux OS stable image to the matchbox ``/var/lib/matchbox`` data directory

    COREOS=1688.5.3
    cd matchbox-$MATCHBOX-linux-amd64
    ./scripts/get-coreos stable $COREOS /var/lib/matchbox/assets
    
    tree /var/lib/matchbox/assets
    /var/lib/matchbox/assets
    `-- coreos
        `-- 1688.5.3
            |-- CoreOS_Image_Signing_Key.asc
            |-- coreos_production_image.bin.bz2
            |-- coreos_production_image.bin.bz2.sig
            |-- coreos_production_pxe_image.cpio.gz
            |-- coreos_production_pxe_image.cpio.gz.sig
            |-- coreos_production_pxe.vmlinuz
            |-- coreos_production_pxe.vmlinuz.sig
            `-- version.txt

and verify the images are accessible from clients

    curl http://matchbox.noverit.com:8080/assets/coreos/$COREOS/

### Tectonic installer
To use Tectonic installer, first create an account on the Tectonic web site and download the license ``tectonic-license.txt`` and secret ``config.json`` files. Move these files in a proper location, e.g. ``/root/tectonic/``.

Download and extract the Tectonic installer

    wget https://releases.tectonic.com/releases/tectonic_1.8.9-tectonic.2.zip
    unzip tectonic_1.8.9-tectonic.2.zip
    cd tectonic_1.8.9-tectonic.2

The Terraform version required to install Tectonic is included in the same installer tarball. Move the placeholder ``terraform.tfvars.metal`` variables file into a dedicated build directory

    export CLUSTER=mycluster
    mkdir -p build/${CLUSTER}
    cp examples/terraform.tfvars.metal build/${CLUSTER}/terraform.tfvars

and edit the following variables

    matchbox_http_url = "http://matchbox.noverit.com:8080"
    matchbox_rpc_endpoint = "matchbox.noverit.com:8081"
    container_linux_version = "1688.5.3"
    pull_secret_path = "/root/tectonic/config.json"
    license_path = "/root/tectonic/tectonic-license.txt"

    base_domain = "noverit.com"
    controller_domain = "master.noverit.com"
    ingress_domain = "tectonic.noverit.com"
    cluster_name = "mycluster"
    cluster_cidr = "10.38.0.0/16"
    service_cidr = "10.32.0.0/16"

    controller_domains = ["core00.noverit.com"]
    controller_macs = ["**:**:**:0f:76:4d"]
    controller_names = ["core00"]

    worker_domains = ["core01.noverit.com", "core02.noverit.com", "core03.noverit.com"]
    worker_macs = ["**:**:**:6C:48:56", "**:**:**:77:b9:89", "**:**:**:86:f3:e6"]
    worker_names = ["core01", "core02", "core03"]

    matchbox_ca = <paste content here>
    matchbox_client_cert = <paste content here>
    matchbox_client_key = <paste content here>

    tectonic_ssh_authorized_key = <paste content here>
    
    tectonic_ca_cert = <paste content here>
    tectonic_ca_key = <paste content here>
    tectonic_ca_key_alg = "RSA"
    
    vanilla_k8s = true

Some notes:

 1. Variable ``vanilla_k8s`` tells Tectonic to install only Kubernetes without the additional components provided by Tectonic management platform.
 2. Variables ``license_path`` and ``pull_secret_path`` are required only when installing Tectonic management platform, i.e. ``vanilla_k8s = false``. Not required for kubernetes vanilla installation.
 2. Variable ``tectonic_ssh_authorized_key`` must be set to the public key of the SSH keys pair the system will use to talk with nodes.
 3. Variables ``matchbox_ca``, ``matchbox_client_cert``, and ``matchbox_client_key`` must contain the keys of matchbox client.
 4. Variables ``tectonic_ca_cert``, ``tectonic_ca_key``, and ``tectonic_ca_key_alg`` need to be set only if you provide a custom Certificate Authority, otherwise Tectonic will generate a self-signed certificates at install time.

Make sure the variables above match your environment, including MAC addresses and domain names of controllers and workers.

### SSH keypair
Tectonic installer makes use of a ssh keypair to login into Container Linux nodes. The installer will ssh into the nodes using the private key of the ssh key you inserted in the variables file. Before starting the setup process, you need to add a ssh private key to your ssh agent running on the provisioner machine which is running the Tectonic installer. Without this step, the Tectonic installer will not be able to ssh copy the assets into nodes.

If you don't have any key you can generate one

    ssh-keygen -t rsa -b 4096 -C "admin@noverit.com"

Leave the private key ``~/.ssh/id_rsa`` into your ssh path and copy the public key ``~/.ssh/id_rsa.pub`` into the Tectonic installer variables file above.

## Deploying
When all the requirements above are met, let's start with deploy of the cluster. Login to the provisioner machine and move to the build environment

    export CLUSTER=mycluster
    cd tectonic_1.8.9-tectonic.2

Make sure the SSH agent is running and add the ssh private key be using in the installer

    eval $(ssh-agent -s)
    ssh-add ~/.ssh/id_rsa
    ssh-add -L

Also make sure that the ``~/.ssh/known_hosts`` file doesn't have old records of the nodes names because the fingerprints will not match.

Initialise Terraform

    export INSTALLER_PATH=$(pwd)/tectonic-installer/linux/installer
    export PATH=$(pwd)/tectonic-installer/linux:$PATH
    terraform init ./platforms/metal

Set the admin and password credentials

    export TF_VAR_tectonic_admin_email="admin@noverit.com"
    export TF_VAR_tectonic_admin_password="********"

Test the terraform plan before deploy

    terraform plan -var-file=build/${CLUSTER}/terraform.tfvars platforms/metal
    
Apply the plan

    terraform apply -var-file=build/${CLUSTER}/terraform.tfvars platforms/metal

Terraform starts and waits till the whole installation process terminates. If something goes wrong, clean the environment  by issuing the following command:

    terraform destroy -var-file=build/${CLUSTER}/terraform.tfvars platforms/metal

and start over.

Terraform writes the machine profiles and the matcher groups to the matchbox service data directory. Check the content of that folder

    tree /var/lib/matchbox
    /var/lib/matchbox
    |-- assets
    |   `-- coreos
    |       ...
    |-- groups
    |   |-- mycluster-core00.json
    |   |-- mycluster-core01.json
    |   |-- mycluster-core02.json
    |   |-- mycluster-core03.json
    |   |-- coreos-install-core00.json
    |   `-- coreos-install-core01.json
    |-- ignition
    |   |-- coreos-install.yaml.tmpl
    |   |-- tectonic-controller.yaml.tmpl
    |   `-- tectonic-worker.yaml.tmpl
    `-- profiles
        |-- coreos-install.json
        |-- tectonic-controller.json
        `-- tectonic-worker.json

Now, power on the machines: they will PXE boot, download the Container Linux OS from Matchbox, write it to disk, and reboot. During the whole process, Terraform waits for the disk installation and reboot to complete and then be able to copy credentials to the nodes to bootstrap the cluster.

Wait till the installation process terminates (it can take more than 30 minutes) and access the cluster from the provisioner machine through the ``kubectl`` command line (install it before).
   
    export KUBECONFIG=generated/auth/kubeconfig
    kubectl cluster-info
    
    Kubernetes master is running at https://master.noverit.com:443
    To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

Use common ``kubectl`` commands to interact with the Kubernetes cluster

    kubectl get nodes
    NAME                 STATUS    ROLES     AGE       VERSION
    core00.noverit.com   Ready     master    2m        v1.8.9+coreos.1
    core01.noverit.com   Ready     node      2m        v1.8.9+coreos.1
    core02.noverit.com   Ready     node      2m        v1.8.9+coreos.1
    core03.noverit.com   Ready     node      2m        v1.8.9+coreos.1

Finally, copy the ``kubeconfig`` file to your home dir

    mkdir ~/.kube
    cp ./generated/auth/kubeconfig ~/.kube/config

