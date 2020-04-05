# Getting started with core concepts
In this section we're going through core concepts of Kubernetes: 

   * [Pods](#core)
   * [Labels](#labels)
   * [Annotations](#annotations)
   * [Replica Sets](#replica-sets)
   * [Deployments](#deployments)
   * [Services](#services)
   * [Volumes](#volumes)
   * [Config Maps](#config-maps)
   * [Secrets](#secrets)
   * [Daemons](#daemons)
   * [Jobs](#jobs)
   * [Cron Jobs](#cron-jobs)
   * [Namespaces](#namespaces)
   * [Quotas and Limits](#quotas-and-limits)
         
## Pods    
In Kubernetes, a group of one or more containers is called a pod. Containers in a pod are deployed together, and are started, stopped, and replicated as a group. The simplest pod definition describes the deployment of a single container. For example, an nginx web server pod might be defined as such ``pod-nginx.yaml`` file

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace:
  labels:
    run: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

A pod definition is a declaration of a desired state. Desired state is a very important concept in the Kubernetes model. Many things present a desired state to the system, and it is Kubernetes’ responsibility to make sure that the current state matches the desired state. For example, when you create a Pod, you declare that you want the containers in it to be running. If the containers happen to not be running (e.g. program failure), Kubernetes will continue to (re-)create them for you in order to drive them to the desired state. This process continues until the Pod is deleted.

Create a pod containing an nginx server 

    kubectl create -f pod-nginx.yaml

List all pods:

    kubectl get pods -o wide
    
    NAME      READY     STATUS    RESTARTS   AGE       IP            NODE
    nginx     1/1       Running   0          8m        172.30.21.2   kuben03

Describe the pod:

    kubectl describe pod nginx
    
    Name:           nginx
    Namespace:      default
    Node:           kuben03/10.10.10.83
    Start Time:     Wed, 05 Apr 2017 11:17:28 +0200
    Labels:         run=nginx
    Status:         Running
    IP:             172.30.21.2
    Controllers:    <none>
    Containers:
      nginx:
        Container ID:       docker://a35dafd66ac03f28ce4213373eaea56a547288389ea5c901e27df73593aa5949
        Image:              nginx:latest
        Image ID:           docker-pullable://docker.io/nginx
        Port:               80/TCP
        State:              Running
          Started:          Wed, 05 Apr 2017 11:17:37 +0200
        Ready:              True
        Restart Count:      0
        Volume Mounts:
          /var/run/secrets/kubernetes.io/serviceaccount from default-token-92z22 (ro)
        Environment Variables:      <none>
    Conditions:
      Type          Status
      Initialized   True
      Ready         True
      PodScheduled  True
    Volumes:
      default-token-92z22:
        Type:       Secret (a volume populated by a Secret)
        SecretName: default-token-92z22
    QoS Class:      BestEffort
    Tolerations:    <none>
    Events:
    ...

Delete the pod:

    kubectl delete pod nginx

A pod can be in one of the following phases:

  * **Pending**: the API Server has created a pod resource and stored it in etcd, but the pod has not been scheduled yet, nor have container images been pulled from the registry.
  * **Running**: the pod has been scheduled to a node and all containers have been created by the kubelet.
  * **Succeeded**: all containers in the pod have terminated successfully and will not be restarted.
  * **Failed**: all containers in the pod have terminated and, at least one container has terminated in failure.
  * **Unknown**: The API Server was unable to query the state of the pod, typically due to an error in communicating with the kubelet.

In the example above, we had a pod with a single container nginx running inside. Kubernetes let's user to have multiple containers running in a pod. All containers inside the same pod share the same resources, e.g. network and volumes and are always scheduled togheter on the same node.

The primary reason that Pods can have multiple containers is to support helper applications that assist a primary application. Typical examples of helper applications are data pullers, data pushers, and proxies. Helper and primary applications often need to communicate with each other, typically through a shared filesystem or loopback network interface.

## Labels
In Kubernetes, labels are a system to organize objects into groups. Labels are key-value pairs that are attached to each object. Label selectors can be passed along with a request to the apiserver to retrieve a list of objects which match that label selector.

To add a label to a pod, add a labels section under metadata in the pod definition:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nginx
...
```

To label a running pod

      kubectl label pod nginx type=webserver

To list pods based on labels

      kubectl get pods -l type=webserver
      
      NAME      READY     STATUS    RESTARTS   AGE
      nginx     1/1       Running   0          21m

Labels can be applied not only to pods but also to other Kuberntes objects like nodes. For example, we want to label or worker nodes based on the their position in the datacenter

      kubectl label node kuben01 rack=rack01
      
      kubectl get nodes -l rack=rack01
      
      NAME      STATUS    AGE
      kuben01   Ready     2d
      
      kubectl label node kuben02 rack=rack01
      
      kubectl get nodes -l rack=rack01
      
      NAME      STATUS    AGE
      kuben01   Ready     2d
      kuben02   Ready     2d

Labels are also used as selector for services and deployments.

## Annotations
In addition to labels, pods and other objects can also contain annotations. Annotations are also key-value pairs, so they are similar to labels, but they can’t be used to group objects the way labels can. While objects can be selected through label selectors, it is not possible to do the same with an annotation selector.

On the other hand, annotations can hold much larger pieces of information than labels. Certain annotations are automatically added to objects by Kubernetes, but others can be added by users.

Here an example of pod with annotation
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  annotations:
    readme: "before to run this pod, make sure you have a service account defined."
  namespace:
  labels:
    run: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

## Replica Sets
A Replica Set ensures that a specified number of pod replicas are running at any one time. In other words, a Replica Set makes sure that a pod or homogeneous set of pods are always up and available. If there are too many pods, it will kill some. If there are too few, it will start more. Unlike manually created pods, the pods maintained by a Replica Set are automatically replaced if they fail, get deleted, or are terminated.

A Replica Set configuration consists of:

 * The number of replicas desired
 * The pod definition
 * The selector to bind the managed pod

A selector is a label assigned to the pods that are managed by the replica set. Labels are included in the pod definition that the replica set instantiates. The replica set uses the selector to determine how many instances of the pod are already running in order to adjust as needed.

In the ``nginx-rs.yaml`` file, define a replica set with replica 1 for our nginx pod.
```yaml
apiVersion: extensions/v1beta1
kind: ReplicaSet
metadata:
  labels:
    run: nginx
  namespace:
  name: nginx-rs
spec:
  replicas: 3
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
    spec:
      containers:
      - image: nginx:1.12
        imagePullPolicy: Always
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
      restartPolicy: Always
```

Create a replica set

    kubectl create -f nginx-rs.yaml

List and describe a replica set

    kubectl get rs
    NAME      DESIRED   CURRENT   READY     AGE
    nginx     3         3         3         1m

    kubectl describe rs nginx
    Name:           nginx
    Namespace:      default
    Image(s):       nginx:latest
    Selector:       run=nginx
    Labels:         run=nginx
    Replicas:       3 current / 3 desired
    Pods Status:    3 Running / 0 Waiting / 0 Succeeded / 0 Failed
    No volumes.

The Replica Set makes it easy to scale the number of replicas up or down, either manually or by an auto-scaling control agent, by simply updating the replicas field. For example, scale down to zero replicas in order to delete all pods controlled by a given replica set

    kubectl scale rs nginx --replicas=0

    kubectl get rs nginx
    NAME      DESIRED   CURRENT   READY     AGE
    nginx     0         0         0         7m

Scale out the replica set to create new pods

    kubectl scale rs nginx --replicas=9

    kubectl get rs nginx
    NAME      DESIRED   CURRENT   READY     AGE
    nginx     9         9         0         9m

Also in case of failure of a node, the replica set takes care of keep the same number of pods by scheduling the containers running on the failed node to the remaining nodes in the cluster.

To delete a replica set

    kubectl delete rs/nginx
    
Deleting a replica set deletes all pods managed by that replica. But, because pods created by a controller are not actually an integral part of the replication set, but only managed by it, we can delete only the replication set and leave the pods running.

    kubectl delete rs/nginx --cascade=false

Now there is nothing managing pods, but we can always create a new replication set with the proper label selector and make them managed again.

A single replica set can match pods with the label ``env=production`` and those with the label ``env=dev`` at the same time. Also we can match all pods that include a label with the key ``run``, whatever its actual value is, acting as some similar to ``run=*``.

```yaml
...
selector:
   matchExpressions:                
     - key: run
       operator: In
       values:
         - nginx
           web
```

## Deployments
A Deployment provides declarative updates for pods and replicas. The Deployment object defines the strategy for transitioning between deployments of the same application.

There are basically two ways of updating an application:

  * delete all existing pods first and then start the new ones or
  * start new ones and once they are up, delete the old ones
  
The latter, can be done with two different approach:

  * add all the new pods and then deleting all the old ones at once
  * add new pods at time and then removing old ones one by one

To create a deployment for our nginx webserver, edit the ``nginx-deploy.yaml`` file as
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
  name: nginx
  namespace:
spec:
  minReadySeconds: 10
  progressDeadlineSeconds: 300
  revisionHistoryLimit: 3
  replicas: 6
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
      - image: nginx:1.12
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 10
          periodSeconds: 5
          successThreshold: 3
          failureThreshold: 1
      restartPolicy: Always
```

and create the deployment

    kubectl create -f nginx-deploy.yaml
    deployment "nginx" created

The deployment creates the following objects

    kubectl get all -l run=nginx -o wide

    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES	SELECTOR
    deploy/nginx   3         3         3            3           37s   nginx        nginx:1.12   run=nginx

    NAME                  DESIRED   CURRENT   READY   AGE    CONTAINERS   IMAGES .     SELECTOR
    rs/nginx-698d6b8c9f   3         3         3       37s    nginx        nginx:1.12   pod-template

    NAME                        READY     STATUS    RESTARTS   AGE       IP            NODE
    po/nginx-698d6b8c9f-cj9n6   1/1       Running   0          37s       10.38.4.200   kubew04
    po/nginx-698d6b8c9f-sr6fh   1/1       Running   0          37s       10.38.5.137   kubew05
    po/nginx-698d6b8c9f-vpsm4   1/1       Running   0          37s       10.38.3.125   kubew03

According to the definitions set in the file, above, there are a deploy, three pods and a replica set. 

The deployment defines the strategy for updates pods

```yaml
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
```

In the snippet above, we set the update strategy as rolling update. During the lifetime of an application, some pods need to be update, for example because the image changed. The Rolling Update strategy removes some old pods, while adding new ones at the same time, keeping the application available during the process and ensuring there is no lack of handle the user's requests. This is the default strategy.

The upper and lower limit for the number of pods above or below the desired replica count are configurable by the ``maxSurge`` and ``maxUnavailable`` parameters. The first one controls how many pod instances exist above the desired replica count configured on the deployment. It defaults to 1, which means there can be at most one pod instance more than the desired count. For example, if the desired replica count is set to 3, there will never be more than 4 pod instances running during the update at the same time.

The second parameter controls how many pods can be unavailable below to the desired replica count during the update. It also defaults to 1, which means the number of available pod instances must never fall below 1 less than the desired replica count. For example, if the desired replica count is set to 3, there will always be at least 2 pod instances available to serve requests during the whole rollout.

For example, to update the pods with a different version of nginx image

    kubectl set image deploy nginx nginx=nginx:1.13
    
Check the rollout status while it is happening

    kubectl rollout status deploy nginx

If you want to pause the rollout

    kubectl rollout pause deploy nginx

Resume it to complete

    kubectl rollout resume deploy nginx

Now there is a new replica set now taking control of the pods. This replica set control new pods having image ``nginx:1.13``. The old replica set is still there and can be used in case of downgrade.

To downgrade, undo the rollout

    kubectl rollout undo deploy nginx

This will report the deploy to the previous state.

When creating new pods, the Rolling strategy waits for pods to become ready. If the new pods never become ready, the deployment will time out and result in a deployment failure.

The deployment strategy uses readiness probe to determine if a new pod is ready for use. If the readiness probe fails, the deployment is stopped. The ``minReadySeconds`` property specifies how long a new created pod should be ready before the pod is treated as available. Until the pod becomes available, the update process will not continue. Once the readiness probe succeeds and the pod becomes available, then the update process can continue. With a properly configured readiness probe and a proper ``minReadySeconds`` setting, kubernetes prevents us from deploying the buggy version of the image.

For example, let's to upgrate the deploy to a buggy image version. This new version of the image is not working properly and hence the update process will fail when the first pod is updated. 

Update the image

    kubectl set image deploy nginx nginx=kalise/nginx:buggy

Check the rollout status

    kubectl rollout status deploy nginx
    Waiting for rollout to finish: 1 out of 6 new replicas have been updated...

Because of the readiness check the update process is blocked to the first pod running the buggy version. Having the deployment stuck, it prevents us to end up with a completely not working application. By default, after the rollout can’t make any progress in 600 seconds, it’s considered as failed

    kubectl rollout status deploy nginx
    Waiting for rollout to finish: 1 out of 6 new replicas have been updated...
    error: deployment "nginx" exceeded its progress deadline

This timer is controlled by the ``progressDeadlineSeconds`` property set into deploy descriptor.

Because the update process will never continue, the only thing to do now is abort the rollout

    kubectl rollout undo deployment nginx

A deployment, can be scaled up and down

    kubectl scale deploy nginx --replicas=6
    deployment "nginx" scaled

    kubectl get deploy nginx
    NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    nginx     6         6         6            3           11m

In a deploy, pods are always controlled by the replica set. However, because the replica set is controlled by the deploy, if we try to scale the replica set instead of the deploy, the deploy will take priority and the number of pods will be reported to the number requested by the deploy.

For example, try to scale up the replica set from the previous example to have 10 replicas

    kubectl scale rs nginx-698d6b8c9f --replicas=10

we see the number of pod scaled to 10, according to the request to scale the replica set to 10 pod. After few seconds, the deploy will take priority and remove all new pod created by the scaling the replica set because the desired stae, as specified by the deploy is to 6 pods.


## Services
Kubernetes pods, as containers, are ephemeral. Replication Sets create and destroy pods dynamically, e.g. when scaling up or down or when doing rolling updates. While each pod gets its own IP address, even those IP addresses cannot be relied upon to be stable over time. This leads to a problem: if some set of pods provides functionality to other pods inside the Kubernetes cluster, how do those pods find out and keep track of which other?

A Kubernetes Service is an abstraction which defines a logical set of pods and a policy by which to access them. The set of pods targeted by a Service is usually determined by a label selector. Kubernetes offers a simple Endpoints API that is updated whenever the set of pods in a service changes.

To create a service for our nginx webserver, edit the ``nginx-service.yaml`` file

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    run: nginx
spec:
  selector:
    run: nginx
  ports:
  - protocol: TCP
    port: 8000
    targetPort: 80
  type: ClusterIP
```

Create the service

    kubectl create -f nginx-service.yaml
    service "nginx" created
    
    kubectl get service -l run=nginx
    NAME      CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
    nginx     10.254.60.24   <none>        8000/TCP    38s

Describe the service

    kubectl describe service nginx
    
    Name:                   nginx
    Namespace:              default
    Labels:                 run=nginx
    Selector:               run=nginx
    Type:                   ClusterIP
    IP:                     10.254.60.24
    Port:                   <unset> 8000/TCP
    Endpoints:              172.30.21.3:80,172.30.4.4:80,172.30.53.4:80
    Session Affinity:       None
    No events.

The above service is associated to our previous nginx pods. Pay attention to the service selector ``run=nginx`` field. It tells Kubernetes that all pods with the label ``run=nginx`` are associated to this service, and should have traffic distributed amongst them. In other words, the service provides an abstraction layer, and it is the input point to reach all of the associated pods.

Pods can be added to the service arbitrarily. Make sure that the label ``run=nginx`` is associated to any pod we would to bind to the service. Define a new pod from the following file without (intentionally) any label
```yaml
apiVersion: v1
kind: Pod
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
```

Create the new pod

    kubectl create -f nginx-pod.yaml

    kubectl get pods
    NAME                    READY     STATUS    RESTARTS   AGE
    nginx                   1/1       Running   0          11s
    nginx-664452237-6h8zw   1/1       Running   0          16m
    nginx-664452237-kmmqk   1/1       Running   0          15m
    nginx-664452237-xhnjt   1/1       Running   0          16m

The just created new pod is not still associated to the nginx service

    kubectl get endpoints | grep nginx
    NAME         ENDPOINTS                                    AGE
    nginx        172.30.21.2:80,172.30.4.2:80,172.30.4.3:80   40m


Now, let's to lable the new pod with ``run=nginx`` label

    kubectl label pod nginx run=nginx
    pod "nginx" labeled

We can see a new endpoint is added to the service

    kubectl get endpoints | grep nginx
    NAME         ENDPOINTS                                                AGE
    nginx        172.30.21.2:80,172.30.4.2:80,172.30.4.3:80 + 1 more...   46m

Any pod in the cluster need for the nginx service will be able to talk with this service by the service address no matter which IP address will be assigned to the nginx pod. Also, in case of multiple nginx pods, the service abstraction acts as load balancer between the nginx pods.

Create a pod from the following yaml file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
    name: busybox
  restartPolicy: Always
```

We'll use this pod to address the nginx service

    kubectl create -f busybox.yaml
    pod "busybox" created

    kubectl exec -it busybox sh
    / # wget -O - 10.254.60.24:8000
    Connecting to 10.254.60.24:8000 (10.254.60.24:8000)
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    </head>
    <body>
    <h1>Welcome to nginx!</h1>
    <p>If you see this page, the nginx web server is successfully installed and
    working. Further configuration is required.</p>
    ...
    </body>
    </html>
    / # exit
    

In kubernetes, the service abstraction acts as stable entrypoint for any application, no matter wich is the IP address of the pod(s) running that application. We can destroy all nginx pods and recreate but service will be always the same IP address and port.

## Volumes
Containers are ephemeral, meaning the container file system only lives as long as the container does. If the application state needs to survive relocation, reboot, and crash of the hosting pod, we need to use some persistent storage mechanism. Kubernetes - as docker does, uses the concept of data volume.  A kubernetes volume has an explicit lifetime, the same as the pod that encloses it. Data stored in a kubernetes volume survive across relocation, reboot, restart and crash of the hosting pod.

In this section, we are going to create two different volume types:

  1. **emptyDir**
  2. **hostPath**

However, kubernetes supports more other volume types. Please, refer to official documentation for details.

### Empty Dir Volume
Here a simple example file ``nginx-volume.yaml`` of nginx pod containing a data volume
```yaml
apiVersion: v1
kind: Pod
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
    volumeMounts:
    - name: content-data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: content-data
    emptyDir: {}
```

The file defines an nginx pod where the served html content directory ``/usr/share/nginx/html`` is mounted as volume. The volume type is ``emptyDir``. This type of volume is created when the pod is assigned to a node, and it exists as long as that pod is running on that node. As the name says, it is initially empty. When the pod is removed from the node for any reason, the data in the emptyDir volume is deleted too.

The Empty Dir volumes are placed on the ``/var/lib/kubelet/pods/POD_UID/volumes/kubernetes.io~empty-dir/`` of the worker node where the pod is currently running. Please, note that a container crash does not remove a pod from a node, so the data in an emptyDir volume is safe across a container crash.

Create the nginx pod above

    kubectl create -f nginx-volume.yaml
    pod "nginx" created
    
    kubectl get po/nginx
    NAME      READY     STATUS    RESTARTS   AGE
    nginx     1/1       Running   0          22s

Check for pod IP address and for the worker node hosting the pod

    kubectl get po/nginx -o wide
    NAME      READY     STATUS    RESTARTS   AGE       IP            NODE
    nginx     1/1       Running   0          13m       10.38.3.167   kubew03

Trying to access the nginx application

     curl 10.38.3.167
     403 Forbidden

we get *forbidden* since the html content dir (mounted as volume) is initially empty.

Login to the worker node and populate the volume dir with an html file

    [root@kubew03 ~]# cd /var/lib/kubelet/pods/<POD_UID>/volumes/kubernetes.io~empty-dir/content-data
    echo "Hello World from " $(pwd) > index.html

Now we should be able to get an answer from the pod

    curl 10.38.3.167
    Hello World from /var/lib/kubelet/pods/<POD_UID>/volumes/kubernetes.io~empty-dir/content-data

With the ``emptyDir`` volume type, data in the volume is removed when the pod is deleted from the node where it was running. To achieve data persistence across pod deletion or relocation, we need for a persistent shared storage alternative.

As alternative to put data in an empty dir of the local disk, we can put data on a tmpfs filesystem, i.e. in memory instead of on disk. To do this, set the ``emptyDir`` medium to ``Memory`` like in this snippet

```
...
volumes:
  - name: html
emptyDir:
      medium: Memory
...
```

### Host Path Volume
The other volume type we're gooing to use is ``hostPath``. With this volume type, the volume is mount from an existing directory on the file system of the node hosting the pod. Data inside the host directory are safe to container crashes and restarts as well as to pod deletion. However, if the pod is moved from a node to another one, data on the initial node are no more accessible from the new instance of the pod.

Based on the previous example, define a nginx pod using the host dir ``/mnt`` as data volume for html content
```yaml
apiVersion: v1
kind: Pod
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
    volumeMounts:
    - name: content-data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: content-data
    hostPath:
      path: /mnt
```

Please, note that host dir ``/mnt`` must be present on the node hosting the pod before the pod is created by kubernetes.

Schedule the pod

    kubectl create -f nginx-host-volume.yaml
    pod "nginx" created
    
    kubectl get pod nginx
    NAME      READY     STATUS    RESTARTS   AGE
    nginx     1/1       Running   0          3m

Check for pod IP address and try to access the nginx application

    kubectl get po/nginx -o yaml | grep podIP
    podIP: 172.30.41.7
    
    curl 172.30.41.7:80
    403 Forbidden

we get *forbidden* since the html content dir (mounted as volume on the host node) is initially empty.

Login to the host node pod populate the volume dir

    echo "Hello from $(hostname)"  > /mnt/index.html

Back to the master node and access the service

    curl 172.30.41.7:80
    Hello from kubew05

Data in host dir volume will survive to any crash and restart of both container and pod. To test this, delete the pod and create it again

    kubectl delete pod nginx
    pod "nginx" deleted

    kubectl create -f nginx-host-volume.yaml
    pod "nginx" created

    kubectl get po/nginx -o yaml | grep podIP
      podIP: 172.30.41.7

    curl 172.30.41.7:80
    Hello from kubew05

This works only when kubernetes schedules the nginx pod on the same worker node as before.

## Config Maps
Kubernetes allows separating configuration options into a separate object called **ConfigMap**, which is a map containing key/value pairs with the values ranging from short literals to full config files. An application doesn’t need to read the ConfigMap directly or even know that it exists. The contents of the map are instead passed to containers as either environment variables or as files in a volume.

### Mount Config Map as volume
The content of config Map is mounted as a volume into the pod. For example, let's to create a Config Map from the ``nginx.conf`` configuration file

    kubectl create configmap nginx --from-file=nginx.conf

Define now a nginx pod mounting the config map above as volume under the ``/etc/nginx/conf.d`` as in the ``nginx-pod-cm.yaml`` manifest file

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace:
  labels:
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
      - name: config
        mountPath: /etc/nginx/conf.d
        readOnly: true
  volumes:
    - name: config
      configMap:
        name: nginx
```

Create the pod

    kubectl create -f nginx-pod-cm.yaml

Check if the pod just created mounted the Config Map as its default configuration file

    kubectl exec nginx cat /etc/nginx/conf.d/nginx.conf

As alternative, a Config Map can be created as in the ``nginx-conf.yaml`` manifest file

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx
  namespace:
data:
  nginx.conf: |
    server {
        listen       80;
        server_name  www.noverit.com;
        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
    }
```

Using a Config Map and exposing it through a volume brings the ability to update the configuration without having to recreate the pod or even restart the container. When updating a Config Map, the files in all the volumes referencing it are updated. It’s then up to the process to detect that they’ve been changed and reload them.

For example, to update the configuration above, edit the Config Map

    kubectl edit cm nginx

Then check the nginx application running inside the pod reloaded the configuration

    kubectl exec nginx cat /etc/nginx/conf.d/nginx.conf

In the previous example, we mounted the volume as a directory, which means any file that is stored in the ``/etc/nginx/conf.d`` directory in the container image is hidden. This is generally what happens in Linux when mounting a filesystem into a directory and the directory then only contains the files from the mounted filesystem, whereas the original files are inaccessible.

To avoid this pitfall, in kubernetes, it is possible to mount only individual files from a Config Map into an existing directory without hiding existing files stored on that directory. For example, as reference to the previous example, the ``/etc/nginx/conf.d`` directory of the container file system, already contains a default configuration file called ``default.conf``. We do not want to hide this file but we only want to add an additional configuration file called ``custom.conf`` for our customized nginx container.

Create a Config Map as in the following ``nginx-custom.conf`` file descriptor

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx
  namespace:
data:
  custom.conf: |
    server {
        listen       8080;
        server_name  www.noverit.com;
        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
    }
```

and then create the nginx pod from the following ``nginx-pod-cm-custom.yaml`` file descriptor

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace:
  labels:
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 8080
    volumeMounts:
      - name: config
        mountPath: /etc/nginx/conf.d/custom.conf
        subPath: custom.conf
        readOnly: true
  volumes:
    - name: config
      configMap:
        name: nginx
```

The resulting pod will mount the both the default and custom configuration files

    kubectl exec nginx -- ls -lrt /etc/nginx/conf.d/
    total 8
    -rw-r--r-- 1 root root 1093 Sep 25 15:04 default.conf
    -rw-r--r-- 1 root root  166 Sep 27 11:45 custom.conf

*Please, note that when mounting a single file in the container, and the config map changes, the file will not be updated.*

### Pass Config Map by environment variables
In addition to mounting a volume, configuration values contained into a Config Map can be passed to a container directly into environment variables. For example, the following ``mysql-cmk.yaml`` file defines a Config Map containing configuration paramenters for a MySQL application

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql
  namespace:
data:
  MYSQL_RANDOM_ROOT_PASSWORD: "yes"
  MYSQL_DATABASE: "employees"
  MYSQL_USER: "admin"
  MYSQL_PASSWORD: "password"
```

The following ``mysql-pod-cmk.yaml`` file defines the MySQL pod using the values from the map above

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql
  namespace:
  labels:
    run: mysql
spec:
  containers:
  - name: mysql
    image: mysql:5.6
    env:
    - name: MYSQL_RANDOM_ROOT_PASSWORD
      # The generated root password will be printed to stdout
      # kubectl logs mysql | grep GENERATED
      valueFrom:
        configMapKeyRef:
          name: mysql
          key: random_root_password
    - name: MYSQL_DATABASE
      valueFrom:
        configMapKeyRef:
          name: mysql
          key: database
    - name: MYSQL_USER
      valueFrom:
        configMapKeyRef:
          name: mysql
          key: user
    - name: MYSQL_PASSWORD
      valueFrom:
        configMapKeyRef:
          name: mysql
          key: password
    ports:
    - name: mysql
      protocol: TCP
      containerPort: 3306
```

Create the config map

    kubectl apply -f mysql-cmk.yaml

and create the MySQL pod

    kubectl apply -f mysql-pod-cmk.yaml

To check the configurations are correctly loaded from the map, try to connect the MySQL with the defined user and password.

When the Config Map contains more than just a few entries, it becomes tedious to create environment variables from each entry individually. It is also possible to expose all entries of a Config Map as environment variables without specifying them in the pod descriptor. For example the following ``mysql-pod-cmx.yaml`` is a more compact form of the descriptor above

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql
  namespace:
  labels:
    run: mysql
spec:
  containers:
  - name: mysql
    image: mysql:5.6
    envFrom:
    - configMapRef:
        name: mysql
    ports:
    - name: mysql
      protocol: TCP
      containerPort: 3306
```

## Secrets
In addition to regular, not sensitive configuration data, sometimes we need to pass sensitive information, such as credentials, tokens and private encryption keys, which need to be kept secure. For these use cases, kubernetes provides Secrets. Secrets are kept safe by distributing them only to the nodes that run the pods that need access to the secrets. Also, on the nodes, secrets are always stored in memory and never written to the disk. On the master node, secrets are stored in encrypted form into the etcd database.

Secrets as for the Config Maps can be passed to containers by mounting a volume or via environment variables. For example, the following ``mysql-secret.yaml`` file descriptor defines a secret to pass the user's credentials

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql
  namespace:
data:
  MYSQL_RANDOM_ROOT_PASSWORD: eWVz
  MYSQL_DATABASE: ZW1wbG95ZWVz
  MYSQL_USER: YWRtaW4=
  MYSQL_PASSWORD: cGFzc3dvcmQ=
```

In a secret data are base64 encoded as

    $ echo -n "admin" | base64
    YWRtaW4=
    $ echo -n "password" | base64
    cGFzc3dvcmQ=
    ...

Data can be passed via environment variables to the MySQL server as defined in the following ``mysql-pod-secret.yaml`` descriptor file

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql
  namespace:
  labels:
    run: mysql
spec:
  containers:
  - name: mysql
    image: mysql:5.6
    envFrom:
    - secretRef:
        name: mysql
    ports:
    - name: mysql
      protocol: TCP
      containerPort: 3306
```

## Daemons
A Daemon Set is a controller type ensuring each node in the cluster runs a pod. As new node is added to the cluster, a new pod is added to the node. As the node is removed from the cluster, the pod running on it is removed and not scheduled on another node. Deleting a Daemon Set will clean up all the pods it created.

The configuration file ``nginx-daemon-set.yaml`` defines a daemon set for the nginx application
```yaml
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  labels:
    run: nginx
  name: nginx-ds
  namespace:
spec:
  selector:
    matchLabels:
      run: nginx-ds
  template:
    metadata:
      labels:
        run: nginx-ds
    spec:
      containers:
      - image: nginx:latest
        imagePullPolicy: Always
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
```

Create the daemon set and get information about id 

    kubectl create -f nginx-daemon-set.yaml
    
    kubectl get ds nginx-ds -o wide
    NAME     DESIRED CURRENT READY UP-TO-DATE AVAILABLE NODE-SELECTOR  AGE CONTAINER(S) IMAGE(S)     SELECTOR
    nginx-ds 3       3       3     3          3         <none>         4m  nginx        nginx:latest run=nginx-ds

There are exactly three pods since we have three nodes

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-ds-b9rnc           1/1       Running   0          7m        10.38.0.20   kubew05
    nginx-ds-k5898           1/1       Running   0          7m        10.38.1.25   kubew04
    nginx-ds-nfr32           1/1       Running   0          7m        10.38.2.17   kubew03

and each pod is running on a different node.

Trying to delete a node from the cluster, the running pod on it is removed and not scheduled on other nodes as happens with other types of controllers

    kubectl delete node kubew03

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-ds-b9rnc           1/1       Running   0          7m        10.38.0.20   kubew05
    nginx-ds-k5898           1/1       Running   0          7m        10.38.1.25   kubew04

Adding back the node to the cluster, we can see a new pod scheduled on that node.

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-ds-b9rnc           1/1       Running   0          7m        10.38.0.20   kubew05
    nginx-ds-k5898           1/1       Running   0          7m        10.38.1.25   kubew04
    nginx-ds-61swl           1/1       Running   0          3s        10.38.2.18   kubew03

To delete a daemon set

    kubectl delete ds nginx-ds

A daemon set object is not controlled by the kubernetes scheduler since there is only a pod for each node. As a test, login to the master node and stop the scheduler

    systemctl stop kube-scheduler

Now create the daemon set

    kubectl create -f nginx-daemon-set.yaml

We can see pods scheduled on each node

    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-ds-b9rnc           1/1       Running   0          7m        10.38.0.20   kubew05
    nginx-ds-k5898           1/1       Running   0          7m        10.38.1.25   kubew04
    nginx-ds-nfr32           1/1       Running   0          7m        10.38.2.17   kubew03
    
It is possible to esclude some nodes from the daemon set by forcing the node selector. For example to run a nginx pod only on the ``worker03`` node, set the node selecto in the ``nginx-daemon-set.yaml`` configuration file above

```yaml
...
    spec:
      containers:
      - image: nginx:latest
        imagePullPolicy: Always
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
...
      nodeSelector:
        kubernetes.io/hostname: kubew03

```

Create the new daemon set and cjeck the pods running on the nodes

    kubectl create -f nginx-daemon-set.yaml
    
    kubectl get pods -o wide
    NAME                     READY     STATUS    RESTARTS   AGE       IP           NODE
    nginx-ds-vwm8w           1/1       Running   0          2m        10.38.2.20   kubew03

## Jobs
In kubernetes, a **Job** is an abstraction for create batch processes. A job creates one or more pods and ensures that a given number of them successfully complete. When all pod complete, the job itself is complete. 

For example, the ``hello-job.yaml`` file defines a set of 16 pods each one printing a simple greating message on the standard output. In our case, up to 4 pods can be executed in parallel 
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: simplejob
spec:
  completions: 16
  parallelism: 4
  template:
    metadata:
      name: hello
    spec:
      containers:
      - name: hello
        image: busybox
        imagePullPolicy: IfNotPresent
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        args:
        - /bin/sh
        - -c
        - echo Hello from $(POD_NAME)
      restartPolicy: OnFailure
```

Create the job

    kubectl create -f hello-job.yaml

and check the pods it creates

    kubectl get pods -o wide -a
    NAME                           READY     STATUS              RESTARTS   AGE       IP           NODE
    simplejob-4729j                0/1       Completed           0          14m       10.38.3.83   kubew03
    simplejob-5rsbt                0/1       Completed           0          14m       10.38.5.60   kubew05
    simplejob-78jkn                0/1       Completed           0          15m       10.38.4.53   kubew04
    simplejob-78jhx                0/1       Completed           0          15m       10.38.4.51   kubew04
    simplejob-469wk                0/1       ContainerCreating   0          3s        <none>       kubew03
    simplejob-9gnfp                0/1       ContainerCreating   0          3s        <none>       kubew03
    simplejob-wrpzp                0/1       ContainerCreating   0          3s        <none>       kubew05
    simplejob-xw5qz                0/1       ContainerCreating   0          3s        <none>       kubew05

After printing the message, each pod completes.

Check the job status

    kubectl get jobs -o wide
    NAME           DESIRED   SUCCESSFUL   AGE       CONTAINERS   IMAGES    SELECTOR
    simplejob      16         4           2m        hello        busybox 

Deleting a job will remove all the pods it created

    kubectl delete job simplejob
    kubectl get pods -o wide -a

## Cron Jobs
In kubernetes, a **Cron Job** is a time based managed job. A cron job runs a job periodically on a given schedule, written in standard unix cron format.

For example, the ``date-cronjob.yaml`` file defines a cron job to print, every minute, the current date and time on the standard output
apiVersion: batch/v1beta1
```yaml
kind: CronJob
metadata:
  name: currentdate
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: date
            image: busybox
            imagePullPolicy: IfNotPresent
            args:
            - /bin/sh
            - -c
            - echo "Current date is"; date
          restartPolicy: OnFailure
```

Create the cron job

    kubectl create -f date-cronjob.yaml

and check the pod it creates

    kubectl get pods -o wide -a
    NAME                           READY     STATUS      RESTARTS   AGE       IP            NODE
    currentdate-1508917200-j8vl9   0/1       Completed   0          2m        10.38.3.127   kubew03
    currentdate-1508917260-qg9zn   1/1       Running     0          1m        10.38.5.98    kubew05

Every minute, a new pod is created. When the pod completes, its parent job completes and a new job is scheduled

    kubectl get jobs -o wide
    NAME                     DESIRED   SUCCESSFUL   AGE       CONTAINERS   IMAGES    SELECTOR
    currentdate-1508917200   1         1            2m        date         busybox   
    currentdate-1508917260   1         1            1m        date         busybox  
    currentdate-1508917320   1         1            31s       date         busybox   

    kubectl get cronjob
    NAME          SCHEDULE      SUSPEND   ACTIVE    LAST SCHEDULE   AGE
    currentdate   */1 * * * *   False     1         Wed, 25 Oct 2017 09:46:00 +0200

## Namespaces
Kubernetes supports multiple virtual clusters backed by the same physical cluster. These virtual clusters are called namespaces. Within the same namespace, kubernetes objects name should be unique. Different objects in different namespaces may have the same name.

Kubernetes comes with two initial namespaces

  * **default**: the default namespace for objects with no other namespace
  * **kube-system** the namespace for objects created by the kubernetes system

To get namespaces

    kubectl get namespaces
    NAME          STATUS    AGE
    default       Active    7d
    kube-system   Active    7d


To see objects belonging to a specific namespace

    kubectl get all --namespace default

    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   2         2         2            2           52s
    NAME             CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
    svc/kubernetes   10.254.0.1     <none>        443/TCP          7d
    svc/nginx        10.254.33.40   <nodes>       8081:31000/TCP   51s
    NAME                  DESIRED   CURRENT   READY     AGE
    rs/nginx-2480045907   2         2         2         52s
    NAME                        READY     STATUS    RESTARTS   AGE
    po/nginx-2480045907-56t21   1/1       Running   0          52s
    po/nginx-2480045907-8n2t5   1/1       Running   0          52s

or objects belonging to all namespaces

    kubectl get service --all-namespaces
    NAMESPACE     NAME                   CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
    default       kubernetes             10.254.0.1       <none>        443/TCP          7d
    default       nginx                  10.254.33.40     <nodes>       8081:31000/TCP   2m
    kube-system   kube-dns               10.254.3.100     <none>        53/UDP,53/TCP    3d
    kube-system   kubernetes-dashboard   10.254.180.188   <none>        80/TCP           1d

Please, note that not all kubernetes objects are in namespaces, i.e. nodes, are cluster resources not included in any namespaces.

Define a new project namespace from the ``projectone-ns.yaml`` configuration file
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: projectone
```

Create the new namespace

    kubectl create -f projectone-ns.yaml
    namespace "projectone" created

    kubectl get ns project-one
    NAME          STATUS    AGE
    projectone   Active    6s

Objects can be assigned to a specific namespace in an explicit way, by setting the namespace in the metadata. For example, to create a nginx pod inside the project-one namespace, force the namespace in the pod definition file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: projectone
  labels:
    run: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

Create the nginx pod and check it lives only in the project-one namespace

    kubectl create -f nginx-pod.yaml
    pod "nginx" created

    kubectl get pod nginx -n projectone
    NAME      READY     STATUS    RESTARTS   AGE
    nginx     1/1       Running   0          51s

    kubectl get pod nginx
    Error from server (NotFound): pods "nginx" not found

Deleteing a namespace, will delete all the objects living in that namespaces. For example

    kubectl delete ns projectone
    namespace "projectone" deleted

    kubectl get pod  --all-namespaces

Another way to create object in namespaces is to force the desired namespace into the contest of *kubectl* command line. The kubectl is the client interface to interact with a kubernetes cluster. The contest of kubectl is specified into the ``~.kube/conf`` kubeconfig file. The contest defines the namespace as well as the cluster and the user accessing the resources.

See the kubeconfig file use the ``kubectl config view`` command

```yaml
  apiVersion: v1
    clusters:
    - cluster:
        server: http://kube00:8080
      name: musa-cluster
    contexts:
    - context:
        cluster: musa-cluster
        namespace: default
        user: admin
      name: default-context
    current-context: default-context
    kind: Config
    preferences: {}
    users:
    - name: admin
      user: {}    
```   
    
The file above defines a default-context operating on the musa-cluster as admin user. All objects created in this contest will be in the default namespace unless specified. We can add more contexts to use different namespaces and switch between contexts.

Create a new contest using the projectone namespace we defined above

    kubectl config set-credentials admin
    kubectl config set-cluster musa-cluster --server=http://kube00:8080
    kubectl config set-context projectone/musa-cluster/admin --cluster=musa-cluster --user=admin
    kubectl config set contexts.projectone/musa-cluster/admin.namespace projectone

The kubeconfig file now looks like
```yaml
apiVersion: v1
clusters:
- cluster:
    server: http://kube00:8080
  name: musa-cluster
contexts:
- context:
    cluster: musa-cluster
    namespace: default
    user: admin
  name: default-context
- context:
    cluster: musa-cluster
    namespace: projectone
    user: admin
  name: projectone/musa-cluster/admin
current-context: default-context
kind: Config
preferences: {}
users:
- name: admin
  user: {}
```

It is not strictly required but it is a convention to use the name of contests as ``<namespace>/<cluster>/<user>`` combination. To switch contest use

    kubectl config use-context projectone/musa-cluster/admin
    Switched to context "projectone/musa-cluster/admin".

    kubectl config current-context
    projectone/musa-cluster/admin

Starting from this point, all objects will be created in the projectone namespace.

Switch back to default context

    kubectl config use-context default-context
    Switched to context "default-context".

## Quotas and Limits
Namespaces let different users or teams to share a cluster with a fixed number of nodes. It can be a concern that one team could use more than its fair share of resources. Resource quotas are the tool to address this concern. 

A resource quota provides constraints that limit aggregate resource consumption per namespace. It can limit the quantity of objects that can be created in a namespace by type, as well as the total amount of compute resources that may be consumed in that project.

Users create resources in the namespace, and the quota system tracks usage to ensure it does not exceed hard resource limits defined in the resource quota. If creating or updating a resource violates a quota constraint, the request will fail. When quota is enabled in a namespace for compute resources like cpu and memory, users must specify resources consumption, otherwise the quota system rejects pod creation.

Define a resource quota ``quota.yaml`` configuration file to assign constraints to current namespace
```yaml
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: project-quota
spec:
  hard:
    limits.memory: 1Gi
    limits.cpu: 1
    pods: 10
```

Create quota and check the current namespace

    kubectl config current-context
    projectone/musa-cluster/admin

    kubectl create -f quota.yaml
    resourcequota "project-quota" created

    kubectl describe ns projectone
    Name:   projectone
    Labels: type=project
    Status: Active

    Resource Quotas
     Name:          project-quota
     Resource       Used    Hard
     --------       ---     ---
     limits.cpu     0       1
     limits.memory  0       1Gi
     pods           0       10

    No resource limits.

Current namespace has now hard constraints set to 1 core CPU, 1 GB of RAM and max 10 running pods. Having set constraints for the namespace, all further requests for pod creation inside that namespace, must specify resources consumption, otherwise the quota system will reject the pod creation. 

Trying to create a nginx pod

    kubectl create -f nginx-pod.yaml
    Error from server (Forbidden) ..

The reason is that, by default, a pod try to allocate all the CPU and memory available in the system. Since we have limited cpu and memory consumption for the namespaces, the quota system cannot honorate a request for pod creation crossing these limits.

We can specify the resource contraint for a pod in its configuration file or in the ``nginx-deploy-limited.yaml`` configuration file
```yaml
...
    spec:
      containers:
      - image: nginx:latest
        resources:
          limits:
            cpu: 200m
            memory: 512Mi
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
...
```

and deploy the pod

    kubectl create -f nginx-deploy-limited.yaml
    deployment "nginx" created

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-3094295584-rsxns   1/1       Running   0          1m

The above pod can take up to 200 millicore of CPU, i.e. the 20% of total CPU resource quota of the namespace; it also can take up to 512 MB of memory, i.e. 50% of total memory resource quota.

So we can scale to 2 pod replicas

    kubectl scale deploy/nginx --replicas=2
    deployment "nginx" scaled

    kubectl get pods
    NAME                     READY     STATUS              RESTARTS   AGE
    nginx-3094295584-bxkln   0/1       ContainerCreating   0          3s
    nginx-3094295584-rsxns   1/1       Running             0          3m

At this point, we consumed all memory quotas we reserved for the namespace. Trying to scale further

    kubectl scale deploy/nginx --replicas=3
    deployment "nginx" scaled

    kubectl get pods
    NAME                     READY     STATUS    RESTARTS   AGE
    nginx-3094295584-bxkln   1/1       Running   0          2m
    nginx-3094295584-rsxns   1/1       Running   0          6m

    kubectl get all
    NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
    deploy/nginx   3         2         2            2           6m
    NAME                  DESIRED   CURRENT   READY     AGE
    rs/nginx-3094295584   3         2         2         6m
    NAME                        READY     STATUS    RESTARTS   AGE
    po/nginx-3094295584-bxkln   1/1       Running   0          3m
    po/nginx-3094295584-rsxns   1/1       Running   0          6m

we cannot get more than 2 containers running.

Quotas lets the cluster administrators to control the resource consumption within a shared cluster. However, a single namespace may be used by more than a single user and it may deploy more than an application. To avoid a single pod consumes all resource of a given namespace, kubernetes introduces the limit range object. The limit range object limits the resources that a pod can consume by specifying the minimum, maximum and default resource consumption.

The configuration file ``limitranges.yaml`` defines limits for all containers running in the current namespace
```yaml
---
kind: LimitRange
apiVersion: v1
metadata:
  name: container-limit-ranges
spec:
  limits:
  - type: Container
    max:
      cpu: 200m
      memory: 512Mi
    min:
      cpu:
      memory:
    default:
      cpu: 100m
      memory: 256Mi
```

Create the limit ranges object and inspect the namespace

    kubectl create -f limitranges.yaml
    limitrange "container-limit-ranges" created

    kubectl describe namespace projectone
    Name:   projectone
    Labels: type=project
    Status: Active

    Resource Quotas
     Name:          project-quota
     Resource       Used    Hard
     --------       ---     ---
     limits.cpu     0       1
     limits.memory  0       1Gi
     pods           0       10

    Resource Limits
     Type           Resource        Min     Max     Default Request Default Limit   Max Limit/Request Ratio
     ----           --------        ---     ---     --------------- -------------   -----------------------
     Container      memory          0       512Mi   256Mi           256Mi           -
     Container      cpu             0       200m    100m            100m            -

The current namespace defines limits for each container running in the namespace. If an user tryes to create a pod with a resource consumption more than limits range, the kubernetes scheduler will deny the request even if within the quota set.

Try to create a nginx pod as
```yaml
...
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      limits:
        cpu: 250m
        memory: 512Mi
    ports:
    - containerPort: 80
...
```

our request will be denied

    kubectl create -f nginx-limited-pod.yaml
    Error from server (Forbidden): error when creating "nginx-limited-pod.yaml":
    pods "nginx" is forbidden: maximum cpu usage per Container is 200m, but limit is 250m.

The default value we set into limit range definition above is used as default for all pods that do not specify resource consumption. So, if we create a nginx pod as follow
```yaml
...
  containers:
  - name: nginx
    image: nginx:latest
    resources:
    ports:
    - containerPort: 80
...
```

the pod will be created with the default resource consumption limits

    kubectl create -f nginx-limited-pod.yaml
    pod "nginx" created

    kubectl describe namespace projectone
    Name:   projectone
    Labels: type=project
    Status: Active

    Resource Quotas
     Name:          project-quota
     Resource       Used    Hard
     --------       ---     ---
     limits.cpu     100m    1
     limits.memory  256Mi   1Gi
     pods           1       10

    Resource Limits
     Type           Resource        Min     Max     Default Request Default Limit   Max Limit/Request Ratio
     ----           --------        ---     ---     --------------- -------------   -----------------------
     Container      cpu             0       200m    100m            100m            -
     Container      memory          0       512Mi   256Mi           256Mi           -

Just to recap, quota defines the total amount of resources within a namespace, while limit ranges define the resource usage for a single pod within the same namespace.

Overcommitting of resource is possible, i.e. it is possible to specify limits exceding the real resources on the cluster nodes. To check real resources and their allocation, describe the worker nodes

    kubectl get nodes

    NAME      STATUS    AGE
    kuben05   Ready     6d
    kuben06   Ready     6d

    kubectl describe node kuben06
    ...
    ExternalID:             kuben06
    Non-terminated Pods:    (3 in total)
      Namespace             Name                    CPU Requests    CPU Limits      Memory Requests Memory Limits
      ---------             ----                    ------------    ----------      --------------- -------------
      default               nginx                   0 (0%)          0 (0%)          0 (0%)          0 (0%)
      default               nginx-2480045907-8n2t5  0 (0%)          0 (0%)          0 (0%)          0 (0%)
      projectone            nginx                   100m (10%)      100m (10%)      256Mi (13%)     256Mi (13%)
    Allocated resources:
      (Total limits may be over 100 percent, i.e., overcommitted.
      CPU Requests  CPU Limits      Memory Requests Memory Limits
      ------------  ----------      --------------- -------------
      100m (10%)    100m (10%)      256Mi (13%)     256Mi (13%)
