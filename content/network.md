# Cluster Networking
Kubernetes assumes that pods can communicate with other pods in the cluster, no matter of which host they land on. In a kubernetes cluster, every pod has its own IP address, so the cluster administrator does not need to create links between pods and never needs to deal with mapping container address to host address.

Kubernetes network model, based on **CNI**, Container Networking Interface, requires that the container address ranges should be routable. This is different from the default docker network model that provides a docker bridge with IP address in a given default subnet. In the default Docker model, each container will get an IP address in that subnet and uses the docker  bridge IP as it’s default gateway.

Kubernetes creates a cleaner model where pods can be treated much like virtual machines or physical hosts from the perspectives of addressing, naming, service discovery and load balancing. There are many ways to implement kubernetes networking model, including L2 and L3 approaches. In this tutorial we are not using the overlay networking daemon for kubernetes. Inseatd, we're using a pure L3 solution based on the static routing table. However, this approach is not suitable for production envinronments. It is used only with learning scope.

In the following sections we're going into a walk-through in kubernetes networking

   * [Pod Networking](#pod-networking)
   * [Exposing services](#exposing-services)
   * [Service discovery](#service-discovery)
   * [Accessing services](#accessing-services)
   * [External services](#external-services)
   * [Network Policies](#network-policies)

## Pod Networking
In a kubernetes cluster, when a pod is deployed, it gets an IP address from the cluster IP address range defined in the inital setup.

Starting form the ``nginx-pod1.yaml`` file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx1
  namespace: default
  labels:
    run: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

Create a nginx pod

    kubectl create -f nginx-pod1.yaml
    pod "nginx1" created

To get the IP address of the pod

    kubectl get pod nginx1 -o wide
    NAME          READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx1        1/1       Running   2          21s       10.38.3.29   kubew03


Thanks to the kubernetes networking model, we can access pod IP from any node in the cluster

      curl 10.38.3.29:80
      Welcome to nginx!

Please that the containers are not using port 80 on the host node where the container is running. This means we can run multiple nginx pods on the same node all using the same container port 80 and access them from any other pod or node in the cluster using their IP. Start a second nginx pod

    kubectl create -f nginx-pod2.yaml
    pod "nginx2" created

    kubectl get pods -o wide
    NAME          READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx1        1/1       Running   0          21s       10.38.3.29   kubew03
    nginx2        1/1       Running   0          21s       10.38.3.30   kubew03

Both pods run on the same host node, as we see from their IP address. We can still access both pods from any other node in the cluster

      curl 10.38.3.29:80
      Welcome to nginx!
    
      curl 10.38.3.30:80
      Welcome to nginx!

We do not need to expose container port on host to access nginx application as it is required in standard docker networking model.

### Host Networking
As alternative, we can define pods to use the same host IP address as defined in the ``nodejs-pod-hostnet.yaml`` configuration file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nodejs
  namespace:
  labels:
spec:
  containers:
  - name: nodejs
    image: kalise/nodejs-web-app:latest
    ports:
    - containerPort: 8080
  hostNetwork: true
``` 

Create the pod and check the IP address

    kubectl create -f nodejs-pod-hostnet.yaml
    
    kubectl get pods -o wide
    NAME          READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx1        1/1       Running   0          10m       10.38.3.29   kubew03
    nginx2        1/1       Running   0          10m       10.38.3.30   kubew03
    nodejs        1/1       Running   0          5m        10.10.10.83  kubew03

However, with the ``hostNetwork: true`` we cannot start more than one pod listening on the same host port. In general, pods with host network are only used for system or daemon applications that do not need to be scaled.

## Exposing services
In kubernetes, services are used not only to provides access to other pods inside the same cluster but also to clients outside the cluster. In this section, we're going to create a deploy of two nginx replicas and expose them to the external world via a nginx service.

Create the deploy

    kubectl create -f nginx-deploy.yaml
    deployment "nginx" created
    
    kubectl get pods
    NAME                    READY     STATUS    RESTARTS   AGE
    nginx-664452237-2r6sf   1/1       Running   0          4m
    nginx-664452237-hr532   1/1       Running   0          4m
    
    kubectl get pods -l run=nginx -o yaml | grep podIP
    podIP: 172.30.5.3
    podIP: 172.30.41.2

Pods are running on different host nodes as we can see from their IP addresses. To create a nginx service, we can expose the deploy on port 80 by running

    kubectl expose deploy/nginx --port=80 --target-port=80 --name=nginx-service
    service "nginx-service" exposed
    
    kubectl get services -l run=nginx
    NAME            CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
    nginx-service   10.254.247.153   <none>        80/TCP    36s

    kubectl describe service nginx-service
    Name:                   nginx-service
    Namespace:              default
    Labels:                 run=nginx
    Selector:               run=nginx
    Type:                   ClusterIP
    IP:                     10.254.247.153
    Port:                   <unset> 80/TCP
    Endpoints:              172.30.41.2:80,172.30.5.3:80
    Session Affinity:       None

This is equivalent to create the service from a ``nginx-svc.yaml`` file

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    run: nginx
```

Any other pod in the cluster is able to access the nginx service without worring about pod IP addresses

    kubectl create -f busybox.yaml

    kubectl exec -it busybox sh
    / # wget -O - 10.254.247.153:80
    Welcome to nginx!

However, the service is not reachable from any cluster host. If we try to access the service we do not get anything

    curl 10.254.247.153:80

Without specifying the type of service, kubernetes by default uses the ``Type: ClusterIP`` option, which means that the new service is only exposed only within the cluster. It is kind of like internal kubernetes service, so not particularly useful if you want to accept external traffic.

When creating a service, kubernetes provides different options of service types:

   * **ClusterIP**: it exposes the service only on a cluster internal IP making the service only reachable from within the cluster. This is the default service type.
   * **NodePort**: it exposes the service on each node public IP on a static port as defined in the NodePort option. It will be possible to access the service, from outside the cluster.
   * **LoadBalancer**: it exposes the service by creating an external load balancer. It works only on some public cloud providers. To make this working, remember to set the option ``--cloud-provider`` in the kube controller manager startup file.

In this section we are going to use the NodePort service type to expose the service.

Delete the the service we created earlier

    kubectl delete svc/nginx-service
    service "nginx-service" deleted

Create a new service with NodePort type

    kubectl expose deploy/nginx --port=80 --target-port=80 --type=NodePort --name=nginx-service
    service "nginx-service" exposed

    kubectl describe svc/nginx-service
    Name:                   nginx-service
    Namespace:              default
    Labels:                 run=nginx
    Selector:               run=nginx
    Type:                   NodePort
    IP:                     10.254.114.251
    Port:                   <unset> 80/TCP
    NodePort:               <unset> 31608/TCP
    Endpoints:              172.30.41.2:80,172.30.5.3:80
    Session Affinity:       None

The NodePort type opens a service port on every worker node in the cluster. The service port is mapped to a port on the public IP node as in the NodePort. On any worker node, it is available at     
    
    
    [root@kuben05 ~]# netstat -natp | grep 31608
    tcp6       0      0 :::31608                :::*                    LISTEN      859/kube-proxy

    [root@kuben06 ~]# netstat -natp | grep 31608
    tcp6       0      0 :::31608                :::*                    LISTEN      863/kube-proxy

The kube-proxy service on the worker node, is in charge of doing this job by configuring the IPtables. Now it is possible to access the nginx service from ouside the cluster by pointing to any worker node

    [root@centos ~]# curl 10.10.10.85:31608
    Welcome to nginx!

    [root@centos ~]# curl 10.10.10.86:31608
    Welcome to nginx!

The NodePort is randomly selected from the 30000-32767 range. If you want to force a specific port, define it in a file ``nginx-nodeport-svc.yaml``  
    
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
  selector:
    run: nginx
  type: NodePort
```

Now that we have a port open on every worker node, we can configure an external load balancer or edge router to route the traffic to any of the worker nodes. Please, note, the service port, if specified, must be in the range defined by the ``--service-node-port-range`` option in the Controller Manager configuration file.

To use the LoadBalancer service type, delete the previous nginx service and change the configuration of the service as in the following ``nginx-loadbalancer-svc.yaml`` configuration file

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    run: nginx
  type: LoadBalancer
```

In this case, an external load balancer is created on top of the kubernetes worker nodes. This load balancer exposes on the Internet the service port specified in the file. In the example above, we have the nginx service exposed on port 80 of the load balancer. To check the public external IP assigned to the load balancer, inspect the service

    kubectl get svc nginx -o wide
    NAME            TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE    SELECTOR
    service/nginx   LoadBalancer   10.32.108.201   104.155.43.158   80:30473/TCP   40m    run=nginx

By accessing the load balancer frontend on its public own IP and port 80, a client's request will be forwarded to the nginx pods passing through the service node port 30473. The service type LoadBalancer is quite expensive because, a separate load balancer will be created for each exposed service.

## Service discovery
To enable service name discovery in a kubernetes cluster, we need to configure an embedded DNS service to resolve all DNS queries from pods trying to access services. The embedded DNS should be manually installed during cluster setup since it is part of the cluster architecture, unless users are going to use other custom solutions for service discovery.

The embedded DNS lives in the kube-system namespace

    kubectl get all -n kube-system
    NAME              DESIRED   CURRENT   READY     AGE
    rc/kube-dns-v20   1         1         1         1d

    NAME           CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE
    svc/kube-dns   10.32.0.10     <none>        53/UDP,53/TCP   1d

    NAME                    READY     STATUS    RESTARTS   AGE
    po/kube-dns-v20-3xk4v   3/3       Running   3          1d

It consists of a controller, a service and a pod running a DNS server, a dnsmaq for caching and healthz for liveness probe. Each time a user starts a new pod, kubernetes injects certain nameservice lookup configuration into new pods allowing to query the DNS records in the cluster. Each time a new service is created, kubernetes registers this service name into the embedded DNS server allowing all pods to query the DNS server for service name resolution.

Create a nginx deploy and create the service. Since we're not interested to expose the service outside the cluster, we leave the default service type, i.e. the ClusterIP mode. This allows only pods inside the cluster can access the service.

    kubectl create -f nginx-deploy.yaml
    deployment "nginx" created
    
    kubectl expose deploy/nginx --port=8080 --target-port=80 --name=nginx-service
    service "nginx-service" exposed

    kubectl get all -l run=nginx
    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   2         2         2            2           3m
    NAME                CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
    svc/nginx-service   10.32.0.44     <none>        8080/TCP   33s
    NAME                 DESIRED   CURRENT   READY     AGE
    rs/nginx-664452237   2         2         2         3m
    NAME                       READY     STATUS    RESTARTS   AGE
    po/nginx-664452237-lkkxx   1/1       Running   0          3m
    po/nginx-664452237-n9pwd   1/1       Running   0          3m

Start a test pod and check if it access the nginx service

    kubectl create -f busybox.yaml
    pod "busybox" created

    kubectl exec -ti busybox -- wget 10.32.0.44:8080
    index.html  200 OK  

Check if service DNS lookup configuration has been injectd by kubernetes

    kubectl exec -ti busybox -- cat /etc/resolv.conf
    search default.svc.cluster.local svc.cluster.local cluster.local
    nameserver 10.32.0.10
    nameserver 8.8.8.8
    options ndots:5

Now check if service discovery works by resolv the service name

    kubectl exec -ti busybox -- nslookup nginx-service
    Server:    10.32.0.10
    Address 1: 10.32.0.10 kube-dns.kube-system.svc.cluster.local
    Name:      nginx-service
    Address 1: 10.32.0.44 nginx-service.default.svc.cluster.local

By default, the Kubernetes DNS server returns the service's cluster IP address. This IP address is static throughout the lifetime of the service. When sending traffic to this IP the iptables on the node will load balance packets across the ready pods that match the selectors of the service. These iptables are programmed automatically by the kube-proxy service running on each node.

If we want service discovery but would rather have the DNS service return the IP addresses of the pods rather than the service IP, we can provision the service with the ClusterIP field set to none which makes the service headless. In this case, the DNS server returns a list of A records that map the DNS name of the service to the A records of the running pods that match the service label selectors.

For example, create a nginx service as in the ``nginx-headless-svc.yaml`` descriptor

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  clusterIP: None
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    run: nginx
```

The service has missing IP

    kubectl get svc
    NAME        TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)          AGE
    nginx       ClusterIP      None            <none>           80/TCP           4m

Now check the service discovery by resolving the service name

    kubectl exec -it busybox -- nslookup nginx

    Name:      nginx
    Address 1: 10.38.2.5
    Address 2: 10.38.2.6
    Address 3: 10.38.2.7

We see the DNS server responding with the pod's IP addresses.

## Accessing services
In this section, we're going to deploy a WordPress application made of two services:

  1. Worpress service
  2. MariaDB service

We'll use the service discovery feature to permit the worpress pod to access the MariaDB pod without knowing the IP address. Also we'll expose the Worpress service to external world.

Create the MariaDB deploy as ``mariadb-deploy.yaml`` file
```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: mariadb
  name: mariadb
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: mariadb
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: mariadb
    spec:
      containers:
      - image: bitnami/mariadb:latest
        imagePullPolicy: Always
        name: mariadb
        ports:
        - containerPort: 3306
          protocol: TCP
        env:
        - name: MARIADB_ROOT_PASSWORD
          value: bitnami123
        - name: MARIADB_DATABASE
          value: wordpress
        - name: MARIADB_USER
          value: bitnami
        - name: MARIADB_PASSWORD
          value: bitnami123
        volumeMounts:
        - name: mariadb-data
          mountPath: /bitnami/mariadb

      volumes:
      - name: mariadb-data
        emptyDir: {}
      dnsPolicy: ClusterFirst
      restartPolicy: Always
```

and deploy it 

    kubectl create -f mariadb-deploy.yaml
    deployment "mariadb" created
    
    kubectl get all -l run=mariadb
    NAME             DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/mariadb   1         1         1            1           38s
    NAME                   DESIRED   CURRENT   READY     AGE
    rs/mariadb-503575936   1         1         1         38s
    NAME                         READY     STATUS    RESTARTS   AGE
    po/mariadb-503575936-l2j57   1/1       Running   0          38s


Create a service called ``mariadb`` as ``mariadb-svc.yaml`` file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mariadb
  labels:
    run: mariadb
spec:
  ports:
  - protocol: TCP
    port: 3306
    targetPort: 3306
  selector:
    run: mariadb
```

and expose it as an internal service

    kubectl create -f mariadb-svc.yaml
    service "mariadb" created

    kubectl get service -l run=mariadb
    NAME      CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
    mariadb   10.254.223.163   <none>        3306/TCP   24s

    kubectl describe svc mariadb
    Name:                   mariadb
    Namespace:              default
    Labels:                 run=mariadb
    Selector:               run=mariadb
    Type:                   ClusterIP
    IP:                     10.254.223.163
    Port:                   <unset> 3306/TCP
    Endpoints:              172.30.41.4:3306
    Session Affinity:       None

This service will be used by the wordpress application as database backend. Thanks to the DNS service discovery embedded in the kubernetes cluster, the worpres application has not to take care of the mariadb database IP address. It should only reference a generic ``mariadb`` host. The embedded DNS will resolve this name into the real IP address of the mariadb service. Also, since we are not controlling where kubernetes start the mariadb pod, we are not worring about of the real IP of the mariadb pod.

Here the ``wordpress-deploy.yaml`` file defining the wordpress application
```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  generation: 1
  labels:
    run: blog
  name: wordpress
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: blog
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        run: blog
    spec:
      containers:
      - image: bitnami/wordpress:latest
        imagePullPolicy: Always
        name: wordpress
        ports:
        - containerPort: 80
          protocol: TCP
        - containerPort: 443
          protocol: TCP
        env:
        - name: MARIADB_HOST
          value: mariadb
        - name: MARIADB_PORT
          value: '3306'
        - name: WORDPRESS_DATABASE_NAME
          value: wordpress
        - name: WORDPRESS_DATABASE_USER
          value: bitnami
        - name: WORDPRESS_DATABASE_PASSWORD
          value: bitnami123
        - name: WORDPRESS_USERNAME
          value: admin
        - name: WORDPRESS_PASSWORD
          value: password
        volumeMounts:
        - name: wordpress-data
          mountPath: /bitnami/wordpress
        - name: apache-data
          mountPath: /bitnami/apache
        - name: php-data
          mountPath: /bitnami/php

      volumes:
      - name: wordpress-data
        emptyDir: {}
      - name: apache-data
        emptyDir: {}
      - name: php-data
        emptyDir: {}

      dnsPolicy: ClusterFirst
      restartPolicy: Always
```

Deploy the wordpress application

    kubectl create -f wordpress-deploy.yaml
    deployment "wordpress" created

    kubectl get all -l run=blog
    NAME               DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/wordpress   1         1         1            1           9s
    NAME                      DESIRED   CURRENT   READY     AGE
    rs/wordpress-3277383805   1         1         1         9s
    NAME                            READY     STATUS    RESTARTS   AGE
    po/wordpress-3277383805-jdvrf   1/1       Running   0          9s

Now we need to expose the frontend wordpress application outside the cluster. To make this, we'll create a nodeport worpress service and expose it on a given port. Here the service definition as in the ``wordpress-svc.yaml`` file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  labels:
    run: blog
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 31080
  selector:
    run: blog
  type: NodePort
```

Create the service 

    kubectl create -f wordpress-svc.yaml
    service "wordpress" created

    kubectl get all -l run=blog
    NAME               DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/wordpress   1         1         1            1           4m
    NAME            CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
    svc/wordpress   10.254.62.237   <nodes>       80:31080/TCP   4s
    NAME                      DESIRED   CURRENT   READY     AGE
    rs/wordpress-3277383805   1         1         1         4m
    NAME                            READY     STATUS    RESTARTS   AGE
    po/wordpress-3277383805-jdvrf   1/1       Running   0          4m

    kubectl describe svc/wordpress
    Name:                   wordpress
    Namespace:              default
    Labels:                 run=blog
    Selector:               run=blog
    Type:                   NodePort
    IP:                     10.254.62.237
    Port:                   <unset> 80/TCP
    NodePort:               <unset> 31080/TCP
    Endpoints:              172.30.41.5:80
    Session Affinity:       None

This service will be accessible from all worker nodes in the cluster thanks to the kube-proxy job. Try to access it from any external client by pointing to any of the worker node

    wget 10.10.10.86:31080
    --2017-04-25 18:01:16--  http://10.10.10.86:31080/
    Connecting to 10.10.10.86:31080... connected.
    HTTP request sent, awaiting response... 200 OK
    Length: unspecified [text/html]
    Saving to: ‘index.html’
    2017-04-25 18:01:18 (3.45 MB/s) - ‘index.html’ saved [51713]

## External Services
The service abstraction in kubernetes can be used to model also external services that are not part of the cluster. For example, a pre-existing Oracle database can be modeled as a common standard service to be accessed from an application running in the cluster as pod. In this section, we are going to model an external MySQL database running on a remote machine with a given IP address. The only requirement is the worker nodes should be able to reach the address of the external database.

An external service does not use label selectors since there are no pods to bind in the cluster. An external service definition file ``mysql-external-svc.yaml`` looks like the following
```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-mysql
  namespace:
spec:
  ports:
  - port: 3306
    protocol: TCP
    targetPort: 3306
  type: ClusterIP
```

Create the service 

    kubectl create -f mysql-external-svc.yaml
    
    kubectl get services external-mysql -o wide
    NAME             CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE       SELECTOR
    external-mysql   10.32.107.128   <none>        3306/TCP   41m       <none>

By inspecting the service, we find that no endpoints are available since it is an headless service. The endpoints need to be manually created as in the ``mysql-external-ep.yaml`` configuration file
```yaml
apiVersion: v1
kind: Endpoints
metadata:
  name: external-mysql
  namespace:
subsets:
- addresses:
  - ip: 10.10.10.3
  ports:
  - port: 3306
    protocol: TCP
```

The IP address above is the actual IP address of the MySQL server running outside the kubernetes cluster.

To test the external MySQL server is modeled as an internal service in kubernetes, start a simple MySQL client running in a pod and connect to the external database by specifying the name of the external service as it is discovered by the embedded DNS in kubernetes

    kubectl run -it --rm ephemeral --image=mysql -- /bin/sh -l
    sh-4.2 $ mysql -h external-mysql -u root -p
    MySQL [(none)]>
    exit

## Network Policies
