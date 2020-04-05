# System Architecture
Kubernetes is an open-source platform for automating deployment, scaling, and operations of application containers across a cluster of hosts. With Kubernetes, you are able to quickly and efficiently respond to customer demand:

  * Deploy your applications quickly and predictably.
  * Scale your applications on the fly.
  * Seamlessly roll out new features.
  * Optimize use of your hardware by using only the resources you need

A Kubernetes system is made of many nodes (both physical or virtual hosts) forming a cluster. A node in the cluster has a role. There are master(s) and workers nodes. Master(s) run the Control Plane and workers run user applications. Multiple masters are used for High Availability of the control plane.

Here a picture about Kubernetes Architecture:

![](../img/architecture.jpg?raw=true)

Main components of a Kubernetes cluster are:

   * [etcd](#etcd)
   * [API Server](#api-server)
   * [Controller Manager](#controller-manager)
   * [Scheduler](#scheduler)
   * [Agent](#agent)
   * [Proxy](#proxy)
   * [CLI](#command-line-client)
    
## etcd
The etcd component is a distributed key/value database using the Raft consensus alghoritm. It is used as Kubernetes’ backing store. All cluster data is stored here.

It runs on the master(s).
It requires port 2380 for listening peers requests and port 2379 for clients requests.

## API Server
The kube-apiserver exposes the Kubernetes API in a REST fashion. It is the front-end for the Kubernetes control plane. Both the humans and machines users interact with the system via the API Server component.

It runs on the master(s).
It binds on port 6443 for listening secure communications and port 8080 for the insecure.

## Controller Manager
The kube-controller-manager is a binary that runs controllers, which are the background threads that handle routine tasks in the cluster. These controllers include:

  * Node Controller: Responsible for noticing & responding when nodes go down.
  * Replication Controller: Responsible for maintaining the correct number of pods for every replication controller object in the system.
  * Endpoints Controller: Populates the Endpoints object (i.e., join Services & Pods).
  * Service Account & Token Controllers: Create default accounts and API access tokens for new namespaces

It runs on the master(s).
It binds on port 10252.

## Scheduler
The kube-scheduler watches newly created pods that have no node assigned, and selects a node for them to run on. It runs on the master(s). It binds on port 10251

## Agent
The kubelet is the primary node agent. Its main responsibilities are:

  * Watches for pods that have been assigned to its node
  * Mounts the pod’s required volumes
  * Runs the pod’s containers via docker 
  * Periodically executes container liveness probes
  * Reports the status of the pod back to the rest of the system

The kubelet runs on the workers. It binds on ports 10250 and 10255.

## Proxy
The kube-proxy component enables the Kubernetes service abstraction by maintaining network rules on the host and performing connection forwarding. It runs on the workers. It binds on port 31080.

## Command line client
The kubectl is the command line interface the humans use to interact with a Kubernetes cluster. It connect to the API Server and provides a power interface. The kubectl CLI can run on any machine is able to reach the API Server.

