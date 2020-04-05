# Ceph setup
In this section of the guide, we're going to setup a Ceph cluster to be used as for storage backend in Kubernetes. Our setup is made of three CentOS nodes:

   * ceph00 with IP 10.10.10.90
   * ceph01 with IP 10.10.10.91
   * ceph02 with IP 10.10.10.92

each of one exposing three row devices: ``/dev/sdb``, ``/dev/sdc`` and ``/dev/sdd`` of 16GB. So in total, we'll have 144GB of raw disk space.

All Ceph nodes are provided by a frontend network interface (public) used by Ceph clients to connect the storage cluster and a backend network interface (cluster) used by Ceph nodes for cluster formation and peering. 

## Install Ceph
These notes refer to Ceph version 10.2.10. As installation tool, we're going to use the ``ceph-deploy`` package. Use a separate admin machine where to install the ``ceph-deploy`` tool.

On the admin machine, enable the Ceph repository and install

    yum update 
    yum install ceph-deploy

On the ceph machines, enable the Ceph repository and install the requirements

    yum update
    yum install -y ntp openssh-server

On all machines, creae a dedicated ``cephdeploy`` user with sudo priviledges

    useradd cephdeploy
    passwd cephdeploy
    echo "cephdeploy ALL = (root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/cephdeploy
    sudo chmod 0440 /etc/sudoers.d/cephdeploy

and enable passwordless SSH to all ceph nodes. The ``ceph-deploy`` tool will not prompt for a password, so you must generate SSH keys on the admin node and distribute the public key to each Ceph node.

On the admin machine, login as ``cephdeploy`` user and generate the key

    ssh-keygen

and copy it to each Ceph node

for host in \
    ceph00 ceph01 ceph02; \
do ssh-copy-id -i ~/.ssh/id_rsa.pub $host; \
done

Modify the ``~/.ssh/config`` file of the admin node so that the ``ceph-deploy`` tool can log in to Ceph nodes without requiring to specify the username

    Host ceph00
       Hostname ceph00
       User cephdeploy
    Host ceph01
       Hostname ceph01
       User cephdeploy
    Host ceph02
       Hostname ceph02
       User cephdeploy

## Create the Ceph cluster
From the admin machine, login as ``cephdeploy`` user and install Ceph on the nodes

    ceph-deploy new ceph00 ceph01 ceph02

The tool should output a ``ceph.conf`` file in the current directory.

Edit the config file and add the public and cluster networks

    [global]
    fsid = 56520790-675b-4cb0-9d7b-f53ae0cc7b25
    mon_initial_members = ceph00, ceph01, ceph02
    mon_host = 10.10.10.90,10.10.10.91,10.10.10.92
    auth_cluster_required = cephx
    auth_service_required = cephx
    auth_client_required = cephx
    public network = 10.10.10.0/24
    cluster network = 192.168.2.0/24

Now, install the Ceph packages

    ceph-deploy install ceph00 ceph01 ceph02

Deploy the initial monitors and gather the keys

    ceph-deploy mon create-initial

Check the output of the tool in the current directory

    ls -lrt
    total 288
    -rw------- 1 cephdeploy cephdeploy     73 Mar 26 17:01 ceph.mon.keyring
    -rw-rw-r-- 1 cephdeploy cephdeploy    298 Mar 26 17:05 ceph.conf
    -rw------- 1 cephdeploy cephdeploy    129 Mar 26 17:10 ceph.client.admin.keyring
    -rw------- 1 cephdeploy cephdeploy    113 Mar 26 17:10 ceph.bootstrap-mds.keyring
    -rw------- 1 cephdeploy cephdeploy    113 Mar 26 17:10 ceph.bootstrap-osd.keyring
    -rw------- 1 cephdeploy cephdeploy    113 Mar 26 17:10 ceph.bootstrap-rgw.keyring
    -rw-rw-r-- 1 cephdeploy cephdeploy 269548 Mar 26 17:39 ceph-deploy-ceph.log

Copy the configuration file and the admin key to your admin node and your Ceph nodes so that you can use the ceph CLI without having to specify the monitor address and the key

    ceph-deploy admin ceph00 ceph01 ceph02

Add the OSDs daemons on all the Ceph nodes

    ceph-deploy osd create ceph00:/dev/sdb ceph00:/dev/sdc ceph00:/dev/sdd
    ceph-deploy osd create ceph01:/dev/sdb ceph01:/dev/sdc ceph01:/dev/sdd
    ceph-deploy osd create ceph02:/dev/sdb ceph02:/dev/sdc ceph02:/dev/sdd

Login to one of the ceph node and check the cluster’s health

    ceph health

Your cluster should report ``HEALTH_OK``.

View a more complete cluster status with

    ceph -s

If at any point you run into trouble and you want to start over, purge the Ceph packages, erase all its data and all configuration.

From the admin node, as ``cephdeploy`` user

    ceph-deploy purge ceph00 ceph01 ceph02
    ceph-deploy purgedata ceph00 ceph01 ceph02
    ceph-deploy forgetkeys
    rm ./ceph.*
    
and start over if the case.

## Configure Ceph for dynamic volumes
It is recommended that you create a pool for your dynamic volumes to live in. Using the default pool of Ceph is an option, but, in general, is not recommended.

Login to a monitor or admin Ceph node and create a new pool for dynamic volumes

    ceph osd pool create kube 1024
    ceph auth get-or-create client.kube \
         mon 'allow r' \
         osd 'allow class-read object_prefix rbd_children, allow rwx pool=kube' \
         -o ceph.client.kube.keyring
     
Check the status of the cluster

    ceph -s

and make sure the cluster is in health state and adjust the number of placement groups if the case.

Now create the base64 admin and client keys

    ceph auth get-key client.admin | base64
    QVFCUERibGFwSUVzTGhBQXFCV3RvSVBKdUFTUkEvK1pYSjJjSkE9PQ==

    ceph auth get-key client.kube | base64
    QVFBeUdibGFmWlFyT0JBQTlIaVAvdWcxKytHV21WNENBS1d4TXc9PQ==

Save the keys above. We'll use them to configure Kubernetes to access the Ceph ``kube`` storage pool we just created above.

## Configure Kubernetes for dynamic provisioning
Kubernetes worker nodes are clients of the Ceph storage. They act as rbd clients by mounting the volumes on demand when the pods startup.

### Prepare the worker nodes
Prepare the setup by installing the ``ceph-common`` library on all schedulable worker nodes

    yum install -y ceph-common

### Configure the Ceph Provisioner
For dynamic storage provisioning, kubernetes uses provisioners that determine what volume plugin is used to provision storage. In our case, we're going to use an external Rados Block Device provisioner running in the ``kube-system`` namespace. The provisioner is defined as deployment in the ``rbd-provisioner.yaml`` configuration file

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: rbd-provisioner
  namespace: kube-system
spec:
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: rbd-provisioner
    spec:
      containers:
      - name: rbd-provisioner
        image: "quay.io/external_storage/rbd-provisioner:latest"
        env:
        - name: PROVISIONER_NAME
          value: ceph.com/rbd
      serviceAccount: rbd-provisioner
```

Because of the RBAC access control, we have to define a dedicate Service Account and give it permissions in the ``kube-system`` namespace.

Define the Service Account as in the ``rbd-sa.yaml`` configuration file

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: kube-system
  name: rbd-provisioner
```

Define the cluster role as in the ``rbd-cluster-role.yaml`` configuration file

```yaml
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-provisioner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services"]
    resourceNames: ["kube-dns"]
    verbs: ["list", "get"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
```

and define the binding between the cluster role and the service account as in the ``rbd-cluster-role-binding.yaml`` configuration file

```yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rbd-provisioner
subjects:
  - kind: ServiceAccount
    name: rbd-provisioner
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: rbd-provisioner
  apiGroup: rbac.authorization.k8s.io
```

Working as cluster admin in the ``kube-system`` namespace, create all the above

    kubectl create -f rbd-sa.yaml
    kubectl create -f rbd-cluster-role.yaml
    kubectl create -f rbd-cluster-role-binding.yaml
    kubectl create -f rbd-provisioner.yaml

and make sure the provisioner is up and running

    kubectl get pods -o wide -n kube-system -l app=rbd-provisioner
    NAME                               READY     STATUS    RESTARTS   AGE       IP            NODE
    rbd-provisioner-77d75fdc5b-wnjzk   1/1       Running   0          1m        10.38.4.194   kubew04

### Create a Storage Class
From the Ceph admin and client keys above, define the Ceph admin secret as in the ``rbd-secret-admin.yaml`` configuration file 
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rbd-secret-admin
  namespace: kube-system
data:
  key: QVFCUERibGFwSUVzTGhBQXFCV3RvSVBKdUFTUkEvK1pYSjJjSkE9PQ== 
type:
  kubernetes.io/rbd 
```
Make sure it is in the ``kube-system`` namespace.

Define the Ceph client secret as in the ``rbd-secret-kube.yaml`` configuration file 
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rbd-secret-kube
  namespace:
data:
  key: QVFBeUdibGFmWlFyT0JBQTlIaVAvdWcxKytHV21WNENBS1d4TXc9PQ==
type:
  kubernetes.io/rbd 
```

Make sure it is in the client namespace.

As cluster admin, create the admin and the client secrets

    kubectl create -f rbd-secret-admin.yaml
    kubectl create -f rbd-secret-kube.yaml

If you want to make the Ceph storage available to another namespace, create an additional secret for each namespace.

Now we can define one or more Storage Classes for dynamic provisioning with Ceph. As for example, the ``rbd-storage-class.yaml`` configuration file
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rbd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: ceph.com/rbd
reclaimPolicy: Delete
parameters:
  monitors: ceph00:6789,ceph01:6789.ceph02:6789
  adminId: admin
  adminSecretName: rbd-secret-admin
  adminSecretNamespace: kube-system
  pool: kube
  userId: kube
  userSecretName: rbd-secret-kube
  imageFormat: "1"
```

Create the storage class

    kubectl create -f rbd-storage-class.yaml

If you want to make this a default storage class, change the annotation in the file above to be ``true``.


### Use Ceph dynamic provisioning
Having configured the Ceph storage and Kubernetes cluster, we can use the Ceph as storage backend for our applications. As standard user, create a Persistent Volume Claim as in the following ``rbd-volume-claim.yaml`` configuration file
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: rbd-claim
spec:
  storageClassName: "rbd"
  accessModes:     
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi 
```

Please, note the ``accessModes`` parameter do not enforce access right or mounting options, but rather it acts as labels to match when creating the Persistent Volume. Also the storage request of 10GB will create a Persistent Volume matching of 10GB on the assigned Ceph storage pool.

Create the claim

    kubectl create -f rbd-volume-claim.yaml

that dynamically creates a new Persistent Volume with the requested capacity.

Check the claims and the volumes

    kubectl get pvc
    NAME        STATUS    VOLUME                             CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    rbd-claim   Bound     pvc-490dedbc-31d1-11e8-abf3-000e   10Gi       RWO            rbd            1m

Once the Ceph volume is created, it is possible to mount it by creating a pod referring the Persistent Volume Claim. For example, create a pod as in the following ``nginx-on-rbd.yaml`` configuration file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-on-rbd
  namespace:
  labels:
    run: nginx
spec:
  restartPolicy: Always
  containers:
  - name: nginx
    image: docker.io/nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - mountPath: "/usr/share/nginx/html"
      name: html
  volumes:
  - name: html
    persistentVolumeClaim:
      claimName: rbd-claim
```

Create the pod and wait it is running

    kubectl create -f nginx-on-rbd.yaml

    kubectl get pods -o wide -l run=nginx
    NAME           READY     STATUS    RESTARTS   AGE       IP            NODE
    nginx-on-rbd   1/1       Running   0          2m        10.38.3.106   kubew03

Check the block devices mounted by the pod

    kubectl exec nginx-on-rbd -- lsblk
    NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    fd0      2:0    1    4K  0 disk
    sr0     11:0    1 1024M  0 rom  
    sda      8:0    0   16G  0 disk 
    |-sda1   8:1    0    1G  0 part 
    `-sda2   8:2    0   15G  0 part 
    rbd0   252:0    0   10G  0 disk /usr/share/nginx/html

Note as the Ceph RBD disk is mounted as ``rbd0`` under the expected path.
