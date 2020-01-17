Migrating Applications to OpenShift
===================================

Part 1: Overview
----------------

As I am involved with helping more teams migrate their applications on to OpenShift, I can't help but notice some patterns and considerations that arise regarding the migration process to ensure success. Such operations have many domain-specific factors, but in regards to getting the applications up and running on OpenShift, there appear to be several common patterns that teams use to migrate successfully.

I've found the following are useful breakpoints of effort:
1. Proof of concept
1. Set up CI/CD for a single environment
1. Set up CD for multiple environments

In this blog series, I will break down the work involved in each of the above stages and use the [bookinfo](https://istio.io/docs/examples/bookinfo/) application from the [Istio](https://istio.io/) project to demonstrate it.

I selected bookinfo because it is an existing, sample microservices application I can deploy from scratch on to OpenShift. Additionally, bookinfo is polyglot, i.e., the microservices are each written in different languages, which allows me to showcase my thought process migrating different types of services across a spectrum of programming languages.

I have forked the bookinfo subdirectory from Istio using the process described by GitHub: [Splitting a subfolder out into a new repository](https://help.github.com/en/github/using-git/splitting-a-subfolder-out-into-a-new-repository). You can find my fork at [rh-tstockwell/bookinfo](https://github.com/rh-tstockwell/bookinfo). The master branch is a direct fork from [istio/istio](https://github.com/istio/istio/tree/master/samples/bookinfo), while the develop branch will contain the changes made in this blog series.


### Prerequisites

For this blog series, I will assume you have at least beginner OpenShift, Kubernetes and container knowledge. Additionally, you will need developer access to an OpenShift cluster. If you do not have one available to you, you can try it out for free. See [Getting Started with OpenShift](https://www.openshift.com/learn/get-started/).

You will also need to [install the oc client](https://docs.openshift.com/container-platform/3.11/cli_reference/get_started_cli.html#installing-the-cli) and successfully log in to your cluster with standard developer privileges. If you followed one of the guides from the Getting Started page, your guide should have instructions for you.

I primarily use the oc client in this series (I generally prefer the command line), but you can make all changes using the GUI if you so wish.


### Proof of concept

First up, the goal is to get your application up and running quickly to act as a proof of concept. The aim is to understand the complexity involved in your undertaking as early as possible to de-risk what you can upfront.

My rules of thumb for this stage are, where possible:
- Spend as little time as possible getting your apps to work
- Use standard s2i images or templates
  - [Why?](https://github.com/openshift/source-to-image/blob/master/README.md#goals)
- Avoid code changes
  - From experience, it is Hard Work™ supporting drifting codebases during a platform migration, so we try to avoid this where we can

In Part 2 of the series, I will demonstrate how easy it is to get bookinfo up and running on an OpenShift cluster using [oc new-app](https://docs.openshift.com/container-platform/3.11/dev_guide/application_lifecycle/new_app.html#using-the-cli).


### Set up CI/CD for a single environment

The second goal is to be able to make changes to your application through a simple CI/CD pipeline. This pipeline will allow you to evolve your application more rapidly, and with more dependability and assurance.

In this stage, we will:
- Export Kubernetes (k8s) resources to [version control](https://www.atlassian.com/git/tutorials/what-is-version-control#benefits-of-version-control)
  - Can be alongside the application or in a separate repository
- Create a simple [CI/CD pipeline](https://www.redhat.com/en/topics/devops/what-is-ci-cd) that:
  - Runs your defined tests
  - Deploys new application code on demand
  - Deploys updates to Kubernetes resources required by the application
    - Ideally, this should work from and to any possible state

Once you have a completed pipeline, I recommend cleaning up any technical debt that resulted from Step 1. You should also implement anything that you left out of the proof of concept that you require for a working, production-ready application (from an application perspective, not necessarily from an ops perspective). I purposefully delay dealing with these issues until we have a working pipeline to utilise the benefits of the pipeline when implementing these more difficult features.

I will showcase a simple series of CI/CD pipelines using [Jenkins OpenShift Pipelines](https://docs.openshift.com/container-platform/3.11/dev_guide/openshift_pipeline.html) for the bookinfo project in Part 3 of the series.


### Set up CD for multiple environments

Lastly, we will need to reconfigure the CD pipelines we created in the previous step to add the ability to deploy to multiple environments. I like to keep this step separate from the previous one as it usually involves some extra steps, configuration & templating of the k8s resources. You can also implement this in many ways.

In Part 4 of the series, I will show how you can implement a very basic multi-environment CD pipeline in Jenkins with no external software.


### Further Considerations

Now, I haven't aimed to cover every single aspect of running an application on OpenShift, but here a few things that I haven't covered that you may want to consider investigating once you have reached this stage in your journey:

- Manage your k8s resources with [GitOps](https://blog.openshift.com/introduction-to-gitops-with-openshift/)
  - You should already be part-way there, as the pipelines already source the k8s resources from version control
- [Improved secrets management](https://blog.openshift.com/managing-secrets-openshift-vault-integration/) with something like [HashiCorp Vault](https://www.vaultproject.io/)
- Persistent storage backup/redundancy/lifecycle
  - Very dependant on your specific environment and needs


### Wrap-up
  
  At this stage, you should have a pretty decent series of application pipelines up & running. These deployments should be enough to start slowly migrating your traffic and environments to the new OpenShift instances. You should also have an understanding of the steps and principles to start such a journey anew.

