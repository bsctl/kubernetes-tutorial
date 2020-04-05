# Advanced Scheduling
A reasonably sized microservices based application will consist of multiple containers. Containers, often, have dependencies among themselves, dependencies to the host, and resource requirements. The resources available on a cluster also can vary
over time. The way we place containers also impacts the availability, the performances, and the capacity of the distributed systems.

In Kubernetes, assigning pods to nodes is done by the scheduler. Generally, the users leave the scheduler to do its job without constraints. However, it might be required introduce a sort of forcing to the scheduler in order to achieve a better resource usage or meet some application's requirements. In this section, we're going to explore some of these use cases:

  * [Node Selectors](#node-selectors)
  * [Node Affinity](#node-affinity)
  * [Pods Affinity](#pods-affinity)
  * [Colocation](#colocation)
  * [Failure domains](#failure-domains)
  * [Taints and Tolerations](#taints-and-tolerations)
  

## Node Selectors
Node selector is the first ans simplest form of scheduler forcing. For example, having a pod that needs for special hardware to perform its work, we can force the scheduler to use that kind of nodes to run the pods. This is achieved by labeling all the node equipped with the special hardware with a proper label, e.g ``hpc=true``, and use this label as node selector in the following ``nginx-pod-node-selector.yaml`` descriptor

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-node-selector
  namespace:
  labels:
    run: nginx
spec:
  nodeSelector:
    hpc: true
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

## Node Affinity
The node affinity is a generalization of the node selector approach with a more expressive and flexible semantics than the node selector technique. Node affinity allows us to specify rules as either required or preferred: required rules must be met for a pod to be scheduled to a node, whereas preferred rules only imply preference for the matching the node.

For example, the following ``nginx-pod-node-affinity.yaml`` pod descriptor defines a node affinity with a required rule

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-node-affinity
  namespace:
  labels:
    app: nginx
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: datacenter
            operator: In
            values:
            - milano-dc-1
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

The rule above force the scheduler to place the pod only on nodes having a label set to ``datacenter=milano-dc-1``. However the rule does only affects pod scheduling and never causes a pod to be evicted from a node if such label is removed from the node. This is because we used the ``requiredDuringSchedulingIgnoredDuringExecution`` instead of the ``requiredDuringSchedulingRequiredDuringExecution``. In the latter case, removing the label from the node, the pod gets evicted from the node.

The following example ``nginx-pod-preferred-node-affinity.yaml``, is a pod descriptor which defines a node affinity with a preferred set of rules:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-preferred-node-affinity
  namespace:
  labels:
    app: nginx
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: hypervisor
            operator: In
            values:
            - esxi
      - weight: 2
        preference:
          matchExpressions:
          - key: hypervisor
            operator: In
            values:
            - kvm
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

The rule above defines a set of preferred rules based on the value of the ``hypervisor=esxi|kvm`` and setting a preference weight (higest is the preferred one).

## Pods Affinity
The node affinity rules are used to force which node a pod is scheduled to. But these rules only affect the affinity between a pod and a node, whereas sometimes we need to specify the affinity between pods themselves. In this case, the pod affinity technique is required. Having a multi services application made of a frontend and a backend service, does make sense to have the frontend pods running on the same worker node where the backend pods are running.

For example, the following ``wordpress-pod-affinity.yaml`` descriptor defines a required pod affinity rule

```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: wordpress
  namespace:
spec:
  replicas: 1
  selector:
    matchLabels:
      run: blog
  template:
    metadata:
      labels:
        run: blog
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                - key: run
                  operator: In
                  values:
                  - "mariadb"
              topologyKey: kubernetes.io/hostname
      containers:
      - image: bitnami/wordpress:latest
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
```

It will create a wordpress pod having a hard requirement to be deployed on the same node ``kubernetes.io/hostname`` as a pod running the database backend.

## Colocation
Another option provided by the affinity function is to force some pods to run in the same rack, zone, or region instead of the same node. Kubernetes nodes can be grouped into racks, zones and regions, then using proper labels and label selectors, it is possible to require pods running on the same rack, zone, or region.

For example, the following ``nginx-rs-colocate.yaml`` descriptor defines pods with hard requirement to be deployed in the same availability zone

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  labels:
  namespace:
  name: nginx
spec:
  replicas: 9
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: run
                operator: In
                values:
                  - nginx
            topologyKey: failure-domain.beta.kubernetes.io/zone
      containers:
      - image: nginx:latest
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
      restartPolicy: Always
```

The pod affinity rule above says pods are scheduled onto nodes in the same availability zone specified by ``failure-domain.beta.kubernetes.io/zone``. Please, note we are not specifying on which zone but we are only requiring pods to be colocated on the same zone.

The pod affinity rules can be combined with node affinity rules to have a more grained control on the pods placement. For example, we can combine the pods affinity above with a node affinity rule to have colocation of pods on a given zone.

## Failure domains
We have seen how to tell the scheduler to colocate pods on the same node, rack, zone or regions. In other cases, we want to have some pods running away each other, for example for balancing load on different availability zones, defining the so called *failure domains*. A failure domain is a single node, rack, zone or region that can fail at same time. For example, each availability zone can be defined as a single failure domain because of network issues. In case of network issues, all nodes in the same zone might remain unreachable. For this reason we can require to distribute pod replicas in different failure domains, i.e. zones in our example.

This is achieved with the anti-affinity rules. The following ``nginx-rs-fd.yaml`` descriptor requires pods replicas to be scheduled on separate availability zones

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  labels:
  namespace:
  name: nginx
spec:
  replicas: 4
  selector:
    matchLabels:
      run: nginx
  template:
    metadata:
      labels:
        run: nginx
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: run
                  operator: In
                  values:
                    - nginx
              topologyKey: failure-domain.beta.kubernetes.io/zone
      containers:
      - image: nginx:latest
        imagePullPolicy: Always
        name: nginx
        ports:
        - containerPort: 80
          protocol: TCP
      restartPolicy: Always
```

## Taints and Tolerations
While affinity and anti-affinity allow pods to choose nodes and or other pods, taints and tolerations allow the nodes to control which pods should or should not be scheduled on them.

A taint is a property of the node that prevents pods to be scheduled on that node unless the pod has a toleration for the taint. For example, we can use taints to prevent production nodes to never run not-production pods:

    kubectl taint node kubew03 node-type=production:NoSchedule

This means that no pods will be able to schedule onto the node unless it has a matching toleration for that taint.

The following ``nginx-pod-taint-toleration.yaml`` descriptor defines a pod with toleration for the taint above

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace:
  labels:
spec:
  tolerations:
  - key: node-type
    operator: Equal
    value: "production"
    effect: NoSchedule
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

To remove taint from the node

    kubectl taint node kubew03 node-type:NoSchedule-

Taints on a node defines three different effects:

  1. **NoSchedule**: pod will not be scheduled on the node unless it tolerates the taint.
  2. **PreferNoSchedule**: scheduler will try to avoid the pod placed onto the node, but pod will be placed ont the node if not possible to place it somewhere else.
  3. **NoExecute**: unlike the previous effects that only affect scheduling, this also affects pods already running on the node. Pods that are already running on the node and do not tolerate the taint will be evicted from the node and no other pods will be placed on the node unless they tolerate the taint.
  
A special usage of taint and toleration is the taint based eviction: the node controller automatically taints a node when certain conditions are true:

  * node.kubernetes.io/not-ready: Node is not ready.
  * node.kubernetes.io/unreachable: Node is unreachable from the node controller.
  * node.kubernetes.io/out-of-disk: Node becomes out of disk.
  * node.kubernetes.io/memory-pressure: Node has memory pressure.
  * node.kubernetes.io/disk-pressure: Node has disk pressure.
  * node.kubernetes.io/network-unavailable: Node network is unavailable.
  * node.kubernetes.io/unschedulable: Node is unschedulable.
  * node.cloudprovider.kubernetes.io/uninitialized: Node is not initialized yet.

The operator can specify the toleration timeout for these taints

```yaml
...
spec:
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
  - effect: NoExecute
    key: node.kubernetes.io/unreachable
    operator: Exists
    tolerationSeconds: 300
...
```

When the controller detects that a node is no longer ready or no longer reachable, will wait for 300 seconds before it deletes the pod and reschedules it to another node. The two tolerations above are automatically added to pods that do not define them.
