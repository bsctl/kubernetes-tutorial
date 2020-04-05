# High Availability Control Plane
For running services without interruption it’s not only the apps that need to be up all the time, but also the Kubernetes Control Plane components. In this section, we’ll configure the control plane to achieve high availability with multiple master nodes.

   * [Configuring multiple etcd instances](#configuring-multiple-etcd-instances)
   * [Configuring multiple APIs servers](#configuring-multiple-apis-servers)
   * [Configuring multiple Controller Managers](#configuring-multiple-controller-managers)
   * [Configuring multiple Schedulers](#configuring-multiple-schedulers)
   * [Configuring the Load Balancer](#configuring-the-load-balancer)
   * [APIs server redundancy](#apis-server-redundancy)   
   * [Controllers redundancy](#controllers-redundancy)


Here the hostnames and addresses:

  * *kubem00* (master) 10.10.10.80
  * *kubem01* (master) 10.10.10.81
  * *kubem02* (master) 10.10.10.82

Make sure to enable DNS resolution for the above hostnames. 

To make kubernetes control plane high available, we need to run multiple instances of:

  * *etcd*
  * *APIs Server*
  * *Controller Manager*
  * *Scheduler*
  
On top of the master nodes, we'll setup an additional machine as load balancer in order to distribute the requests to all masters:

  * *kubernetes* (load balancer) 10.10.10.2

Configure the DNS to resolve the *kubernetes* hostname with the load balancer address. We'll use this name in our configuration files without specifying for a particular hostname.

The etcd and the APIs server will run in active-active mode meaning all instances are able to handle requests in parallel. The Controller Manager and the Scheduler will run in active-standby mode meaning only one instance is handling requests while the other two are in standy waiting for take over.

## Configuring multiple etcd instances
The etcd distributed key/value database stores all configurations about the claster status. It has been designed to be natively running in multiple instance, so all we need is run it on an appropriate number of machines. Because the etcd is based on the **Raft** distributed consensus algorithm, we need to setup an odd number of machines to avoid the so called *"split-brain"* scenario where a partitioning in the cluster can lead the two partitions to act independently.

We'll configure an etcd instance on each master node.

### Create the TLS certificates
Create the ``etcd-server-csr.json`` configuration file
```json
{
  "CN": "etcd-server",
  "hosts": [
    "127.0.0.1",
    "10.10.10.80",
    "10.10.10.81",
    "10.10.10.82"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
```

Create the key and certificate using the CA files we used for setting up a single master kubernetes

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=cert-config.json \
      -profile=peer-authentication \
      etcd-server-csr.json | cfssljson -bare etcd-server

This will produce the ``etcd-server.pem`` certificate file containing the public key and the ``etcd-server-key.pem`` file, containing the private key. Move the keys pair to all the master node in the proper location ``/etc/etcd/pki`` as well as the certification authority certificate we used:

    for instance in kubem00 kubem01 kubem02; do
      scp etcd-server*.pem ${instance}:/etc/etcd/pki
    done

Also make sure to move in the same location, the client etcd and the certification authority certificates, we created previously for the single master kubernetes setup

    for instance in kubem00 kubem01 kubem02; do
      scp ca.pem ${instance}:/etc/etcd/pki
      scp etcd-client*.pem ${instance}:/etc/etcd/pki
    done

### Create the instances
On each master node, create the ``/var/lib/etcd`` data directory and set options in the ``/etc/systemd/system/etcd.service`` startup file

    [Unit]
    Description=etcd
    Documentation=https://github.com/coreos
    After=network.target
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=notify
    ExecStart=/usr/bin/etcd \
      --name kubem00 \
      --trusted-ca-file=/etc/kubernetes/pki/ca.pem \
      --cert-file=/etc/etcd/pki/etcd-server.pem \
      --key-file=/etc/etcd/pki/etcd-server-key.pem \
      --client-cert-auth=true \
      --listen-client-urls https://10.10.10.80:2379\
      --advertise-client-urls https://10.10.10.80:2379 \
      --peer-client-cert-auth=true \
      --peer-trusted-ca-file=/etc/kubernetes/pki/ca.pem \
      --peer-cert-file=/etc/etcd/pki/etcd-server.pem \
      --peer-key-file=/etc/etcd/pki/etcd-server-key.pem \
      --initial-advertise-peer-urls https://10.10.10.80:2380 \
      --listen-peer-urls https://10.10.10.80:2380 \
      --initial-cluster-token etcd-cluster-token \
      --initial-cluster kubem00=https://10.10.10.80:2380,kubem01=https://10.10.10.81:2380,kubem02=https://10.10.10.82:2380 \
      --initial-cluster-state new \
      --data-dir=/var/lib/etcd \
      --debug=false

    Restart=on-failure
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target

On each node, start and enable the service

    systemctl daemon-reload
    systemctl start etcd
    systemctl enable etcd
    systemctl status etcd

To check the etcd cluster formation, query any of the etcd instances about the membership

    etcdctl -C https://10.10.10.80:2379 \
               --ca-file=/etc/etcd/pki/ca.pem  \
               --cert-file=/etc/etcd/pki/etcd-client.pem \
               --key-file=/etc/etcd/pki/etcd-client-key.pem \
               member list

    name=kubem00 peerURLs=https://10.10.10.80:2380 clientURLs=https://10.10.10.80:2379 isLeader=true
    name=kubem01 peerURLs=https://10.10.10.81:2380 clientURLs=https://10.10.10.81:2379 isLeader=false
    name=kubem02 peerURLs=https://10.10.10.82:2380 clientURLs=https://10.10.10.82:2379 isLeader=false

We see the etcd cluster formed with the first instance having the leader role.

## Configuring multiple APIs servers
On each master node, set the options in the ``/etc/systemd/system/kube-apiserver.service`` startup file

    [Unit]
    Description=Kubernetes API Server
    Documentation=https://github.com/GoogleCloudPlatform/kubernetes
    After=network.target
    After=etcd.service

    [Service]
    Type=notify
    ExecStart=/usr/bin/kube-apiserver \
      --admission-control=NamespaceLifecycle,ServiceAccount,LimitRanger,ResourceQuota,DefaultStorageClass \
      --etcd-servers=https://10.10.10.80:2379,https://10.10.10.81:2379,https://10.10.10.82:2379 \
      --etcd-cafile=/etc/etcd/pki/ca.pem \
      --etcd-certfile=/etc/etcd/pki/etcd-client.pem \
      --etcd-keyfile=/etc/etcd/pki/etcd-client-key.pem \
      --advertise-address=0.0.0.0 \
      --allow-privileged=true \
      --bind-address=0.0.0.0 \
      --secure-port=6443 \
      --service-cluster-ip-range=10.32.0.0/16 \
      --service-node-port-range=30000-32767 \
      --client-ca-file=/etc/kubernetes/pki/ca.pem \
      --tls-cert-file=/etc/kubernetes/pki/apiserver.pem \
      --tls-private-key-file=/etc/kubernetes/pki/apiserver-key.pem \
      --service-account-key-file=/etc/kubernetes/pki/sa.key \
      --kubelet-client-certificate=/etc/kubernetes/pki/kubelet-client.pem \
      --kubelet-client-key=/etc/kubernetes/pki/kubelet-client-key.pem \
      --insecure-bind-address=127.0.0.1 \
      --insecure-port=8080 \
      --endpoint-reconciler-type=lease \
      --enable-swagger-ui=true \
      --authorization-mode=Node,RBAC \
      --v=2

    Restart=on-failure
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target

Also make sure to copy all required certificates and keys on the proper locations

    for instance in kubem00 kubem01 kubem02; do
      scp ca*.pem ${instance}:/etc/kubernetes/pki
      scp apiserver*pem ${instance}:/etc/kubernetes/pki
      scp sa.key ${instance}:/etc/kubernetes/pki
      scp kubelet-client*pem ${instance}:/etc/kubernetes/pki     
    done

Start and enable the service

    systemctl daemon-reload
    systemctl start kube-apiserver
    systemctl enable kube-apiserver
    systemctl status kube-apiserver

## Configuring multiple Controller Managers
To configure the controller manager component to communicate securely with APIs server, on all the master nodes, set the required options in the ``/etc/systemd/system/kube-controller-manager.service`` startup file

    [Unit]
    Description=Kubernetes Controller Manager
    Documentation=https://github.com/GoogleCloudPlatform/kubernetes
    After=network.target

    [Service]
    ExecStart=/usr/bin/kube-controller-manager \
      --kubeconfig=/var/lib/kube-controller-manager/kubeconfig \
      --address=127.0.0.1 \
      --cluster-cidr=10.38.0.0/16 \
      --cluster-name=kubernetes \
      --leader-elect=true \
      --service-cluster-ip-range=10.32.0.0/16 \
      --root-ca-file=/etc/kubernetes/pki/ca.pem \
      --service-account-private-key-file=/etc/kubernetes/pki/sa.key \
      --use-service-account-credentials=true \
      --controllers=* \
      --v=2

    Restart=on-failure
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target

Then create the ``kubeconfig`` file under the proper directory ``/var/lib/kube-controller-manager/``
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.pem
    server: https://kubernetes:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: system:kube-controller-manager
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: system:kube-controller-manager
  user:
    client-certificate: /var/lib/kube-controller-manager/pki/controller-manager.pem
    client-key: /var/lib/kube-controller-manager/pki/controller-manager-key.pem
```

Before to start the service, make sure to copy all required certificates and keys on the proper locations

    for instance in kubem00 kubem01 kubem02; do
      scp controller-manager*pem ${instance}:/var/lib/kube-controller-manager/pki
    done

On all the master nodes, start and enable the service

    systemctl daemon-reload
    systemctl start kube-controller-manager
    systemctl enable kube-controller-manager
    systemctl status kube-controller-manager

## Configuring multiple Schedulers
On all the master nodes, configure the sceduler by setting the required options in the ``/etc/systemd/system/kube-scheduler.service`` startup file

    [Unit]
    Description=Kubernetes Scheduler
    Documentation=https://github.com/GoogleCloudPlatform/kubernetes
    After=network.target

    [Service]
    ExecStart=/usr/bin/kube-scheduler \
      --address=127.0.0.1 \
      --kubeconfig=/var/lib/kube-scheduler/kubeconfig \
      --leader-elect=true \
      --v=2

    Restart=on-failure
    RestartSec=5
    LimitNOFILE=65536

    [Install]
    WantedBy=multi-user.target

Then create the ``kubeconfig`` file under the proper directory ``/var/lib/kube-scheduler/``
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.pem
    server: https://kubernetes:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: system:kube-scheduler
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: system:kube-scheduler
  user:
    client-certificate: /var/lib/kube-scheduler/pki/scheduler.pem
    client-key: /var/lib/kube-scheduler/pki/scheduler-key.pem
```

Before to start the service, make sure to copy all required certificates and keys on the proper locations

    for instance in kubem00 kubem01 kubem02; do
      scp scheduler*pem ${instance}:/var/lib/kube-scheduler/pki
    done

On all the master nodes, start and enable the service

    systemctl daemon-reload
    systemctl start kube-scheduler
    systemctl enable kube-scheduler
    systemctl status kube-scheduler


## Configuring the Load Balancer
To fairly balance the requests towards the APIs servers, we configure a load balancer on an additional machine with HAProxy. The load balancer will do health checks of the APIs server on each of the nodes and balance the requests to the healthy instances in the cluster. It is configured as transparent SSL proxy in TCP mode.

The relevant part of the config is in ``/etc/haproxy/haproxy.cfg`` file
```
...
#---------------------------------------------------------------------
# Listen configuration
#---------------------------------------------------------------------

listen secure_kube_control_plane
    bind :6443
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server secure_kubem00 10.10.10.80:6443 check
    server secure_kubem01 10.10.10.81:6443 check
    server secure_kubem02 10.10.10.82:6443 check
...
```

All clients talking to the APIs server will send their requests to the load balancer and then forwarded transparently in a round robin fashion to the APIs servers.

To avoid single point of failure in the load balancer, instead to use a single external machine, we can setup an istance of HAProxy on all the master nodes and configure redundant DNS entries for the load balancer hostname.

## APIs server redundancy
The apiserver is exposed through a service called **kubernetes** in the dafault namespace.

    kubectl get svc -o wide -n default
    
    NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE       SELECTOR
    kubernetes   ClusterIP   10.32.0.1    <none>        443/TCP   9d        <none>

This service is accessible to all pods from any namespaces. Pods access this service through its endpoints corresponding to the apiserver replicas that we set.

Check the endpoints

    kubectl get endpoints -n default
    
    NAME         ENDPOINTS                                            AGE
    kubernetes   10.10.10.80:6443,10.10.10.81:6443,10.10.10.82:6443   10m

We see the addresses of all APIs servers. Please, note that pods cannot access the APIs server through the external load balancer se configured above but instead through the iptables set by the kube-proxy. This means, in case of one of the APIs server stops to work, the list of endpoints is not updated and pods can fail to access the APIs server.

To workaround this, a reconciler implementation is available in kubernetes. It uses a lease that is regularly renewed by each APIs server replica. When a replica is down, it stops renewing its lease, and the other replicas notice that the lease expired and remove it from the list of endpoints. This is achieved by adding the flag ``--endpoint-reconciler-type=lease`` in the APIs server configuration file.


## Controllers redundancy
Compared to the API server, where multiple replicas can run simultaneously, running multiple instances of the Controller Manager or the Scheduler requires coordination among instances. Because controllers and the scheduler all actively watch the cluster state and then act when it changes, running multiple instances of each of those components would result in all of them performing the same action.

For this reason, when running multiple instances of these components, only one instance may be active at any given time. This is controlled with the ``--leader-elect=true`` option in the startup files of both the controller manager and the scheduler. Each individual instance will only be active when it becomes the elected leader. Only the leader performs actual work, whereas all other instances are standing by and waiting for the current leader to fail. When it does, the remaining instances elect a new leader, which then takes over the work. This mechanism ensures that two components are never operating at the same time.

To check the active instance of the controller manager, query the system for the service endpoints in the ``kube-system`` namespace

    kubectl describe endpoints kube-controller-manager -n kube-system
    
    Name:         kube-controller-manager
    Namespace:    kube-system
    Labels:       <none>
    Annotations:  control-plane.alpha.kubernetes.io/leader
                  {
                   "holderIdentity":"kubem00",
                   "leaseDurationSeconds":15,
                   "acquireTime":"2018-03-18T03:55:36Z",
                   "renewTime":"2018-03-19T14:46:50Z",
                   "leaderTransitions":3
                  }
    Subsets:
    Events:  <none>

The ``holderIdentity`` annotation reports the name of the current leader. Once becoming the leader, it periodically update the resource, so all other instances know that it is still alive. When the current leader fails, the other instances see that the resource has not been updated for a while, and try to become
the new leader by writing their name to the resource.

    kubectl describe endpoints kube-controller-manager -n kube-system
    
    Name:         kube-controller-manager
    Namespace:    kube-system
    Labels:       <none>
    Annotations:  control-plane.alpha.kubernetes.io/leader
                  {
                   "holderIdentity":"kubem01",
                   "leaseDurationSeconds":15,
                   "acquireTime":"2018-03-19T14:48:31Z",
                   "renewTime":"2018-03-19T14:48:33Z",
                   "leaderTransitions":4
                  }
    Subsets:
    Events:
      Type    Reason          Age   From                Message
      ----    ------          ----  ----                -------
      Normal  LeaderElection  3s    controller-manager  kubem01 became leader

The same technique is used for the scheduler.
