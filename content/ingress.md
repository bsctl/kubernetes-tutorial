# Ingress
In kubernetes, user applications are made public by creating a service on a given port and a load balancer on top of the cluster for each application to expose. For example, a request for *myservice.mysite.com* will be balanced across worker nodes and then routed to the related service exposed on a given port by the kube proxy. An external load balancer is required for each service to expose. This can get rather expensive especially when done on a public cloud.

Ingress gives the cluster admin a different way to route requests to services by centralizing multiple services into a single external load balancer.

An ingress is split up into two main pieces: the first is an **Ingress Resource**, which defines how you want requests routed to the backing services. The second is an **Ingress Controller**, which listen to the kubernetes API for Ingress Resource creation and then handle requests that match them.

## Ingress Resource
An ingress resource is a kubernetes abstraction to handle requests, for example to *web.cloud.noverit.com* and then route them to the kubernetes services named web.

A file definition ``website-ingress.yaml`` for the Ingress resource above looks like the following

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: website
spec:
  rules:
  - host: web.cloud.noverit.com
    http:
      paths:
      - path: /
        backend:
          serviceName: website
          servicePort: 80
```

Before to create an Ingress, define a simple web server application listening on http port, as in the following ``website-rc.yaml`` configuration file

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: website
  namespace:
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: website
    spec:
      containers:
      - name: website
        image: centos/httpd:latest
        ports:
        - containerPort: 80
```

Then define an internal service pointing to the same application above, as in the ``website-svc.yaml`` configuration file
```yaml
apiVersion: v1
kind: Service
metadata:
  name: website
spec:
  type: ClusterIP
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    app: website
```

Please, note the service above is defined as type of ``ClusterIP`` and then it's not exposed directly to the external.

Create the application
```bash
kubectl create -f website-rc.yaml
kubectl create -f website-svc.yaml
```

Create the service
```bash
kubectl create -f website-svc.yaml
```

Create the ingress
```bash
kubectl create -f website-ingress.yaml
```

Check and inspect the ingress
```bash
kubectl get ingress -o wide
NAME          HOSTS                             ADDRESS   PORTS     AGE
website       web.cloud.noverit.com                       80        27m
```

However, an Ingress resource on it’s own does not do anything. An Ingress Controller is required to route requests to the service.

## Ingress Controller
The Ingress Controller is the component that routes the requests to the services. It is listening to the kubernetes API for an ingress creation and then handle requests.

Ingress Controllers can technically be any system capable of reverse proxying, but the most common options are Nginx and HAProxy. As additional component, a **Default Backend** service is created to handle all requests that are no service relates. This backend service will reply to all requests that are not related to our services, for example requests for unknown urls. The default backend will reply with a *Not Found (404)* error page. 

### Default Backend
Create the backend and related service from the file ``ingress-default-backend.yaml`` available [here](../examples/ingress/ingress-default-backend.yaml)
```bash
kubectl create -f ingress-default-backend.yaml
```

The template above, will create a replica controller and the related internal service in the ``kube-system`` namespace.
```bash
kubectl get all -l run=ingress-default-backend
NAME                               READY     STATUS    RESTARTS   AGE
po/ingress-default-backend-hd5pv   1/1       Running   0          1m

NAME                         DESIRED   CURRENT   READY     AGE
rc/ingress-default-backend   1         1         1         1m

NAME                          CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
svc/ingress-default-backend   10.32.156.148   <none>        8080/TCP   1m
```

Please, note that the ingress default backend service is an internal service ``type: ClusterIP`` and therefore, it is not exposed.

### Nginx as Ingress Controller
The Nginx application is capable to act as reverse proxy to route requests from an external load balancer directly to the pods providing the service. To configure an Nginx Ingress Controller, create an Nginx deploy form the ``nginx-ingress-controller-deploy.yaml`` available [here](../examples/ingress/nginx-ingress-controller-deploy.yaml).

Assuming we want to handle TLS requests, the Ingress Controller needs to have a default TLS certificate. This will be used for requests where is not specified TLS certificate. Assuming we have a certificate and key, ``tsl.crt`` and ``tsl.key``, respectively, create a secrets as follow
```bash
kubectl -n kube-system create secret tls tls-secret --key tls.key --cert tls.crt
```

Create the ingress controller
```bash
kubectl create -f nginx-ingress-controller-deploy.yaml
```
The file above, will deploy the ingress controller in the ``kube-system`` namespace.

Having already created the Ingress resource, the Ingress Controller is now able to forward requests from the kube proxy directly to the pods running your application
```bash
curl -i kubew03:30080 -H 'Host: web.cloud.noverit.com'

HTTP/1.1 200 OK
Date: Mon, 25 Sep 2017 00:11:37 GMT
Content-Type: text/plain
Transfer-Encoding: chunked
Server: echoserver
```

Unknown requests will be redirected to the default backend service
```bash
curl -i kubew03:30080 -H 'Host: foo.cloud.noverit.com'

HTTP/1.1 404 Not Found
Date: Mon, 25 Sep 2017 00:14:43 GMT
Content-Length: 21
Content-Type: text/plain; charset=utf-8
default backend - 404
```

An Ingress Controller can be deployed also as Daemon Set resulting an Nginx instance for each worker node in the cluster. The daemon set definition file ``nginx-ingress-controller-daemonset.yaml`` can be found [here](../examples/ingress/nginx-ingress-controller-daemonset.yaml). Remove the previous deploy and create the daemon set in the ``kube-system`` namespace
```bash
kubectl create -f nginx-ingress-controller-daemonset.yaml
```

Please, note the ingress controller is running as a host pod, meaning it is using the same network namespace of the host. This is achieved with the ``hostNetwork`` option in the pod template:
```yaml
    ...
    spec:
      hostNetwork: true
      containers:
      - ...
```

In practice, this means the ingress controller pod is listening on the IP address and port of the host machine.


### TLS Termination
An Ingress Controller is able to terminate secure TLS sessions and redirect requests to insecure HTTP applications running on the cluster. To configure TLS termination for user application, create a secret with certification and key in the user namespace pay attention to the **Common Name** used for the service.

For the web service
```
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout web-tls.key \
    -out web-tls.crt \
    -subj "/CN=web.cloud.noverit.com"

kubectl create secret tls web-tls-secret --cert=web-tls.crt --key=web-tls.key
```

Create a configuration file ``website-ingress-tls.yaml`` as ingress for TLS termination
```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: website-with-tls
spec:
  tls:
  - hosts:
    - web.cloud.noverit.com
    secretName: web-tls-secret
  rules:
  - host: web.cloud.noverit.com
    http:
      paths:
      - path: /
        backend:
          serviceName: website
          servicePort: 80
```

Create the ingress in the user namespace
```
kubectl create -f website-ingress-tls.yaml
```

Now the Ingress controller acts also as TLS terminator.
