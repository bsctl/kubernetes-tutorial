# Cluster Healing
In this section we are going to deal with some advanced cluster admin tasks.

   * [Cluster Backup and Restore](#cluster-backup-and-restore)
   * [Control Plane Failure](#control-plane-failure)
   * [Worker Failure](#worker-failure)

To show the impact of the cluster on user applications, start a simple nginx deploy of three pods and the related service

    kubectl create -f nginx-deploy.yaml
    kubectl create -f nginx-svc.yaml

    kubectl get all

    NAME                        READY     STATUS    RESTARTS   AGE
    po/nginx-1423793266-bfpg6   1/1       Running   0          13m
    po/nginx-1423793266-qfgvb   1/1       Running   0          13m
    po/nginx-1423793266-vhzq7   1/1       Running   1          2h

    NAME             CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
    svc/kubernetes   10.32.0.1      <none>        443/TCP          1d
    svc/nginx        10.32.163.25   <nodes>       8000:31000/TCP   2h

    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   3         3         3            3           2h

    NAME                  DESIRED   CURRENT   READY     AGE
    rs/nginx-1423793266   3         3         3         2h


## Cluster Backup and Restore
The state of the cluster is stored in the etcd db, usually running on the master node along with the API Server and other components of the control plane. To avoid single point of failure, it is recommended to use an odd number of etcd nodes.

For now, let's take a backup of the cluster data. To interact with etcd, we're going to use the ``etcdctl`` admin tool. The etcd db supports both v2 and v3 APIs.

For v2 APIs:

    etcdctl --endpoints=http://10.10.10.80:2379 member list

    89f7d3a76f81eee3: name=kubem00
    peerURLs=http://10.10.10.80:2380
    clientURLs=http://10.10.10.80:2379
    isLeader=true

For v3 APIs, set first the env variable

    export ETCDCTL_API=3
    etcdctl --endpoints=http://10.10.10.80:2379 member list
    
    89f7d3a76f81eee3, started, kubem00, http://10.10.10.80:2380, http://10.10.10.80:2379


Our kubernetes cluster is using, by default, the v3 APIs.

First, take a snapshot of the current cluster state

    etcdctl --endpoints=http://10.10.10.80:2379 snapshot save etcd-backup.db

The sanpshot is taken as backup ``etcd-backup.db`` file on the local disk.

    etcdctl --endpoints=http://10.10.10.80:2379 snapshot status etcd-backup.db
    be27a17b, 184596, 613, 3.3 MB

Now make some changes to the cluster, for example by deleting the nginx deploy

    kubectl delete deploy nginx
    
so, no more pods running on the cluster

    kubectl get pods
    No resources found.

To restore the previous cluster state from the backup file, stop the etcd service, remove the current db content and restore from the backup

    systemctl stop etcd
    rm -rf /var/lib/etcd

    etcdctl --endpoints=http://10.10.10.80:2379 snapshot restore etcd-backup.db \
            --data-dir="/var/lib/etcd"  \
            --initial-advertise-peer-urls="http://10.10.10.80:2380" \
            --initial-cluster="kubem00=http://10.10.10.80:2380" \
            --initial-cluster-token="etcd-cluster-token"  \
            --name="kubem00"

Note that to restore data, we also need to specify all the parameters of the etcd service.

Now start the etcd service and restart also the kubernetes service to reconcilie the previous state

    systemctl start etcd
    systemctl restart kube-apiserver kube-controller-manager kube-scheduler
    
Check if everything is restored

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-1423793266-0fh6d   1/1       Running   0          19m
    nginx-1423793266-4lxgp   1/1       Running   0          19m
    nginx-1423793266-q2nnw   1/1       Running   0          19m

### TLS security
In case etcd is installed with TLS (as it should be), the `etcdctl` client needs to be authenticated by the `etcd` server

    source /etc/etcd/etcd.conf 
    etcdctl --cert=$ETCD_PEER_CERT_FILE --key=$ETCD_PEER_KEY_FILE --cacert=$ETCD_TRUSTED_CA_FILE --endpoints=$ETCD_LISTEN_CLIENT_URLS member list
    11e83f60ba359a88, started, master01, https://10.10.10.80:2380, https://10.10.10.80:2379
    64d9750a0e53fb8e, started, master00, https://10.10.10.81:2380, https://10.10.10.81:2379
    c15a42797f6144f0, started, master02, https://10.10.10.82:2380, https://10.10.10.82:2379

## Control Plane Failure
In this section we are going to analyze the effects of a control plane failure, i.e. the master and its components.

### APIs Server failure
An APIs server failure breaks the cluster control plane preventings users and administrators to interact with it. For this reason, production envinronments should leverage on an high availability control plane.

However, a failure in the control plane does not prevents user applications to work. To check this, login to the master node and stop the APIs server

    systemctl stop kube-apiserver

Now it no more possible to access any resource in the cluster

    kubectl get all
    The connection to the server was refused - did you specify the right host or port?

However, our nginx pods are still serving

    curl http://kubew03:31000
    Welcome to nginx!

Restart the APIs server

    systemctl start kube-apiserver


### Scheduler failure
A Scheduler failure prevents the users to schedule new pods to the cluster. However already running pods are still serving. To check this, login to the master node and stop the scheduler

    systemctl stop kube-scheduler

Now try to scale up the nginx deploy

    kubectl scale deploy nginx --replicas=6
    deployment "nginx" scaled

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-1423793266-0fh6d   1/1       Running   0          33m
    nginx-1423793266-4lxgp   1/1       Running   0          33m    
    nginx-1423793266-q2nnw   1/1       Running   0          33m
    nginx-1423793266-wjmjs   0/1       Pending   0          9s
    nginx-1423793266-14x09   0/1       Pending   0          9s
    nginx-1423793266-fbrvg   0/1       Pending   0          9s
    
We see new pods stucking in pending state since the scheduler is not available.

Restore the scheduler service and check the status of the pods

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-1423793266-0fh6d   1/1       Running   0          35m
    nginx-1423793266-14x09   1/1       Running   0          2m
    nginx-1423793266-4lxgp   1/1       Running   0          35m
    nginx-1423793266-fbrvg   1/1       Running   0          2m
    nginx-1423793266-q2nnw   1/1       Running   0          35m
    nginx-1423793266-wjmjs   1/1       Running   0          2m


### Controller Manager failure
Primary task of the control manager is to reconcile the actual state of the system with the desired state. A failure of the controller prevents the cluster to update the actual state with changes requested by the users.

Login to the master node and stop the controller manager service

    systemctl stop kube-controller-manager
    
Now change the status of the cluster by deleting some running pods

    kubectl delete pod nginx-1423793266-0fh6d nginx-1423793266-14x09
    pod "nginx-1423793266-0fh6d" deleted
    pod "nginx-1423793266-14x09" deleted

In normal conditions, with the controller manager running, this trigger the recreation of two new pods to honour the replica set specified by the user. But the controller failure prevents it

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-1423793266-fbrvg   1/1       Running   0          14m
    nginx-1423793266-ghk3t   1/1       Running   0          1m
    nginx-1423793266-q2nnw   1/1       Running   0          47m
    nginx-1423793266-wjmjs   1/1       Running   0          14m

Restore the controller manager and check it does its job correctly

    systemctl start kube-controller-manager
    
    kubectl get pods
    NAME                     READY     STATUS              RESTARTS   AGE
    nginx-1423793266-b10l0   0/1       ContainerCreating   0          1s
    nginx-1423793266-fbrvg   1/1       Running             0          15m
    nginx-1423793266-ghk3t   1/1       Running             0          2m
    nginx-1423793266-q2nnw   1/1       Running             0          48m
    nginx-1423793266-w87jh   0/1       ContainerCreating   0          1s
    nginx-1423793266-wjmjs   1/1       Running             0          15m

## Worker Failure
In this section, we are going to see how to deal with failure of a worker node

### Maintenance of a worker node
The cluster admin can have needs to operate on a worker node for any maintenance reason. Our cluster has three worker nodes

    kubectl get nodes
    NAME      STATUS    AGE       VERSION
    kubew03   Ready     7h        v1.7.0
    kubew04   Ready     7h        v1.7.0
    kubew05   Ready     7h        v1.7.0

and a maintenance windows can be scheduled on it without impacting on the user applications

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-b10l0   1/1       Running   0          6m        10.38.2.16   kubew04
    nginx-1423793266-fbrvg   1/1       Running   0          21m       10.38.0.44   kubew03
    nginx-1423793266-ghk3t   1/1       Running   0          8m        10.38.1.13   kubew05
    nginx-1423793266-q2nnw   1/1       Running   0          54m       10.38.1.11   kubew05
    nginx-1423793266-w87jh   1/1       Running   0          6m        10.38.0.45   kubew03
    nginx-1423793266-wjmjs   1/1       Running   0          21m       10.38.2.14   kubew04

The admin can put in maintenance one of the node. This move all the pods running on that node to the remaining nodes preventing the scheduler to schedule new pod on the cordoned node

    kubectl drain kubew03 --force
    node "kubew03" cordoned
    pod "nginx-1423793266-fbrvg" evicted
    pod "nginx-1423793266-w87jh" evicted
    pod "kube-dns-2619606146-224mm" evicted
    node "kubew03" drained
    
Check the status of the nodes

    kubectl get nodes
    NAME      STATUS                     AGE       VERSION
    kubew03   Ready,SchedulingDisabled   7h        v1.7.0
    kubew04   Ready                      7h        v1.7.0
    kubew05   Ready                      7h        v1.7.0

And where its pods are now running

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-b10l0   1/1       Running   0          10m       10.38.2.16   kubew04
    nginx-1423793266-ghk3t   1/1       Running   0          13m       10.38.1.13   kubew05
    nginx-1423793266-j9px4   1/1       Running   0          47s       10.38.2.17   kubew04
    nginx-1423793266-q2nnw   1/1       Running   0          59m       10.38.1.11   kubew05
    nginx-1423793266-wjmjs   1/1       Running   0          26m       10.38.2.14   kubew04
    nginx-1423793266-zf11c   1/1       Running   0          47s       10.38.2.18   kubew04

Having completed the maintenance operations, the cluster admin can restore the node to be again available for user applications

    kubectl uncordon  kubew03
    node "kubew03" uncordoned
    
After the node is completly restored, check where are running the pods

    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-b10l0   1/1       Running   0          21m       10.38.2.16   kubew04
    nginx-1423793266-ghk3t   1/1       Running   0          24m       10.38.1.13   kubew05
    nginx-1423793266-j9px4   1/1       Running   0          11m       10.38.2.17   kubew04
    nginx-1423793266-q2nnw   1/1       Running   0          1h        10.38.1.11   kubew05
    nginx-1423793266-wjmjs   1/1       Running   0          37m       10.38.2.14   kubew04
    nginx-1423793266-zf11c   1/1       Running   0          11m       10.38.2.18   kubew04

We see pods are not moved back to the restored node.

### Failure of a worker node
As in any working envinronments, a worker nodes can fail. However, the kubernetes cluster is designed to deal with that leaving user applications to be moved on other worker nodes.

As in the previous example, check where user pods are running before to simulate a worker failure

    kubectl get pods -o wide

    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-704fv   1/1       Running   0          21s       10.38.1.15   kubew05
    nginx-1423793266-jh5m7   1/1       Running   0          21s       10.38.0.49   kubew03
    nginx-1423793266-x60qb   1/1       Running   0          21s       10.38.2.19   kubew04

Login to a worker node, e.g. kubew03, and simulate a failure by stopping the kubelet service

    systemctl stop kubelet
    
And check the status of the nodes

    kubectl get node
    NAME      STATUS     AGE       VERSION
    kubew03   NotReady   8h        v1.7.0
    kubew04   Ready      8h        v1.7.0
    kubew05   Ready      8h        v1.7.0

It has been marker as not ready. Now check the running pods. It will take some time before the pods are running on the failed node are moved to another one in the cluster

    kubectl get pods -o wide

    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-704fv   1/1       Running   0          4m        10.38.1.15   kubew05
    nginx-1423793266-jh5m7   1/1       Running   0          4m        10.38.0.49   kubew03
    nginx-1423793266-x60qb   1/1       Running   0          4m        10.38.2.19   kubew04

It will take 5 minutes by design and it is controlled by the ``--pod-eviction-timeout`` of the controller manager.

    kubectl get pods -o wide

    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-704fv   1/1       Running   0          8m        10.38.1.15   kubew05
    nginx-1423793266-7220d   1/1       Running   0          2m        10.38.2.20   kubew04
    nginx-1423793266-jh5m7   1/1       Unknown   0          8m        10.38.0.49   kubew03
    nginx-1423793266-x60qb   1/1       Running   0          8m        10.38.2.19   kubew04

Login again to the worker node and put it back

    systemctl restart kubelet

The node is moved back in ready state

    kubectl get node
    NAME      STATUS    AGE       VERSION
    kubew03   Ready     8h        v1.7.0
    kubew04   Ready     8h        v1.7.0
    kubew05   Ready     8h        v1.7.0

Now check where are running the pods

    kubectl get pods -o wide

    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-1423793266-704fv   1/1       Running   0          11m       10.38.1.15   kubew05
    nginx-1423793266-7220d   1/1       Running   0          4m        10.38.2.20   kubew04
    nginx-1423793266-x60qb   1/1       Running   0          11m       10.38.2.19   kubew04

As in the previous example, we see pods are not moved back to the restored node.
