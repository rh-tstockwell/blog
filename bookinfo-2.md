Migrating Applications to OpenShift
===================================

Part 2: Proof of concept
------------------------

In this part of the “Migrating Applications to OpenShift” series, I will demonstrate creating a proof of concept application using bookinfo.

I will showcase YAML changes using [oc patch](https://docs.openshift.com/container-platform/3.11/cli_reference/basic_cli_operations.html#patch), but it is possible to make the same changes by directly modifying the Pod YAML via [oc edit](https://docs.openshift.com/container-platform/3.11/cli_reference/basic_cli_operations.html#edit) or through the GUI.

### Getting Started

First up we make sure to have a bookinfo project setup on OpenShift and locally check out the bookinfo repository from GitHub.

```
$ oc login
$ oc new-project bookinfo
$ git clone https://github.com/rh-tstockwell/bookinfo.git
$ cd bookinfo
```

#### Useful Commands
Unless otherwise specified, I use the following commands regularly to check the status and progress of builds & deployments:

| Command       | Description |
| ------------- | ----------- |
| `oc status`   | Gives a general overview of the entire project |
| `oc get pods` | Shows the name & status of all Pods in the project |
| `oc logs -f bc/<app>` | Follows the logs of the current build Pod for `<app>` |
| `oc logs -f dc/<app>` | Follows the logs of the deployment/deployed Pod for `<app>`. Until the application Pod deploys, it will show the deploy Pod logs. After the deploy Pod completes and exits, the command will complete, after which you can rerun the command to follow the application logs. |

### Ratings Database (MongoDB)
For no reason in particular, I've selected MongoDB as the backend for the Ratings Service over PostgreSQL (the Ratings Service can use either) and will deploy this first so that the other services have a database they can use.

The source of the istio image can be found at src/mongodb/Dockerfile. Upon investigation, we can see that the Dockerfile extends an existing MongoDB image and pre-populates the database with some data. We can implement this more nicely in OpenShift without needing to create a custom image.

Firstly, we should create a MongoDB instance using the mongodb-persistent template. This template will instantiate all the Kubernetes resources, including persistent storage, to run a persistent MongoDB database in OpenShift.

```
$ oc new-app --template mongodb-persistent --name mongodb
```

Once the MongoDB pod is up and running, we can create a remote shell and connect to the database. As you can see, we have an empty database with no collections.

```
$ oc rsh dc/mongodb bash -c 'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --quiet --eval "db.getCollectionNames()"'
[ ]
```

**Note:** The environment variables I used to connect to MongoDB above are sourced from the `mongodb` secret and assigned to the Pod by `oc new-app`.

Now that we have a functioning MongoDB database, we need to ensure it is pre-populated with the correct data. Using a method mentioned in Using Post Hook to Initialise a Database, we can use the original scripts (with some small modifications) used by the Dockerfile to populate our database after the Pod starts by using a pod lifecycle hook. 

We are going to have to make the following changes to `script.sh` for it to work in our lifecycle hook:
- Enable the MongoDB Red Hat Software Collection to access the MongoDB binaries
- Connect to our MongoDB instance using the appropriate environment variables
- Handle duplicate values on import using --upsertFields since our script will be run after every deployment.

<details>
  <summary><code>src/mongodb/script.sh</code></summary>

```
. /opt/rh/rh-mongodb36/enable

mongoimport --host "$MONGODB_SERVICE_HOST:$MONGODB_SERVICE_PORT" \
  --db "$MONGODB_DATABASE" \
  --username "$MONGODB_USER" \
  --password "$MONGODB_PASSWORD" \
  --collection ratings \
  --upsertFields rating \
  --file "$APP_DATA/scripts/ratings_data.json"
```
</details>

Now we need to get the script and data mounted into the mongodb Pod so that it can be run. The best way to do that is going to be using a ConfigMap.

```
$ oc create configmap mongodb-scripts \
  --from-file=script.sh=src/mongodb/script.sh \
  --from-file=ratings_data.json=src/mongodb/ratings_data.json
configmap/mongodb-scripts created
```

Now that we've created the ConfigMap, we can mount it into the Pod as a volume and set up a Post Lifecycle Hook that uses the script.

<details>
  <summary><code>src/mongodb/patch-1-dc-hook.yml</code></summary>
  
```yaml
spec:
  template:
    spec:
      containers:
        - name: mongodb
          volumeMounts:
            - name: scripts
              mountPath: /opt/app-root/src/scripts
      volumes:
        - name: scripts
          configMap:
            name: mongodb-scripts
            defaultMode: 0770
  strategy:
    recreateParams:
      post:
        failurePolicy: Abort
        execNewPod:
          containerName: mongodb
          command:
            - /bin/sh
            - -c
            - $APP_DATA/scripts/script.sh
          env:
            - name: MONGODB_USER
              valueFrom:
                secretKeyRef:
                  key: database-user
                  name: mongodb
            - name: MONGODB_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: database-password
                  name: mongodb
            - name: MONGODB_DATABASE
              valueFrom:
                secretKeyRef:
                  key: database-name
                  name: mongodb
          volumes:
            - scripts
```
</details>

```
$ oc patch dc mongodb -p "$(cat src/mongodb/patch-1-dc-hook.yml)"
```

**Note:** The extra `sleep` command in the lifecycle hook command gives the MongoDB service a chance to start up successfully before the script runs.

After the rollout succeeds, we can query the database to check that our hook ran successfully. 

```bash
$ oc rsh dc/mongodb bash -c 'mongo -u $MONGODB_USER -p $MONGODB_PASSWORD $MONGODB_DATABASE --quiet --eval "db.ratings.find()"'
{ "_id" : ObjectId("..."), "rating" : 5 }
{ "_id" : ObjectId("..."), "rating": 4 }
```

And there it is, a pre-populated MongoDB database running on OpenShift!
