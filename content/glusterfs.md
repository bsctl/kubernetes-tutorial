# GlusterFS setup
In this section of the guide, we're going to setup a GlusterFS environment to be used as storage backend in Kubernetes. Our cluster is made of three nodes:

   * gluster00 with IP 10.10.10.120
   * gluster01 with IP 10.10.10.121
   * gluster02 with IP 10.10.10.122

each one exposing two row devices: ``/dev/vg00/brick00`` and ``/dev/vg01/brick01"``.

To manage the Gluster cluster storage, i.e. adding volumes, removing volumes, etc., we are going to install an additional **Heketi** server on one of the gluster node. As alternative, the **Heketi** can be installed on a stand-alone machine as system service or it can be deployed as container based service running on the same kubernetes cluster.

Install the Heketi server and the cli client on one of the gluster node

    yum install heketi heketi-client -y

Create a ssh key pair

    ssh-keygen -f /etc/heketi/heketi_key -t rsa -N ''

set the ownership of the key pair

    chown heketi:heketi /etc/heketi/heketi_key*
    
and install the public key on each gluster node

    ssh-copy-id -i /etc/heketi/heketi_key.pub root@gluster00
    ssh-copy-id -i /etc/heketi/heketi_key.pub root@gluster01
    ssh-copy-id -i /etc/heketi/heketi_key.pub root@gluster02

Now configure the Heketi server by editing the ``/etc/heketi/heketi.json`` configuration file as following
```
...
  "_port_comment": "Heketi Server Port Number",
  "port": "8080",
...
    "executor": "ssh",
    "_sshexec_comment": "SSH username and private key file information",
    "sshexec": {
      "keyfile": "/etc/heketi/heketi_key",
      "user": "root",
      "port": "22",
      "fstab": "/etc/fstab"
    },
...
    "_db_comment": "Database file name",
    "db": "/var/lib/heketi/heketi.db",
...
```

Start and enable the Heketi service

    systemctl restart heketi
    systemctl enable heketi

Make sure the Heketi server hostname is resolved and check the connection

    curl http://heketi:8080/hello
    Hello from Heketi

A topology file is used to tell Heketi about the environment and what nodes and devices it has to manage. Create a ``topology.json`` configuration file describing all nodes in the cluster topology
```json
{
   "clusters":[
      {
         "nodes":[
            {
               "node":{
                  "hostnames":{
                     "manage":[
                        "gluster00"
                     ],
                     "storage":[
                        "10.10.10.120"
                     ]
                  },
                  "zone":1
               },
               "devices":[
                  "/dev/vg00/brick00",
                  "/dev/vg01/brick01"
               ]
            },
// other nodes here ...
```

Load the cluster topology into Heketi by the Heketi cli

	heketi-cli --server http://heketi:8080 topology load --json=topology.json
	
	Creating cluster ... ID: 88fa719937edf4b3b3822b4abf825c6b
        Creating node gluster00 ... ID: db2f0baad1bbb5868f8e65f82e7ca905
                Adding device /dev/vg00/brick00 ... OK
                Adding device /dev/vg01/brick01 ... OK
        Creating node gluster01 ... ID: 43fa07bc2c2156c98c1f959860cf94b1
                Adding device /dev/vg00/brick00 ... OK
                Adding device /dev/vg01/brick01 ... OK
        Creating node gluster02 ... ID: e93ba25f09c74938064bfaca0d5697fe
                Adding device /dev/vg00/brick00 ... OK
                Adding device /dev/vg01/brick01 ... OK


Check the cluster has been created

	heketi-cli --server http://heketi:8080 cluster list
	Clusters: 88fa719937edf4b3b3822b4abf825c6b
	
	heketi-cli --server http://heketi:8080 node list
	Id:43fa07bc2c2156c98c1f959860cf94b1     Cluster:88fa719937edf4b3b3822b4abf825c6b
	Id:db2f0baad1bbb5868f8e65f82e7ca905     Cluster:88fa719937edf4b3b3822b4abf825c6b
	Id:e93ba25f09c74938064bfaca0d5697fe     Cluster:88fa719937edf4b3b3822b4abf825c6b


Create a gluster volume to verify Heketi:

	heketi-cli --server http://heketi:8080 volume create --size=1
	Name: vol_7ce4d0cbc77fe36b84ca26a5e4172dbe
	Size: 1
	Volume Id: 7ce4d0cbc77fe36b84ca26a5e4172dbe
	Cluster Id: 88fa719937edf4b3b3822b4abf825c6b
	Mount: 10.10.10.120:vol_7ce4d0cbc77fe36b84ca26a5e4172dbe
	Mount Options: backup-volfile-servers=10.10.10.121,10.10.10.122
	Durability Type: replicate
	Distributed+Replica: 3

