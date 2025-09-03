# Solution

## Files provided

`makefile`: A makefile to help with the creation/deletion of the cluster, deployment of app, deploying of monitoring (opentelemetry), gitops(prefered tool is fluxCD)

`kind-three-node`: Simple three node cluster with 2 workers and one controlplane

## Part 1 – Kubernetes Setup:

- Provided kind-three-node (Used Kind)
- Started my Makefile and run the application after some errors with the 5000 port on mac (Did you know that airplay receiver run there? neither did i.)

## Part 2 – Application Refining

- Create a Secret and configmap as stated by the assignement.md
- Add PDB in case there is a running rollout of new nodes and the deployment shuts all pods. Yes this is a stateless app, and maybe nobody notices.
- Add Affinity to the pod to choose all workers that the operator "controlplane" doesn't exist (cheeky i know. I played with what Kind gives me without adding anything else). I could have added a taint to the node of NoSchedule to not allow any workloads. 
- Created Netpols to deny traffic by default and allow traffice from the same namespace and from the monitoring namespace. Felt cute. maybe i create an opencollector and scrap metrics
- Added RBAC for the app service account to be able to read secrets/Configmaps
- Set the Deployment Replicas to 2 and a PDB of 50% so we never run out. 
- For the purpose of storings secrets as encrypted (safe) and not viewable by anyone.. in a production environment i would choose installing the ESO operator and the AWS external secret store named AWS Secret Manager. ConfigMaps are generaly for not so-sensitive data so maybe leave them as is? 
- Added Minimum HPA for the deployment, 2-5 pods can run simultanusly. In the context of a bigger infrastructure, maybe we could run a custom metric 
- Added Egress for DNS
- Added Namespace Labels, TODO: Add Labels to all resources
- Added Quotas and limit ranges for Namespace
- Added labels for all resources 

TODO: - the metrics-api server creation is missing some flag in the creation. the prompt returns fail and the metrics server is up 
TODO: - if i need metrics with prometheus i might need to enable the netpol and add metrics scrape annotations. (line 273 on the manifest)

- Network policy tweaks: If i have other services in the cluster then i need
- Add Egress UDP 53 for DNS requests 
- Add Egress/Ingress from those namespaces
