# Static Pods
In kubernetes, regular pods are managed by the API Server, scheduled by the Scheduler and controlled by Controller Manager. At the opposite, static pods are managed directly by the kubelet running on a specific node, without the API server intervention. It does not have an associated controller and the kubelet itself controls it and restarts it when the pod crashes. Static pods are always bound to one kubelet daemon and always run on the same node with it.

For example, given a worker node, let's to create a nodejs application defined by ``nodejs-pod.yaml`` configuration file as a static pod running on that node
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nodejs
  namespace: default
  labels:
    app:nodejs
spec:
  containers:
  - name: nodejs
    image: kalise/nodejs-web-app:latest
    ports:
    - containerPort: 8080
```

Copy the pod configuration file on the worker node

    mkdir -p /etc/kubernetes/manifest
    cp nodejs-pod.yaml /etc/kubernetes/manifest

Configure the kubelet on the worker node to use the above directory as place for static pods by editing the systemd configuration file ``/etc/systemd/system/kubelet.service`` for kubelet
```
...
[Service]
ExecStart=/usr/bin/kubelet \
...
  --pod-manifest-path=/etc/kubernetes/manifest/
  --v=2

Restart=on-failure
RestartSec=5
...
```

Restart the kubelet daemon

    systemctl daemon-reload
    systemctl restart kubelet

By default, kubelet automatically creates a mirror pod on the API server for each static pod, so the pods are visible from API server but cannot be controlled

    kubectl get pods -o wide -n default
    NAME             READY     STATUS    RESTARTS   AGE       IP            NODE
    nodejs-kubew03   1/1       Running   0          30s       10.38.3.173   kubew03

Trying to delete that pod, the kubelet on the worker node automatically will recreate it

    kubectl delete pod nodejs-kubew03 -n default

    kubectl get pods -o wide -n default
    NAME             READY     STATUS    RESTARTS   AGE       IP            NODE
    nodejs-kubew03   1/1       Running   0          8s        10.38.3.173   kubew03

In some cases, it is useful to bound static pods to the worker node network address, as in the ``nodejs-pod-hostnet.yaml`` configuration file
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nodejs-hostnet
  namespace: default
  labels:
    app: nodejs
spec:
  containers:
  - name: nodejs
    image: kalise/nodejs-web-app:latest
    ports:
    - containerPort: 8080
  hostNetwork: true
```

Move that file in the worker node's manifest directory and restart the kubelet

    cp nodejs-pod-hostnet.yaml /etc/kubernetes/manifest
    systemctl restart kubelet

and check the mirror pods from the API server

    kubectl get pods -o wide -n default
    NAME                     READY     STATUS    RESTARTS   AGE       IP            NODE
    nodejs-hostnet-kubew03   1/1       Running   0          15s       10.10.10.83   kubew03
    nodejs-kubew03           1/1       Running   0          12m       10.38.3.173   kubew03


