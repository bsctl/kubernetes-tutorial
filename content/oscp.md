# Creating Applications in OpenShift
OpenShift is a customized distribution of Kubernetes provided by **Red Hat**. In OpenShift, containers run using a no-root arbitrarily assigned user ID. This behavior provides an additional security level against processes escaping the container due to a vulnerability and thereby achieving escalated permissions on the host node. Due to this restriction, images that run as root may not be deployed on OpenShift.

In this section, we're going to describe various ways to deploy a containerized software application in OpenShift.

  * [Applications from images](#applications-from-images)
    * [Image Stream](#image-stream)
    * [Deployment Config](#deployment-config)
  * [Applications from source code](#applications-from-source-code)
    * [Docker build strategy](#docker-build-strategy)
    * [Build Config](#build-config)
    * [Source build strategy](#source-build-strategy)
  * [Applications from templates](#applications-from-templates)

Before to procede, please make sure the internal OpenShift image registry is published outside the cluster, for example it is reachable at `https://registry.openshift.noverit.com`.

## Applications from images
Users can deploy an application from an already built docker image if it can run as no-root user. Images can be pulled from the local reposistory or they can be pulled from any public registry.

As a demo user, create a new application strarting from the docker [image](docker.io/kalise/nodejs-web-app) in the Docker Hub
```
oc new-app \
   --name=nodejs \
   --docker-image=docker.io/kalise/nodejs-web-app \
   -e MESSAGE="Hello New Application"

--> Found Docker image from docker.io for "docker.io/kalise/nodejs-web-app"

--> Creating resources ...
    imagestream.image.openshift.io "nodejs" created
    deploymentconfig.apps.openshift.io "nodejs" created
    service "nodejs" created

--> Success
```

The command above creates a bounch of objects:

 * Image Stream
 * Deployment Config
 * Service


### Image Stream
The Image Stream object tells OpenShift when the referenced image changes. In suche case, a new deployment of our application is created.

By inspecting the Image Stream above 
```
oc get is nodejs -o yaml
```

Here parts of the yaml of the above Image Stream
```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  labels:
    app: nodejs
  name: nodejs
  namespace: demo
spec:
  lookupPolicy:
    local: false
  tags:
  - annotations:
      openshift.io/imported-from: docker.io/kalise/nodejs-web-app
    from:
      kind: DockerImage
      name: docker.io/kalise/nodejs-web-app
```

The Image Stream references Docker Image originated from public image repository ``docker.io/kalise/nodejs-web-app``. This image has been pulled during the application creation process and stored in the local registry at `https://registry.openshift.noverit.com`. Any changes to the image in the local registry will trigger a new deployment of the application.

### Deployment Config
A Deployment Config just creates a new replica controller and lets it start up the pods, similarly to a kubernetes deployment.

See the Deployment Config above 
```
oc get dc/nodejs -o yaml
```

The Deployment Config defines the following:
  
  * The number of the desired pod replicas.
  * The labels selector used to bind the pods.
  * The strategy for the update.
  * The triggers for creating a new deployment.

Here some relevant details about the triggering conditions for the deployment above
```yaml
apiVersion: v1
kind: DeploymentConfig
...
spec:
  triggers:
  - type: ConfigChange
  - type: ImageChange
      imageChangeParams:
      automatic: true
      containerNames:
      - nodejs
      from:
        kind: ImageStreamTag
        name: nodejs:latest
        namespace: project00
        lastTriggeredImage: docker.io/kalise/nodejs-web-app    
...
```

A ``ConfigChange`` trigger causes a new deployment to be created any time the configuration changes. An ``ImageChange`` trigger causes a new deployment to be created each time a new version of the image is available.

The user defines customizable strategies to transition from the previous deployment to the new one. Each application has different requirements for availability during deployments. OpenShift provides strategies to support a variety of deployment scenarios. The Rolling strategy is the default strategy while the other option is the Recreate strategy.

Here the relevant details about the strategy for the deployment above
```yaml
apiVersion: v1
kind: DeploymentConfig
...
spec:
  ...
  strategy:
    resources: {}
    rollingParams:
      intervalSeconds: 1
      maxSurge: 25%
      maxUnavailable: 25%
      updatePeriodSeconds: 1
    type: Rolling
...
```

Users can manually force a new deployment to start

```
oc rollout latest dc/nodejs
deploymentconfig "nodejs" rolled out
```

To get basic information about all the available revisions of the application
```
oc rollout history dc/nodejs
deploymentconfigs "nodejs"
REVISION        STATUS          CAUSE
1               Complete        image change
2               Complete        image change
3               Complete        image change
4               Complete        config change
5               Running         manual change
```

Above we see latest deployment still running. It is triggered by a manual change. Rollback the deployment
```
oc rollout undo dc/nodejs
deploymentconfig "nodejs" rolled back
```

Other changes can be triggered by config changes in the pod template, as for example, adding probes and/or resource constraints.


Also an image change in the ImageStream creates a new deployment. For example, make a change in the ImageStream by pushing a different image to the local registry:

    docker pull kalise/nodejs-web-app:1.2
    docker tag kalise/nodejs-web-app:1.0 registry.openshift.noverit.com/demo/nodejs:latest
    docker login -u openshift -p $(oc whoami -t) registry.openshift.noverit.com
    docker push registry.openshift.noverit.com/demo/nodejs:latest

Check if the new deployment has been created

    oc get dc,rc
    NAME                                        REVISION   DESIRED   CURRENT   TRIGGERED BY
    deploymentconfig.apps.openshift.io/nodejs   2          1         1         config,image(nodejs:latest)

    NAME                             DESIRED   CURRENT   READY     AGE
    replicationcontroller/nodejs-1   0         0         0         8m
    replicationcontroller/nodejs-2   1         1         1         1m

As we can see, the DeploymentConfig updated with a new Replication Controller.

## Applications from source code
Users can create applications from source code stored in a local or remote Git repository. When users specify a source code repository, OpenShift attempts to build the code into a new application image and tries to automatically determine the type of build strategy to use.

There are, basically two build strategies: **Docker** or **Source**.

### Docker build strategy
If a Dockerfile is present in the source code repository, OpenShift uses the Docker strategy invoking the ``docker build`` command to produce a runnable image.

```
oc new-app https://github.com/kalise/nodejs-web-app.git \
   --name=nodejs-git \
   -e MESSAGE="Hello New Application"

--> Found Docker image from Docker Hub for "node:latest"

--> Creating resources ...
    imagestream.image.openshift.io "node" created
    imagestream.image.openshift.io "nodejs-git" created
    buildconfig.build.openshift.io "nodejs-git" created
    deploymentconfig.apps.openshift.io "nodejs-git" created
    service "nodejs-git" created

--> Success
```

The above command creates a **Build Config**, which produces a runnable image. The code is cloned locally from the remote git reposistory and then a runnable image ``nodejs-web-app:latest`` is created and pushed to the local registry.

Since the code repository already contains a Dockerfile, the build strategy is *"Docker"* by default. The base image ``node:latest`` is also created and pushed to the local OpenShift registry.

The command also creates two image streams to keep track of changes in the base ``node:latest`` image and in the runnable image.

The command also create a new **Deployment Config** to deploy the runnable image, and a **Service** to provide load-balanced access to the pods. 

### Build Config
In general, a build is the process of transforming input source code into a runnable image. The **Build Config** object created by OpenShift is the definition of this build process. A Build Config describes a single build process and a set of triggers for when a new build should be created. 

Inspect the Build Config object above
```
oc get bc/nodejs-web-app -o yaml
```
Here some key points.

The source section, defines the source code repository location
```yaml
...
  source:
    git:
      uri: https://github.com/kalise/nodejs-web-app.git
    type: Git
...
```

The strategy section describes the build strategy used to execute the build
```yaml
...
  strategy:
    dockerStrategy:
      from:
        kind: ImageStreamTag
        name: node:latest
    type: Docker
...
```

The output section, defined where the runnable image is pushed after it is successfully built
```yaml
...
  output:
    to:
      kind: ImageStreamTag
      name: nodejs-web-app:latest
...
```

The trigger section, defines the criteria which cause a new build to be created
```yaml
...
  triggers:
  - type: GitHub
    github:
      secret: *******
  - type: Generic
    generic:
      secret: *******
  - type: ConfigChange
  - type: ImageChange
    imageChange:
      lastTriggeredImageID: node
...
```

Users can force a new build to happen even if no changes are in place
```
oc start-build bc/nodejs-web-app
build "nodejs-web-app-2" started
```

When the new build completes, a new image is created and pushed to the local registry. Also a new deployment is created to start the new application.

### Source build strategy
The source build strategy optimizes, secures and speeds the build of the new application by injecting the application source into a single runnable image. By building runnable images from source code, instead of using a regular Dockerfile, the users can avoid accidental or intentional abuses by running, for example, an application as a root user.

To create a new application, using the source build strategy 
```
oc new-app https://github.com/kalise/nodejs-web-app.git \
   --name=nodejs-git-source \
   -e MESSAGE="Hello New Application" \
   --strategy=source
   
--> Creating resources ...
    imagestream.image.openshift.io "nodejs-git-source" created
    buildconfig.build.openshift.io "nodejs-git-source" created
    deploymentconfig.apps.openshift.io "nodejs-git-source" created
    service "nodejs-git-source" created

--> Success
```

## Applications from templates
OpenShift makes it possible to deploy a set of resources through a single JSON or YAML manifest file. In addition, OpenShift takes this a step further by allowing that manifest to be parameterizable. This is called a **Template**. A template is a list of OpenShift objects whose definitions can include placeholders that get replaced with actual values when OpenShift instantiate the template.

OpenShift comes with a set of predefined templates. However, users can create their own custom templates. An example of custom template can be found in the ``nodejs-template.yaml`` file descriptor.

First, create the template

    oc apply -f nodejs-template.yaml

Create a new application, from the template ``nodejs-web-app`` by specifying the parameters, where it is required
```
oc new-app nodejs-web-app \
   -p NAME=web \
   -p NODEJS_VERSION=8 \
   -p MEMORY_LIMIT=512Mi \
   -p SOURCE_REPOSITORY_URL=https://github.com/kalise/nodejs-web-app.git \
   -p APPLICATION_DOMAIN_NAME=openshift.noverit.com
   
Deploying template "openshift/nodejs-web-app" to project project00

     NoverIT Nodejs Web App
     ---------
     An example of nodejs web application.

     The following service(s) have been created in your project: web.
     labels:
     template: nodejs-web-app
     app: nodejs-web-app

     * With parameters:
        * Name=web
        * Namespace=openshift
        * Version of NodeJS Image=10
        * Memory Limit=512Mi
        * Git Repository URL=https://github.com/kalise/nodejs-web-app.git
        * Git Reference=
        * Context Directory=
        * Application Domain=openshift.noverit.com
```
