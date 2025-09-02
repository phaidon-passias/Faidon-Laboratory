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


