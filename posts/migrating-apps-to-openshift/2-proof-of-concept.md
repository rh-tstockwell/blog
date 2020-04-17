# Migrating Applications to OpenShift: Part 2 - Proof of concept

In this part of the [Migrating Applications to OpenShift](1-overview.md) series, I will demonstrate creating a proof of concept application using bookinfo.

I will showcase Kubernetes (k8s) YAML changes using [oc patch](https://docs.openshift.com/container-platform/3.11/cli_reference/basic_cli_operations.html#patch), but it is possible to make the same changes by directly modifying the Pod YAML via [oc edit](https://docs.openshift.com/container-platform/3.11/cli_reference/basic_cli_operations.html#edit) or through the GUI.

## Getting Started

First up we make sure to have a bookinfo project setup on OpenShift and locally check out the bookinfo repository from GitHub.

```sh
oc login
oc new-project bookinfo
git clone https://github.com/rh-tstockwell/bookinfo.git
cd bookinfo
```

This will checkout develop branch by default, commands lower down will make sure to deploy the app from master branch code if necessary.

### Useful Commands

Unless otherwise specified, I use the following commands regularly to check the status and progress of builds & deployments:

- **`oc status`** - Gives a general overview of the entire project.
- **`oc get pods`** - Shows the name & status of all Pods in the project.
- **`oc logs -f bc/<app>`** - Follows the logs of the current build Pod for `<app>`.
- **`oc logs -f dc/<app>`** - Follows the logs of the deployment/deployed Pod for `<app>`.
Until the application Pod deploys, it will show the deploy Pod logs.
After the deploy Pod completes and exits, the command will complete, after which you can rerun the command to follow the application logs.

## Ratings Database (MongoDB)

For no reason in particular, I've selected MongoDB as the backend for the Ratings Service over PostgreSQL (the Ratings Service can use either) and will deploy this first so that the other services have a database they can use.

The source of the istio image can be found at [`src/mongodb/Dockerfile`](https://github.com/rh-tstockwell/bookinfo/blob/master/src/mongodb/Dockerfile).
Upon investigation, we can see that the Dockerfile extends an existing MongoDB image and pre-populates the database with some data.
We can implement this more concisely in OpenShift without needing to create a custom image.

Firstly, we should create a MongoDB instance using the `mongodb-persistent` template.
This template will instantiate all k8s resources, including persistent storage, to run a persistent MongoDB database in OpenShift.

```console
$ oc new-app --template mongodb-persistent --name mongodb
--> Deploying template "openshift/mongodb-ephemeral" to project bookinfo
...
--> Creating resources ...
    secret "mongodb" created
    service "mongodb" created
    deploymentconfig.apps.openshift.io "mongodb" created
--> Success
    Application is not exposed. You can expose services to the outside world by executing one or more of the commands below:
     'oc expose svc/mongodb'
    Run 'oc status' to view your app.
```

```console
$ oc status
...
svc/mongodb - x.x.x.x:27017
  dc/mongodb deploys openshift/mongodb:3.6
    deployment #1 deployed 1 minute ago
...
```

Once the MongoDB pod is up and running, we can create a [remote shell](https://docs.openshift.com/container-platform/3.11/dev_guide/ssh_environment.html) and connect to the local database.
No collections should exist if we have an empty MongoDB database.

```console
$ oc rsh dc/mongodb bash -c 'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --quiet --eval "db.getCollectionNames()"'
[ ]
```

> **Note:** The environment variables I used to connect to MongoDB above are sourced from the `mongodb` secret and assigned to the Pod by `oc new-app`.

Now that we have a functioning MongoDB database, we need to ensure it is pre-populated with the data listed in [`src/mongodb/ratings_data.json`](https://github.com/rh-tstockwell/bookinfo/blob/master/src/mongodb/ratings_data.json).
Using a method mentioned in [Using Post Hook to Initialize a Database](https://www.openshift.com/blog/using-post-hook-to-initialize-a-database), we can use the original scripts used by the Dockerfile (with some small modifications) to populate our database after the Pod starts by using a [Pod-based lifecycle hook](https://docs.openshift.com/container-platform/3.11/dev_guide/deployments/deployment_strategies.html#pod-based-lifecycle-hook).

We are going to have to make the following changes to [`src/mongodb/script.sh`](https://github.com/rh-tstockwell/bookinfo/blob/master/src/mongodb/script.sh) for it to work in our lifecycle hook:

- Enable the MongoDB Red Hat Software Collection to access the MongoDB binaries
- Connect to our MongoDB instance using the appropriate environment variables
- Handle duplicate values on import using [`--upsertFields`](https://docs.mongodb.com/manual/reference/program/mongoimport/#cmdoption-mongoimport-upsertfields) since our script will be run after every deployment.

View the updated script [here](https://github.com/rh-tstockwell/bookinfo/blob/blog/2/mongodb/src/mongodb/script.sh).

Now we need to get the script and data mounted into the mongodb Pod so that we can run them when the Pod starts.
The best way to do this is using a [`ConfigMap`](https://docs.openshift.com/container-platform/3.11/dev_guide/configmaps.html).

```console
$ oc create cm mongodb-scripts --from-file=src/mongodb/script.sh --from-file=src/mongodb/ratings_data.json
configmap/mongodb-scripts created
```

Now that we've created the ConfigMap, we can mount it into the Pod as a volume and set up a Post Lifecycle Hook that uses the script.

View the patch [here](https://github.com/rh-tstockwell/bookinfo/blob/blog/2/mongodb/src/mongodb/patches/1-dc-hook.yml).

```console
$ oc patch dc mongodb -p "$(cat src/mongodb/patches/1-dc-hook.yml)"
deploymentconfig.apps.openshift.io/mongodb patched
```

> **Note:** The extra `sleep` command in the lifecycle hook command gives the MongoDB service a chance to start up successfully before the script runs.

After the rollout succeeds, we can query the MongoDB `ratings` collection to check that it has been populated with the data in [`src/mongodb/ratings_data.json`](https://github.com/rh-tstockwell/bookinfo/blob/master/src/mongodb/patches/1-dc-hook.yml).

```console
$ oc rsh dc/mongodb bash -c 'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --quiet --eval "db.ratings.find()"'
{ "_id" : ObjectId("..."), "rating" : 5 }
{ "_id" : ObjectId("..."), "rating": 4 }
```

And there it is, a pre-populated MongoDB database running on OpenShift!

## Ratings Service (NodeJS)

- Initial build from `master` with nodejs s2i

```console
$ oc new-app 'nodejs:10~https://github.com/rh-tstockwell/bookinfo.git#master' --context-dir src/ratings --name ratings
--> Found image 0d01232 (7 months old) in image stream "openshift/nodejs" under tag "10" for "nodejs:10"
...
--> Creating resources ...
    imagestream.image.openshift.io "ratings" created
    buildconfig.build.openshift.io "ratings" created
    deploymentconfig.apps.openshift.io "ratings" created
    service "ratings" created
--> Success
    Build scheduled, use 'oc logs -f bc/ratings' to track its progress.
    Application is not exposed. You can expose services to the outside world by executing one or more of the commands below:
     'oc expose svc/ratings'
    Run 'oc status' to view your app.
```

```console
$ oc status
...
svc/ratings - x.x.x.x:8080
  dc/ratings deploys istag/ratings:latest <-
    bc/ratings source builds https://github.com/rh-tstockwell/bookinfo.git on openshift/nodejs:10
    deployment #1 deployed 2 minutes ago - 0/1 pods (warning: 2 restarts)

Errors:
  * pod/ratings-1-5t966 is crash-looping
...
```

- Doesn't start - crash looping on deployment
- Should check the deployment logs

```console
$ oc logs -f dc/ratings
...
> @ start /opt/app-root/src
> node ratings.js

net.js:1405
      throw new ERR_SOCKET_BAD_PORT(options.port);
      ^

RangeError [ERR_SOCKET_BAD_PORT]: Port should be >= 0 and < 65536. Received NaN.
...
```

- Looks like the script expects a port to be passed to it on the cmd line

```js
var port = parseInt(process.argv[2])
```

- According to the [NodeJS S2I Readme](https://github.com/sclorg/s2i-nodejs-container/tree/master/10#environment-variables), we can use the `NPM_RUN` environment variable to override the script that gets run when the container starts.
- In this case, we can set it to the following to set a port: `start -- 8080`. `start` ensures it still runs the `start` script, the `--` indicates everything after it should be an argument to the underlying command run by the previous script, and in our case we want to give it the port number `8080` as it is the default port expected by services in k8s/openshift?.
- Two ways to provide envvars, through `.s2i/environment`, and through the `deploymentconfig`.
- Should use `.s2i/environment` for something that will not change for the app in different environments (dev, test, etc.) and `deploymentconfig` for others
- In this case we have the first one so should do that

<!-- TODO: add link to .s2i/environment -->
- View it here.

- Now we'll patch the buildconfig to point to the updated commit

<!-- TODO: add link to patch -->
- View the patch.

```console
$ oc patch bc ratings -p "$(cat src/ratings/patches/1-bc-ref.yml)"
buildconfig.build.openshift.io/ratings patched
```

- Patched the build, so need to make sure we start a new build (may happen automatically?)

```console
$ oc start-build ratings
build.build.openshift.io/ratings-2 started
```

- This will eventually work

```console
$ oc status
...
svc/ratings - x.x.x.x:8080
  dc/ratings deploys istag/ratings:latest <-
    bc/ratings source builds https://github.com/rh-tstockwell/bookinfo.git#blog/2/ratings on openshift/nodejs:10
    deployment #2 deployed about a minute ago - 1 pod
    deployment #1 deployed 3 hours ago
...
```

- Appears to be running, check by exposing service and hitting up an endpoint

```
$ oc expose svc ratings
route.route.openshift.io/ratings exposed

$ host="$(oc get route ratings --template '{{.spec.host}}')"

$ curl "http://$host/ratings/1"
{"id":1,"ratings":{"Reviewer1":5,"Reviewer2":4}}
```

- Yay! However, we're not actually hooked up to the database just yet. To do so we need to make sure the `SERVICE_VERSION` environment variable is set to `v2` and set the `MONGO_DB_URL` environment variable to point to our mongodb service.

- `MONGO_DB_URL`: `mongodb.bookinfo.svc:27017` -> due to the default [DNS-based service discovery](https://docs.openshift.com/container-platform/3.11/architecture/networking/networking.html#architecture-additional-concepts-openshift-dns) for services

```console
$ oc patch dc ratings -p "$(cat src/ratings/patches/2-dc-mongo.yml)"
deploymentconfig.apps.openshift.io/ratings patched
```

- Once that's done, check the api again

```console
$ curl "http://$host/ratings/1"
{"error":"could not connect to ratings database"}
```

- This will still fail. The default mongodb on openshift is secured so we need to modify the application to work with a secured cluster (**to do:** how do we figure this out, show debug steps). I made the following change (maybe link to diff instead? | could I import with asciidoc?):

```javascript
var MongoClient = require('mongodb').MongoClient
var host = process.env.MONGO_DB_URL
var database = process.env.MONGODB_DATABASE
var username = process.env.MONGODB_USER
var password = process.env.MONGODB_PASSWORD
var url = `mongodb://${username}:${password}@${host}/${database}`
```

- Now, update the deployment to add the new envvars we defined, and update the build to point to the updated code

```console
$ oc patch dc ratings -p "$(cat src/ratings/patches/3-dc-mongo.yml)"
deploymentconfig.apps.openshift.io/ratings patched

$ oc patch bc ratings -p "$(cat src/ratings/patches/4-bc-ref.yml)"
buildconfig.build.openshift.io/ratings patched

$ oc start-build ratings
build.build.openshift.io/ratings-3 started
```

- Check it worked

```console
$ oc status
...
http://ratings-bookinfo.apps.cluster.example.com to pod port 8080-tcp (svc/ratings)
  dc/ratings deploys istag/ratings:latest <-
    bc/ratings source builds https://github.com/rh-tstockwell/bookinfo.git#blog/2/ratings-2 on openshift/nodejs:10
    deployment #4 deployed about a minute ago - 1 pod
    deployment #3 deployed 7 minutes ago
    deployment #2 deployed about an hour ago
...

$ curl "http://$host/ratings/1"
{"error":"could not connect to ratings database"}
```

- Note that in the real world we'd probably just make an update and push our code to master.
  I've just used tags here to demostrate all the different changes for this blog.
