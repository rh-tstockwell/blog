Migrating an Applications to OpenShift: Phase 1 - Get it running!
=================================================================

As I am involved with helping more teams migrate their applications on to OpenShift,
I can't help but notice some patterns and considerations that arise regarding the
migration process to ensure success. Such operations have many domain-specific factors,
but in regards to getting the applications up and running on OpenShift, there appear
to be several common patterns that teams use to migrate successfully.

I find the following phases useful breakpoints of effort in application migration:

- **Phase 1:**  Get it running!
- **Phase 2:** Start managing & configuring k8s resources
- **Phase 3:** Setup CI/CD for a single deployment environment
- **Phase 4:** Setup CD for multiple environments

In this blog series, I use the [bookinfo](https://istio.io/docs/examples/bookinfo)
application from the [Istio](https://istio.io/) project to demonstrate the complete
steps required to migrate an application on to OpenShift.

I selected bookinfo because it is an existing, sample microservices application I
can deploy from scratch on to OpenShift. Additionally, bookinfo is polyglot, i.e.,
the microservices are each written in different languages, which allows me to
showcase my thought process migrating different types of services across a spectrum
of programming languages.


I have forked the bookinfo subdirectory from Istio using the process described [here](https://help.github.com/en/github/using-git/splitting-a-subfolder-out-into-a-new-repository).
You can find my fork at [rh-tstockwell/bookinfo](https://github.com/rh-tstockwell/bookinfo).


Prerequisites
-------------
First off, I will assume you already have developer access to an OpenShift cluster.
If not, you can try it for free at [Getting Started with OpenShift](https://www.openshift.com/learn/get-started/).
Additionally, you should have at least beginner OpenShift, Kubernetes and container knowledge.

You will also need to install the oc client and successfully log in to your
cluster with standard developer privileges. If you followed one of the guides from the Getting Started
page, your guide should have instructions for you.

I use the oc client exclusively in this blog (I generally prefer the command line), but you can make all changes
using the GUI if you so wish.


Phase 1: Get it running!
------------------------

The goal in this phase is to get your application up and running in OpenShift as quickly
as possible. As such, you can use this as a proof of concept to understand the difficulty
level of your deployment.

My rules of thumb for this phase are, where possible:
- Spend as little time as possible getting the apps to work
- Use standard s2i images or templates
  - [Why?](https://github.com/openshift/source-to-image/blob/master/README.md#goals)
- Avoid code changes
  - It is incredibly beneficial to reduce code drift when supporting separate deployments
    during a migration. 

### Getting Started

First up I make sure to have a bookinfo project setup on OpenShift and locally
check out the bookinfo repository from GitHub.

```
$ oc login
$ oc new-project bookinfo
$ git clone https://github.com/rh-tstockwell/bookinfo.git
$ cd bookinfo
```

**To Do:** I should also explain that I'm going to be building these from scratch
to make use of the full range of the OpenShift feature set.  - this is part of
the value add of OpenShift


### Ratings Database (MongoDB)

For no particular reason, I'll select MongoDB as the backend for the ratings service
over PostgreSQL (the ratings service can use either) and deploy this first so that
my services have a database they can use.

```
$ cd src/mongodb
```

The Dockerfile here is the source of the original Istio image. Upon investigation,
I can see that the Dockerfile merely extends an existing MongoDB image and pre-populates
the database with some data. I can implement this more nicely in OpenShift without
needing to create a custom image.

Firstly, I create a MongoDB instance using the `mongodb-persistent` template. This
template will instantiate all the Kubernetes resources, including persistent storage,
to run a persistent MongoDB database in OpenShift.

```sh
$ oc new-app --template mongodb-persistent --name mongodb
```

<detail>
  <summary>Note</summary>
  <p>
  Unless otherwise specified, I use the following commands to check the status and
  progress of builds & deployments:
  
  - `oc status`
    - Gives a general overview of the entire project
  - `oc get pods`
    - Shows the status of all Pods in the project
  - `oc logs -f bc/app`
    - Follows the logs of the current build Pod
  - `oc logs -f dc/app`
    - Follows the logs of the current deployment/deployed Pod
    - Until the application Pod deploys, it will show the deploy Pod logs.
      After the deploy Pod completes and exits, the command will complete,
      after which you can rerun the command to follow the application logs</p>
</detail>

Once the MongoDB pod is up and running, I should be able to create a remote shell
session inside the Pod and connect to the database. As I can see, there are no
collections or data present.

```
$ oc rsh dc/mongodb bash -c \
    'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --eval "db.ratings.find()"'
# show output here
```

- Create mongodb db from openshift template


- Re-use existing scripts where possible
- Update script to use env vars and to handle dupes, since this will run on every deploy (upsertFields) - link to commit
- Create config map with init script & init data to mount into pod
```sh
$ oc create configmap mongodb-scripts \
  --from-file=init.sh=src/mongodb/script.sh \
  --from-file=data.json=src/mongodb/ratings_data.json
```

- Patch the dc to:
  - mount the configmap as a volume
  - run a new pod in the post lifecycle hook which runs the mounted script
    - `sleep` gives the mongo service a chance to start up successfully (link to something that explains)
```sh
$ oc patch deploymentconfig mongodb -p "$(cat src/mongodb/patch-1-dc-hook.yml)"
```

- Should rollout automatically due to config change
- Check data was imported successfully
- 
<details><summary>test</summary><p>

```
$ oc rsh dc/mongodb bash -c \
    'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --eval "db.ratings.find()"'
MongoDB shell version v3.6.3
connecting to: mongodb://127.0.0.1/sampledb
MongoDB server version: 3.6.3
{ "_id" : ObjectId("..."), "rating" : 5 }
{ "_id" : ObjectId("..."), "rating": 4 }
```

</p></details>

### Ratings - NodeJS
- Deploy app to openshift
```sh
$ oc new-app --image-stream nodejs:10 https://github.com/rh-tstockwell/bookinfo.git --context-dir src/ratings --name ratings
```
- Doesn't start - crashbackoff
- Check logs
```
> @ start /opt/app-root/src
> node ratings.js

net.js:1405
      throw new ERR_SOCKET_BAD_PORT(options.port);
      ^

RangeError [ERR_SOCKET_BAD_PORT]: Port should be >= 0 and < 65536. Received NaN.
```
- Checking the script we notice it pulls the port from a cmd line arg
```js
var port = parseInt(process.argv[2])
```
- According to the [readme](https://github.com/sclorg/s2i-nodejs-container/tree/master/10#environment-variables) for the NodeJS S2I image, we can use the `NPM_RUN` environment variable to override the script that is run when the container starts. In this case, we can set it to the following to set a port: `start -- 8080`. `start` ensures it still runs the `start` script, the `--` indicates everything after it should be an argument to the underlying command run by the previous script, and in our case we want to give it the port number `8080`.
- Apply the patch to do the above
```sh
$ oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-run.yml)"
```
- You may also notice by checkout out the ratings source code that we're actually not using the mongodb database yet. To do so we need to make sure the `SERVICE_VERSION` environment variable is set to `v2` and set the `MONGO_DB_URL` environment variable to point to our mongodb service.
  - `MONGO_DB_URL`: `mongodb:27017` -> due to local cluster naming (**todo:** find link)
```sh
$ oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-version.yml)"
```
- Check by exposing service and hitting up an endpoint
```
$ oc expose svc ratings
$ host="$(oc get route ratings --template '{{.spec.host}}')"
$ curl "http://$host/health"
{"status":"Ratings is healthy"}
$ curl "http://$host/ratings/1"
{"error":"could not connect to ratings database"}
```
- This will still fail. The default mongodb on openshift is secured so we need to modify the application to work with a secured cluster (**to do:** how do we figure this out, show debug steps). I made the following change (maybe link to diff instead? | could I import with asciidoc?):
```js
var MongoClient = require('mongodb').MongoClient
var host = process.env.MONGO_DB_URL
var database = process.env.MONGODB_DATABASE
var username = process.env.MONGODB_USER
var password = process.env.MONGODB_PASSWORD
var url = `mongodb://${username}:${password}@${host}/${database}`
```
- Now patch the buildconfig to point to the updated branch
```sh
$ oc patch bc ratings -p "$(cat src/ratings/patch-bc-ref.yml)"
```
- And add env vars from the mongodb secret, and point to our updated version 
```sh
$ oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-mongodb.yml)"
$ oc start-build ratings
$ oc logs -f bc/ratings
$ oc logs -f dc/ratings
```
- Check it worked
```
$ curl "http://ratings-bookinfo.apps.ca-central-1.starter.openshift-online.com/ratings/1"
{"id":1,"ratings":{"Reviewer1":5,"Reviewer2":4}}
```

### Details - Ruby

- Add custom run script to run ruby app
- Deploy app to OpenShift

```sh
$ oc new-app --image-stream ruby:2.5 https://github.com/rh-tstockwell/bookinfo.git --context-dir src/details --name details
$ oc logs -f bc/details
$ oc logs -f dc/details
You might consider adding 'puma' into your Gemfile.
ERROR: Rubygem Rack is not installed in the present image.
       Add rack to your Gemfile in order to start the web server.
```
- Won't work to start with, ruby s2i image expects a rack server running or puma etc 
- Can fix by adding a custom s2i run script (link to doco) at `src/details/.s2i/bin/run`
```sh
#!/bin/bash
ruby details.rb 8080
```
- Patch buildconfig to point to a ref with our changes
```
$ oc patch buildconfig details -p "$(cat src/details/patch-bc-ref.yml)"
$ oc start-build details
$ oc logs -f bc/details
$ oc logs -f dc/details
[2020-01-23 02:34:01] INFO  WEBrick 1.4.2
[2020-01-23 02:34:01] INFO  ruby 2.5.5 (2019-03-15) [x86_64-linux]
[2020-01-23 02:34:01] INFO  WEBrick::HTTPServer#start: pid=13 port=8080
```

### Reviews - Java + Gradle

```shell script
$ oc new-app jboss-eap72-openshift:1.0~https://github.com/rh-tstockwell/bookinfo.git --context-dir src/reviews --name reviews
$ oc expose svc reviews
$ curl http://reviews-bookinfo.apps-crc.testing/health   
     <html><head><title>Error</title></head><body>404 - Not Found</body></html>
```

- Looks like it succeeded, except our health endpoint tells us no
- Glancing through the build logs we notice that it never actually ran a build. The s2i image doesn't work with gradle
  and assumed a binary deployment when it didn't find a `pom.xml` file
- Let's customise an `assemble` script
- But first, we need to add the gradle wrapper so it can run gradle from anywhere
  - https://docs.gradle.org/current/userguide/gradle_wrapper.html
- Find assemble helper scripts from source code (find & link directly to source code cct_module code probs)
- Find some doco for the new env vars or find the link in code
- Need to set `MAVEN_S2I_ARTIFACT_DIRS` envvar to pick the war from reviews-application
- Mostly copied the assemble script from the image (`oc rsh` -> `/usr/local/s2i/assemble`)
- Looks like it worked
```
43) WFLYSRV0010: Deployed "reviews-application-1.0.war" (runtime-name : "reviews-application-1.0.war")
$ curl http://reviews-bookinfo.apps-crc.testing/health   
     <html><head><title>Error</title></head><body>404 - Not Found</body></html>
$ curl http://reviews-bookinfo.apps-crc.testing/reviews-application-1.0/healthhttp://reviews-bookinfo.apps-crc.testing/health  
  {"status": "Reviews is healthy"}
```
- Change gradle war name to deploy to root
```
war {
  archiveName = "ROOT.war"
}
```
- Do build
```
$ curl http://reviews-bookinfo.apps-crc.testing/health   
  {"status": "Reviews is healthy"}
```

To Do
-----
- Flesh out writing
- Link directly to code where possible
- Tag each completed stage, as well as each service per stage in repo
- Change java image to use wildfly
- Mention when to use `.s2i/environment` (appliation specific) and when to use the environment in the `buildconfig` (env specific)
- Short mention of why cli / yml over GUI in this blog (persistent long-term vs rapid changes, testing, dev etc long term)

Further Considerations
----------------------
- GitOps tooling
  - Helm v3
  - Ansible
  - Flux
  - ArgoCD
- Secrets management
- Persistent storage backups/redundancy/lifecycle
    - Depends on underlying tech
    - Can continue using existing external (to the cluster) databases if perf is ok



Bookinfo project
----------------
> This section needs to be moved to my Bookinfo readme file.
- Create a new repo to hold the bookinfo application: [rh-tstockwell/bookinfo](https://github.com/rh-tstockwell/bookinfo)
```shell script
git clone https://github.com/istio/istio.git
cd istio
git remote add bookinfo git@github.com:rh-tstockwell/bookinfo.git
```

- Isolate bookinfo subdir & history into its own branch
```shell script
git checkout -b bookinfo
git filter-branch --subdirectory-filter samples/bookinfo -- bookinfo
git push bookinfo bookinfo:upstream
```

- Keeps history intact so can update by repeating the process with an updated branch
<!--stackedit_data:
eyJoaXN0b3J5IjpbNjc3NTk4MzkyXX0=
-->
