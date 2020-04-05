# Persistent Storage Model
Containers are ephemeral, meaning the container file system only lives as long as the container does. Volumes are simplest way to achieve data persistance. In kubernetes, a more flexible and powerful model is available.

This model is based on the following abstractions:

  * **PersistentVolume**: it models shared storage that has been provisioned by the cluster administrator. It is a resource in the cluster just like a node is a cluster resource. Persistent volumes are like standard volumes, but having a lifecycle independent of any individual pod. Also they hide to the users the details of the implementation of the storage, e.g. NFS, iSCSI, or other cloud storage systems.

  * **PersistentVolumeClaim**: it is a request for storage by a user. It is similar to a pod. Pods consume node resources and persistent volume claims consume persistent volume objects. As pods can request specific levels of resources like cpu and memory, volume claimes claims can request the access modes like read-write or read-only and stoarage capacity.

Kubernetes provides two different ways to provisioning storage:

  * **Manual Provisioning**: the cluster administrator has to manually make calls to the storage infrastructure to create persisten volumes and then users need to create volume claims to consume storage volumes.
  * **Dynamic Provisioning**: storage volumes are automatically created on-demand when users claim for storage avoiding the cluster administrator to pre-provision storage. 

In this section we're going to introduce this model by using simple examples. Please, refer to official documentation for more details.

  * [Local Persistent Volumes](#local-persistent-volumes)
  * [Volume Access Mode](#volume-access-mode)
  * [Volume State](#volume-state)
  * [Volume Reclaim Policy](#volume-reclaim-policy)
  * [Manual volumes provisioning](#manual-volumes-provisioning)
  * [Storage Classes](#storage-classes)
  * [Dynamic volumes provisioning](#dynamic-volumes-provisioning)
  * [Redis benchmark](#redis-benchmark)
  * [Stateful Applications](./stateful.md)
  * [Configure GlusterFS as Storage backend](./glusterfs.md)
  * [Configure Ceph as Storage backend](./ceph.md)

## Local Persistent Volumes
Start by defining a persistent volume ``local-persistent-volume-recycle.yaml`` configuration file

```yaml
kind: PersistentVolume
apiVersion: v1
metadata:
  name: local
  labels:
    type: local
spec:
  storageClassName: ""
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data"
  persistentVolumeReclaimPolicy: Recycle
```

The configuration file specifies that the volume is at ``/data`` on the the cluster’s node. The volume type is ``hostPath`` meaning the volume is local to the host node. The configuration also specifies a size of 2GB and the access mode of ``ReadWriteOnce``, meanings the volume can be mounted as read write by a single pod at time. The reclaim policy is ``Recycle`` meaning the volume can be used many times.  It defines the Storage Class name manual for the persisten volume, which will be used to bind a claim to this volume.

Create the persistent volume

    kubectl create -f local-persistent-volume-recycle.yaml
    
and view information about it 

    kubectl get pv
    NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     STORAGECLASS   REASON    AGE
    local     2Gi        RWO           Recycle         Available                                      33m

Now, we're going to use the volume above by creating a claiming for persistent storage. Create the following ``volume-claim.yaml`` configuration file
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: volume-claim
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Note the claim is for 1GB of space where the the volume is 2GB. The claim will bound any volume meeting the minimum requirements specified into the claim definition. 

Create the claim

    kubectl create -f volume-claim.yaml

Check the status of persistent volume to see if it is bound

    kubectl get pv
    NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS    CLAIM                  STORAGECLASS   REASON    AGE
    local     2Gi        RWO           Recycle         Bound     project/volume-claim                            37m

Check the status of the claim

    kubectl get pvc
    NAME           STATUS    VOLUME    CAPACITY   ACCESSMODES   STORAGECLASS   AGE
    volume-claim   Bound     local     2Gi        RWO                          1m

Create a ``nginx-pod-pvc.yaml`` configuration file for a nginx pod using the above claim for its html content directory
```yaml
---
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  namespace: default
  labels:
spec:

  containers:
    - name: nginx
      image: nginx:latest
      ports:
        - containerPort: 80
          name: "http-server"
      volumeMounts:
      - mountPath: "/usr/share/nginx/html"
        name: html

  volumes:
    - name: html
      persistentVolumeClaim:
       claimName: volume-claim
```

Note that the pod configuration file specifies a persistent volume claim, but it does not specify a persistent volume. From the pod point of view, the claim is the volume. Please note that a claim must exist in the same namespace as the pod using the claim.

Create the nginx pod

    kubectl create -f nginx-pod-pvc.yaml

Accessing the nginx will return *403 Forbidden* since there are no html files to serve in the data volume

    kubectl get pod nginx -o yaml | grep IP
      hostIP: 10.10.10.86
      podIP: 172.30.5.2

    curl 172.30.5.2:80
    403 Forbidden

Let's login to the worker node and populate the data volume

    echo "Welcome to $(hostname)" > /data/index.html

Now try again to access the nginx application

     curl 172.30.5.2:80
     Welcome to kubew05

To test the persistence of the volume and related claim, delete the pod and recreate it

    kubectl delete pod nginx
    pod "nginx" deleted

    kubectl create -f nginx-pod-pvc.yaml
    pod "nginx" created

Locate the IP of the new nginx pod and try to access it

    kubectl get pod nginx -o yaml | grep podIP
      podIP: 172.30.5.2

    curl 172.30.5.2
    Welcome to kubew05

## Volume Access Mode
A persistent volume can be mounted on a host in any way supported by the resource provider. Different storage providers have different capabilities and access modes are set to the specific modes supported by that particular volume. For example, NFS can support multiple read write clients, but an iSCSI volume can be support only one.

The access modes are:

  * **ReadWriteOnce**: the volume can be mounted as read-write by a single node
  * **ReadOnlyMany**: the volume can be mounted read-only by many nodes
  * **ReadWriteMany**: the volume can be mounted as read-write by many nodes

Claims and volumes use the same conventions when requesting storage with specific access modes. Pods use claims as volumes. For volumes which support multiple access modes, the user specifies which mode desired when using their claim as a volume in a pod.

A volume can only be mounted using one access mode at a time, even if it supports many. For example, a NFS volume can be mounted as ReadWriteOnce by a single node or ReadOnlyMany by many nodes, but not at the same time.

Block based volumes, e.g. iSCSI and Fibre Channel cannot be mounted as ReadWriteMany at same type. The iSCSI and Fibre Channel volumes do not have any fencing mechanisms yet, so you must ensure the volumes are only used by one node at a time. In certain situations, such as draining a node, the volumes may be used simultaneously by two nodes. Before draining the node, first ensure the pods that use these volumes are deleted.

## Volume state
When a pod claims for a volume, the cluster inspects the claim to find the volume meeting claim requirements and mounts that volume for the pod. Once a pod has a claim and that claim is bound, the bound volume belongs to the pod.

A volume will be in one of the following state:

  * **Available**: a volume that is not yet bound to a claim
  * **Bound**: the volume is bound to a claim
  * **Released**: the claim has been deleted, but the volume is not yet available
  * **Failed**: the volume has failed 

The volume is considered released when the claim is deleted, but it is not yet available for another claim. Once the volume becomes available again then it can bound to another other claim. 

In our example, delete the volume claim

    kubectl delete pvc volume-claim

See the status of the volume

    kubectl get pv persistent-volume
    NAME      CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     STORAGECLASS   REASON    AGE
    local     2Gi        RWO           Recycle         Available                                      57m

## Volume Reclaim Policy
When deleting a claim, the volume becomes available to other claims only when the volume claim policy is set to ``Recycle``. Volume claim policies currently supported are:

  * **Retain**: the content of the volume still exists when the volume is unbound and the volume is released
  * **Recycle**: the content of the volume is deleted when the volume is unbound and the volume is available
  * **Delete**: the content and the volume are deleted when the volume is unbound. 
  
*Please note that, currently, only NFS and HostPath support recycling.* 

When the policy is set to ``Retain`` the volume is released but it is not yet available for another claim because the previous claimant’s data are still on the volume.

Define a persistent volume ``local-persistent-volume-retain.yaml`` configuration file

```yaml
kind: PersistentVolume
apiVersion: v1
metadata:
  name: local-retain
  labels:
    type: local
spec:
  storageClassName: ""
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/data"
  persistentVolumeReclaimPolicy: Retain
```

Create the persistent volume and the claim

    kubectl create -f local-persistent-volume-retain.yaml
    kubectl create -f volume-claim.yaml

Login to the pod using the claim and create some data on the volume

    kubectl exec -it nginx bash
    root@nginx:/# echo "Hello World" > /usr/share/nginx/html/index.html
    root@nginx:/# exit

Delete the claim

    kubectl delete pvc volume-claim

and check the status of the volume

    kubectl get pv
    NAME           CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS     CLAIM                  STORAGECLASS     AGE
    local-retain   2Gi        RWO           Retain          Released   project/volume-claim                    3m
    
We see the volume remain in the released status and not becomes available since the reclaim policy is set to ``Retain``. Now login to the worker node and check data are still there.

An administrator can manually reclaim the volume by deleteting the volume and creating a another one.

## Manual volumes provisioning
In this section we're going to use a **Network File System** storage backend for manual provisioning of shared volumes. Main limit of local storage for container volumes is that storage area is tied to the host where it resides. If kubernetes moves the pod from another host, the moved pod is no more to access the data since local storage is not shared between multiple hosts of the cluster. To achieve a more useful storage backend we need to leverage on a shared storage technology like NFS.

We'll assume a simple external NFS server ``fileserver`` sharing some folders. To make worker nodes able to consume these NFS shares, install the NFS client on all the worker nodes by ``yum install -y nfs-utils`` command.

Define a persistent volume as in the ``nfs-persistent-volume.yaml`` configuration file
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-volume
spec:
  storageClassName: ""
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  nfs:
    path: "/mnt/nfs"
    server: fileserver
  persistentVolumeReclaimPolicy: Recycle
```

Create the persistent volume

    kubectl create -f nfs-persistent-volume.yaml
    persistentvolume "nfs" created

    kubectl get pv nfs -o wide
    NAME        CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS      CLAIM     STORAGECLASS   REASON    AGE
    nfs-volume  1Gi        RWO           Recycle         Available                                      7s

Thanks to the persistent volume model, kubernetes hides the nature of storage and its complex setup to the applications. An user need only to claim volumes for their pods without deal with storage configuration and operations.

Create the claim

    kubectl create -f volume-claim.yaml

Check the bound 

    kubectl get pv
    NAME        CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS    CLAIM                  STORAGECLASS   REASON    AGE
    nfs-volume  1Gi        RWO           Recycle         Bound     project/volume-claim                            5m

    kubectl get pvc
    NAME           STATUS    VOLUME      CAPACITY   ACCESSMODES   STORAGECLASS   AGE
    volume-claim   Bound     nfs-volume  1Gi        RWO                          9s

Now we are going to create more nginx pods using the same claim.

For example, create the ``nginx-pvc-template.yaml`` template for a nginx application having the html content folder placed on the shared storage 
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: nginx
  name: nginx-pvc
spec:
  replicas: 3
  selector:
    matchLabels:
      run: nginx
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: nginx
    spec:
      containers:
      - image: nginx:latest
        imagePullPolicy: IfNotPresent
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
          name: "http-server"
        volumeMounts:
        - mountPath: "/usr/share/nginx/html"
          name: html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: volume-claim
      dnsPolicy: ClusterFirst
      restartPolicy: Always
```

The template above defines a nginx application based on a nginx deploy of 3 replicas. The nginx application requires a shared volume for its html content. The application does not have to deal with complexity of setup and admin an NFS share.

Deploy the application

    kubectl create -f nginx-pvc-template.yaml
    
Check all pods are up and running

    kubectl get pods -o wide
    NAME                         READY     STATUS    RESTARTS   AGE       IP            NODE
    nginx-pvc-3474572923-3cxnf   1/1       Running   0          2m        10.38.5.89    kubew05
    nginx-pvc-3474572923-6cr28   1/1       Running   0          6s        10.38.3.140   kubew03
    nginx-pvc-3474572923-z17ls   1/1       Running   0          2m        10.38.5.90    kubew05

Login to one of these pods and create some html content

    kubectl exec -it nginx-pvc-3474572923-3cxnf bash
    root@nginx-pvc-3474572923-3cxnf:/# echo 'Hello from NFS!' > /usr/share/nginx/html/index.html                
    root@nginx-pvc-3474572923-3cxnf:/# exit

Since all three pods mount the same shared folder on the NFS, the just created html content is placed on the NFS share and it is accessible from any of the three pods

    curl 10.38.5.89    
    Hello from NFS!
    
    curl 10.38.5.90
    Hello from NFS!
    
    curl 10.38.3.140
    Hello from NFS!

### Volume selectors
A volume claim can define a label selector to bound a specific volume. For example, define a claim as in the ``pvc-volume-selector.yaml`` configuration file
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-volume-selector
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  selector:
    matchLabels:
      volumeName: "share01"
```

Create the claim

	kubectl create -f pvc-volume-selector.yaml

The claim remains pending because there are no matching volumes

	kubectl get pvc
	NAME                  STATUS    VOLUME    CAPACITY   ACCESS MODES   STORAGECLASS   AGE
	pvc-volume-selector   Pending                                                      5s
	
	kubectl get pv
	NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM     
	share01   1Gi        RWX            Recycle          Available             
	share02   1Gi        RWX            Recycle          Available             

Pick the volume named ``share01`` and label it

	kubectl label pv share00 volumeName="share01"
	persistentvolume "share01" labeled
	
And check if the claim bound the volume

	kubectl get pv
	NAME      CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                         
	share01   1Gi        RWX            Recycle          Bound       project/pvc-volume-selector     
	share02   1Gi        RWX            Recycle          Available                                 

## Storage Classes
A Persistent Volume uses a given storage class specified into its definition file. A claim can request a particular class by specifying the name of a storage class in its definition file. Only volumes of the requested class can be bound to the claim requesting that class.

If the storage class is not specified in the persistent volume definition, the volume has no class and can only be bound to claims that do not require any class. 

Multiple storage classes can be defined specifying the volume provisioner to use when creating a volume of that class. This allows the cluster administrator to define multiple type of storage within a cluster, each with a custom set of parameters.

For example, the following ``gluster-storage-class.yaml`` configuration file defines a storage class for a GlusterFS backend
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: glusterfs
  labels:
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Delete
parameters:
  resturl: "http://heketi:8080"
  volumetype: "replicate:3"
```

Create the storage class

    kubectl create -f gluster-storage-class.yaml
    kubectl get sc
    NAME                              PROVISIONER
    glusterfs-storage-class           kubernetes.io/glusterfs


The cluster administrator can define a class as default storage class by setting an annotation in the class definition file
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: default-storage-class
  labels:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Delete
parameters:
  resturl: "http://heketi:8080"
```

Check the storage classes

    kubectl get sc
    NAME                              PROVISIONER
    default-storage-class (default)   kubernetes.io/glusterfs
    glusterfs-storage-class           kubernetes.io/glusterfs

If the cluster administrator defines a default storage class, all claims that do not require any class will be dynamically bound to volumes having the default storage class. 

## Dynamic volumes provisioning
In this section we're going to use a **GlusterFS** distributed storage backend for dynamic provisioning of shared volumes. We'll assume an external GlusterFS cluster made of three nodes providing a distributed and high available file system.

### Dynamically Provision a GlusterFS volume
Define a storage class for the gluster provisioner
```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: glusterfs-storage-class
  labels:
provisioner: kubernetes.io/glusterfs
reclaimPolicy: Delete
parameters:
  resturl: "http://heketi:8080"
  volumetype: "replicate:3"
```

Make sure the ``resturl`` parameter is reporting the Heketi server and port.

Create the storage class

	kubectl create -f gluster-storage-class.yaml

To make the kubernetes worker nodes able to consume GlusterFS volumes, install the gluster client on all worker nodes

	yum install -y glusterfs-fuse

Define a volume claim in the gluster storage class

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: apache-volume-claim
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 500Mi
  storageClassName: glusterfs-storage-class
```

and an apache pod that is using that volume claim for its static html repository

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: apache-gluster-pod
  labels:
    name: apache-gluster-pod
spec:
  containers:
  - name: apache-gluster-pod
    image: centos/httpd:latest
    ports:
    - name: web
      containerPort: 80
      protocol: TCP
    volumeMounts:
    - mountPath: "/var/www/html"
      name: html
  volumes:
  - name: html
    persistentVolumeClaim:
      claimName: apache-volume-claim
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```

Create the storage class, the volume claim and the apache pod

	kubectl create -f glusterfs-storage-class.yaml
	kubectl create -f pvc-gluster.yaml
	kubectl create -f apache-pod-pvc.yaml

Check the volume claim

	kubectl get pvc
	NAME                  STATUS    VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS              AGE
	apache-volume-claim   Bound     pvc-4af76e0f   1Gi        RWX            glusterfs-storage-class   7m

The volume claim is bound to a dynamically created volume on the gluster storage backend

	kubectl get pv
	NAME           CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS    CLAIM                 STORAGECLASS
	pvc-4af76e0f   1Gi        RWX            Delete           Bound     apache-volume-claim   glusterfs-storage-class

Cross check through the Heketi

 	heketi-cli --server http://heketi:8080 volume list
	Id:7ce4d0cbc77fe36b84ca26a5e4172dbe Name:vol_7ce4d0cbc77fe36b84ca26a5e4172dbe ...

In the same way, the gluster volume is dynamically removed when the claim is removed

	kubectl delete pvc apache-volume-claim
	kubectl get pvc,pv
	No resources found.

## Redis benchmark
In this section, we are going to use persistent storage as a backend for a Redis server. Redis is an open source, in-memory data structure store, used as a database, cache and message broker. Redis provides different levels of on-disk persistence. Redis is famous for its performances and, therefore, we are going to run a Redis benchmark having persistence on a persistence volume.

### Create a persistent volume claim
Make sure a default Storage Class is defined and create a claim for data as in the ``redis-data-claim.yaml`` configuration file
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: redis-data-claim
spec:
  storageClassName: default
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Create the claim and check the dynamic volume creation and the binding

	kubectl create -f redis-data-claim.yaml
	
	kubectl get pvc
	NAME                     STATUS    VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS        AGE
	redis-data-claim         Bound     pvc-eaab62e3   10Gi       RWO            default             1m

### Create a Redis Master
Define a Redis Master deployment as in the ``redis-deployment.yaml`` configuration file
```yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: redis-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        name: redis
        role: master
      name: redis
    spec:
      containers:
        - name: redis
          image: kubernetes/redis:v1
          env:
            - name: MASTER
              value: "true"
          ports:
            - containerPort: 6379
          volumeMounts:
            - mountPath: /redis-master-data
              name: redis-data
      volumes:
        - name: redis-data
          persistentVolumeClaim:
            claimName: redis-data-claim
```

Define a Redis service as in the ``redis-service.yaml`` configuration file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
    nodePort: 31079
    name: http
  type: NodePort
  selector:
    name: redis
```

Deploy the Redis Master and create the service

	kubectl create -f redis-deployment.yaml
	kubectl create -f redis-service.yaml

Wait the Redis pod is ready

	kubectl get pods -a -o wide
	NAME                                READY     STATUS      RESTARTS   AGE       IP             NODE
	redis-deployment-75466795f6-thtx4   1/1       Running     0          30s       10.38.5.62     kubew05

To verify Redis, install the ``netcat`` utility and connect to the Redis Master

	yum install -y nmap-ncat

	nc -v kubew05 31079
	Ncat: Version 6.40 
	Ncat: Connected to kubew05:31079.
	ping
	+PONG
	set greetings "Hello from Redis!"
	+OK
	get greetings
	$17
	Hello from Redis!
	logout

### Run benchmark
Define a job running the Redis performances benchmark as in the ``redis-benchmark.yaml`` configuration file
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: redis-bench
spec:
  template:
    metadata:
      name: bench
    spec:
      containers:
      - name: bench
        image: clue/redis-benchmark
      restartPolicy: Never
```

Create a batch job to run the benchmark

	kubectl create -f redis-benchmark.yaml

Wait the job completes

	kubectl get job
	NAME          DESIRED   SUCCESSFUL   AGE
	redis-bench   1         1            48s

Check the bench pod name and display the results

	kubectl get pods -a
	NAME                                        READY     STATUS      RESTARTS   AGE
	redis-bench-jgbj8                           0/1       Completed   0          1m
	redis-deployment-75466795f6-thtx4           1/1       Running     0          16m

	kubectl logs redis-bench-jgbj8
