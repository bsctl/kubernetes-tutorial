# Stateful Applications
Common controller as Replica Set and Daemon Set are a great way to run stateless applications on kubernetes, but their semantics are not so friendly for deploying stateful applications. A better approach for deploying stateful applications on a kubernetes cluster, is to use **Stateful Set**.

## Stateful Set
The purpose of Stateful Set is to provide a controller with the correct semantics for deploying stateful workloads. However, before move all in a converging storage and orchestration framework, one should consider with care to implement stateful applications in kubernetes.

A Stateful Set manages the deployment and scaling of a set of pods, and provides guarantees about the ordering and uniqueness of these pods. Like a Replica Set, a Stateful Set manages pods that are based on an identical container specifications. Unlike Replica Set, a Stateful Set maintains a sticky identity for each of pod across any rescheduling.

For a Stateful Set with n replicas, when pods are deployed, they are created sequentially, in order from {0..n-1} with a sticky, unique identity in the form ``<statefulset name>-<ordinal index>``. The (i)th pod is not created until the (i-1)th is running. This ensure a predictable order of pod creation. Deletion of pods in stateful set follows the inverse order from {n-1..0}. However, if the order of pod creation is not strictly required, it is possible to creat pods in parallel by setting the ``podManagementPolicy: Parallel`` option. A Stateful Set can be scaled up and down ensuring the same order of creation and deletion.

A stateful set requires an headless service to control the domain of its pods. The domain managed by this service takes the form ``$(service name).$(namespace).svc.cluster.local``.  As each pod is created, it gets a matching service name, taking the form ``$(podname).$(service)``, where the service is defined by the service name field on the Stateful Set. This leads to a predictable service name surviving to pod deletions and restarts.

## Deploy a Consul cluster
**Consul** is a distributed key-value store with service discovery. Consul is based on the **Raft** alghoritm for distributed consensus. Details about Consul and how to configure and use it can be found on the product documentation.

The most difficult part to run a Consul cluster on Kubernetes is how to form a cluster having Consul strict requirements about instance names of nodes being part of it. In this section we are going to deploy a three node Consul cluster by using the stateful set controller. This is only an example, and you can easily extend it to the distributed datastore of your choice like **MongoDB**, **RethinkDB** or **Cassandra**, just to name few.

### Prerequisites
We assume a persistent shared storage environment is available to the kubernetes cluster. This is because each Consul node uses a data directory where to store the status of the cluster and this directory needs to be preserved across pod deletions and restarts. A default storage class needs to be created before to try to implement this example.

### Bootstrap the cluster
First define a headless service for the Stateful Set as in the ``consul-svc.yaml`` configuration file
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: consul
  labels:
    app: consul
spec:
  ports:
  - name: rpc
    port: 8300
    targetPort: 8300
  - name: lan
    port: 8301
    targetPort: 8301
  - name: wan
    port: 8302
    targetPort: 8302
  - name: http
    port: 8500
    targetPort: 8500
  - name: dns
    targetPort: 8600
    port: 8600
  clusterIP: None
  selector:
    app: consul
```

Then define a Stateful Set for the Consul cluster as in the ``consul-sts.yaml`` configuration file
```yaml
apiVersion: apps/v1beta2
kind: StatefulSet
metadata:
  name: consul
  namespace:
  labels:
    type: statefulset
spec:
  serviceName: consul
  replicas: 3
  selector:
    matchLabels:
      app: consul
  template:
    metadata:
      labels:
        app: consul
    spec:
      initContainers:
      - name: consul-config-data
        image: busybox:latest
        imagePullPolicy: IfNotPresent
        command: ["/bin/sh", "-c", "cp /readonly/consul.json /config && sed -i s/default/$(POD_NAMESPACE)/g /config/consul.json"]
        env:
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
        volumeMounts:
        - name: readonly
          mountPath: /readonly
          readOnly: true
        - name: config
          mountPath: /config
          readOnly: false
      containers:
      - name: consul
        image: consul:1.0.2
        imagePullPolicy: IfNotPresent
        ports:
        - name: rpc
          containerPort: 8300
        - name: lan
          containerPort: 8301
        - name: wan
          containerPort: 8302
        - name: http
          containerPort: 8500
        - name: dns
          containerPort: 8600
        volumeMounts:
        - name: data
          mountPath: /consul/data
          readOnly: false
        - name: config
          mountPath: /consul/config
          readOnly: false
        args:
        - consul
        - agent
        - -config-file=/consul/config/consul.json
      volumes:
        - name: readonly
          configMap:
            name: consulconfig
        - name: config
          emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
      storageClassName: default
```

We notice the presence of an init container in the pod template in addition to the main Consul container. Both the containers, the init and the main container mount the same Consul configuration file in the form of the ConfigMap.

The role of the init container is to copy the configuration file from the ConfigMap (read only) to a shared volume (read write) and then update the file according to the namespace where that pod is running. This is accomplished by accessing the pod metadata by the API server running in the Kubernetes Control Plane. This step is required because the discoverability of each Consul instance depends on the namespace where the instance is running, i.e. Consul instances running in different namespaces are named differently.  

Create the headless service

    kubectl create -f consul-svc.yaml

    kubectl get svc -o wide
    NAME    TYPE       CLUSTER-IP EXTERNAL-IP PORT(S)                                        AGE  SELECTOR
    consul  ClusterIP  None       <none>      8300/TCP,8301/TCP,8302/TCP,8500/TCP,8600/TCP   25s  app=consul

The service above exposes all the ports of the Consul instances and makes each instance discoverable by its predictable hostname in the form of ``$(statefulset name)-$(ordinal).$(service name).$(namespace).svc.cluster.local``. Thanks to the above headless service, all Consul pods will get a discoverable hostname. The presence of headless service, ensure node discovery for the Consul cluster.

Before to create the StatefulSet for the Consul cluster, we’ll create a ConfigMap containing a Consul configuration file. The file  ``consul.json`` contains all the settings parameters required by Consul to form a cluster of three Consul instances.

```json
{
  "datacenter": "kubernetes",
  "log_level": "DEBUG",
  "data_dir": "/consul/data",
  "server": true,
  "bootstrap_expect": 3,
  "retry_join": ["consul-0.consul.default.svc.cluster.local","consul-1.consul.default.svc.cluster.local","consul-2.consul.default.svc.cluster.local"],
  "client_addr": "0.0.0.0",
  "bind_addr": "0.0.0.0",
  "domain": "cluster.local",
  "ui": true
}
```

Create the Config Map for Consul configuration file

    kubectl create configmap consulconfig --from-file=consul.json
    
Create the Stateful Set of three nodes

    kubectl create -f consul-sts.yaml

The Consul pods will be created in a strict order with a predictable name

    kubectl get pods -o wide
    NAME            READY     STATUS    RESTARTS   AGE       IP           NODE
    consul-0        1/1       Running   0          7m        10.38.5.95   kubew05
    consul-1        1/1       Running   0          6m        10.38.3.88   kubew03
    consul-2        1/1       Running   0          5m        10.38.5.96   kubew05

Each pod creates its own volume where to store its data

    kubectl get pvc
    NAME            STATUS    VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS 
    data-consul-0   Bound     pvc-7bf6c16e   2Gi        RWO            default 
    data-consul-1   Bound     pvc-951e3b17   2Gi        RWO            default
    data-consul-2   Bound     pvc-adfbf7ce   2Gi        RWO            default
    
Consul cluster should be formed

    kubectl exec -it consul-0 -- consul members
    Node      Address          Status  Type    Build  Protocol  DC          Segment
    consul-0  10.38.5.95:8301  alive   server  0.9.3  2         kubernetes  <all>
    consul-1  10.38.3.88:8301  alive   server  0.9.3  2         kubernetes  <all>
    consul-2  10.38.5.96:8301  alive   server  0.9.3  2         kubernetes  <all>

and ready to be used by any other pod in the kubernetes cluster.

Also each pod creates its own storage volume where to store its own copy of the distributed database

    kubectl get pvc
    NAME            STATUS    VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    data-consul-0   Bound     pvc-e975189c   2Gi        RWO            default        1h
    data-consul-1   Bound     pvc-02461605   2Gi        RWO            default        1h
    data-consul-2   Bound     pvc-1ac2d8d5   2Gi        RWO            default        1h


### Delete a pod
Now let’s to delete a pod 

    kubectl delete pod consul-1
    pod "consul-1" deleted

while checking its status progression

    kubectl get pod consul-1 -o wide --watch

    NAME       READY     STATUS           RESTARTS   AGE       IP          NODE
    consul-1   1/1       Running          0          1m        10.38.4.5   kubew04
    consul-1   1/1       Terminating      0          1m        10.38.4.5   kubew04
    consul-1   0/1       Pending          0          0s        <none>      kubew04
    consul-1   0/1       Init:0/1         0          0s        <none>      kubew04
    consul-1   0/1       PodInitializing  0          9s        10.38.4.6   kubew04
    consul-1   1/1       Running          0          12s       10.38.4.6   kubew04

As expected, a new pod is recreated with different IP address but with the same identity. Now check if the rescheduled pod is using the same previous storage volume

    kubectl describe pod consul-1
    ...
    Volumes:
      data:
        Type:       PersistentVolumeClaim
        ClaimName:  data-consul-1
        ReadOnly:   false
    ...

As you can see, the rescheduled pod is using the same PersistentVolumeClaim as the previous one. Please, remember that deleting a pod in a StatefulSet does not delete the PersistentVolumeClaims used by that pod. This preserves the data persistence across pod deletion and rescheduling.

### Access the cluster from pods
Create a simple curl shell in a pod from the ``curl.yaml`` file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: curl
  namespace:
spec:
  containers:
  - image: kalise/curl:latest
    command:
      - sleep
      - "3600"
    name: curl
  restartPolicy: Always
```

Attach to the curl shell, create and retrieve a key/value pair in the Consul cluster

    kubectl exec -it curl sh
    / # curl --request PUT --data my-data http://consul:8500/v1/kv/my-key
    true
    / # curl --request GET http://consul:8500/v1/kv/my-key
    [{"LockIndex":0,"Key":"my-key","Flags":0,"Value":"bXktZGF0YQ==","CreateIndex":336,"ModifyIndex":349}]
    / # exit

### Scaling the cluster
Scaling down a StatefulSet and then scaling it up is similar to deleting a pod and waiting for the StatefulSet to recreate it. Please, remember that scaling down a StatefulSet only deletes the pods, but leaves the PersistentVolumeClaims. Also, please, note that scaling down and scaling up is performed similar to how pods are created when the StatefulSet is created. When scaling down, the pod with the highest index is deleted first: only after that pod gets deleted, the pod with the second highest index is deleted, and so on.

What is the expected behaviour scaling up the Consul cluster? Since the Consul cluster is based on the Raft algorithm, we have to scale up our 3 nodes cluster by 2 nodes at same time because an odd number of nodes is always required to form a healthy Consul cluster. We also expect a new PersistentVolumeClaim is created for each new pod.

    kubectl scale sts consul --replicas=5
    statefulset "consul" scaled

By listing the pods, we see our Consul cluster gets scaled up.

    kubectl get pods -o wide

    NAME       READY     STATUS    RESTARTS   AGE       IP            NODE
    consul-0   1/1       Running   0          5m        10.38.3.160   kubew03
    consul-1   1/1       Running   0          5m        10.38.4.10    kubew04
    consul-2   1/1       Running   0          4m        10.38.5.132   kubew05
    consul-3   1/1       Running   0          1m        10.38.3.161   kubew03
    consul-4   1/1       Running   0          1m        10.38.4.11    kubew04

Check the membership of the scaled cluster

    kubectl exec -it consul-0 -- consul members
    Node      Address           Status  Type    Build  Protocol  DC          Segment
    consul-0  10.38.3.160:8301  alive   server  1.0.2  2         kubernetes  <all>
    consul-1  10.38.4.10:8301   alive   server  1.0.2  2         kubernetes  <all>
    consul-2  10.38.5.132:8301  alive   server  1.0.2  2         kubernetes  <all>
    consul-3  10.38.3.161:8301  alive   server  1.0.2  2         kubernetes  <all>
    consul-4  10.38.4.11:8301   alive   server  1.0.2  2         kubernetes  <all>

Also check the dynamic storage provisioner created the additional volumes

    kubectl get pvc -o wide

    NAME            STATUS    VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    data-consul-0   Bound     pvc-e975189c   2Gi        RWO            default        1h
    data-consul-1   Bound     pvc-02461605   2Gi        RWO            default        1h
    data-consul-2   Bound     pvc-1ac2d8d5   2Gi        RWO            default        1h
    data-consul-3   Bound     pvc-adaa4d2d   2Gi        RWO            default        1h
    data-consul-4   Bound     pvc-28feff1c   2Gi        RWO            default        1h

### Exposing the cluster
Consul provides a simple HTTP graphical interface on port 8500 for interact with it. To expose this interface to the external of the kubernetes cluster, define an service as in the ``consul-ui.yaml`` configuration file
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: consul-ui
  labels:
    app: consul
spec:
  type: ClusterIP
  ports:
  - name: ui
    port: 8500
    targetPort: 8500
  selector:
    app: consul
```

Assuming we have an Ingress Controller in place, define the ingress as in the ``consul-ingress.yaml`` configuration file
```yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: consul
spec:
  rules:
  - host: consul.cloud.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: consul-ui
          servicePort: 8500
```

Create the service and expose it

    kubectl create -f consul-ui.yaml
    kubectl create -f consul-ingress.yaml

Point the browser to the http://consul.cloud.example.com/ui to access the GUI.

### Cleanup everything
To delete the Consul cluster, delete the StatefulSet in cascade mode. This will delete both the StatefulSet objects and all pods. Please remember that the order of pods deletion will be from the pod having the highest index. Also you will have to delete the PersistentVolumeClaims and then all PersistentVolumes but only in case of static storage provisioning. In our case, since we used the dynamic storage provisioner, all the PersistentVolumes will be deleted or retained according to the reclaim policy specified in the Storage Class.

Remove every object create in the previous steps

    kubectl delete -f consul-ingress.yaml
    kubectl delete -f consul-svc-ext.yaml
    kubectl delete -f consul-sts.yaml
    kubectl delete -f consul-svc.yaml
    kubectl delete pvc data-consul-0 data-consul-1 data-consul-2
    kubectl delete configmap consulconfig
