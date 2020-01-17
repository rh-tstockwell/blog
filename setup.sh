#!/bin/sh

## mongodb
oc new-app --template mongodb-persistent --name mongodb
oc create configmap mongodb-scripts \
  --from-file=init.sh=src/mongodb/script.sh \
  --from-file=data.json=src/mongodb/ratings_data.json
oc patch deploymentconfig mongodb -p "$(cat src/mongodb/patch-dc-volume.yml)"
oc patch deploymentconfig mongodb -p "$(cat src/mongodb/patch-dc-hook.yml)"
oc rollout latest mongodb
sleep 30s

## ratings
oc new-app --image-stream nodejs:10 https://github.com/rh-tstockwell/bookinfo.git --context-dir src/ratings --name ratings
oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-run.yml)"
oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-version.yml)"
oc expose svc ratings
oc patch bc ratings -p "$(cat src/ratings/patch-bc-ref.yml)"
oc patch deploymentconfig ratings -p "$(cat src/ratings/patch-dc-mongodb.yml)"
oc start-build ratings
sleep 30s


## details
oc new-app --image-stream ruby:2.5 https://github.com/rh-tstockwell/bookinfo.git --context-dir src/details --name details
oc patch buildconfig details -p "$(cat src/details/patch-bc-ref.yml)"
oc start-build details



# reviews
oc new-app jboss-eap72-openshift:1.0~https://github.com/rh-tstockwell/bookinfo.git --context-dir src/reviews --name reviews



# productpage
oc new-app python:3.6~https://github.com/rh-tstockwell/bookinfo.git --context-dir src/productpage --name productpage
oc patch dc productpage -p "$(cat src/productpage/patch-dc-ref.yml)"
# error starting
# try adding env var for productpage.py
# fail, remove env then try adding app.sh script
oc patch dc productpage -p "$(cat src/productpage/patch-bc-ref.yml)"
oc start-build productpage
# todo: flesh out better
# don't worry about port 9080
# change to not require any ports in productrpage app