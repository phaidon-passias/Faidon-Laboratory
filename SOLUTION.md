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
- Network policy tweaks: If i have other services in the cluster then i need
- Add Egress UDP 53 for DNS requests 
- Add Egress/Ingress from those namespaces
- Fixed more makefile targets and created scripts to create the cluster, push services, load test and teardown the cluster

## How to run (scripts)

### 1) Setup everything

```bash
chmod +x setup-all.sh teardown-all.sh hpa-demo.sh
./setup-all.sh
```

What it does:
- Creates kind cluster + local registry, installs metrics-server
- Builds and pushes the app image to `localhost:5000`
- Applies manifests and waits for rollout

If you see a message about port 5000 being in use, it means a registry (or AirPlay on macOS) already binds that port. Either stop it or skip starting another registry.

### 2) Drive HPA scaling and observe

Start load and 60s monitoring snapshots:
```bash
HPA_CONCURRENCY=200 HPA_DURATION=60 ./hpa-demo.sh run
```

Alternatively, live watch:
```bash
./hpa-demo.sh watch
```

### 3) Teardown everything

```bash
./teardown-all.sh
```

What it does:
- Deletes the `app` namespace and resources
- Stops any lingering port-forward
- Deletes the kind cluster and stops the local registry



TODO: - if i need metrics with prometheus i might need to enable the netpol and add metrics scrape annotations. (line 273 on the manifest)
TODO: Add building and pushing images to the CI pipeline in makefile
TODO: Specify the LOAD AND VERIFICATION OF HPA SCALES
TODO: Add "hey as a formula that i use for my setup for HPA"

## PART3: Fixing a bug with the application- metrics related issue

There was a logical issue with when reporting latency, previously it only recorded latency for failed requestes.
I added some code to help with reporting also successfull request. Now all requested with contribute to latency metrics. If we were to scale based on latency metrics then we would face the issue that we would have incoherent data.
If the problem statement behind the decision of reporting only the failed requests would be monitoring i'd suggest filter or drop a percentage of the successfull requests in your OTEL Collector. 
I see a problem if I'd set an SLA based on percentiles on this metric. Also questions like "how much Load i can handle before the service is degrades are not answered.

I'd revert if its a dev only application and i don't care about further analysis or if i have a storage issue (from our last interview Robert noted that the biggest "cost-issue" kaiko is facing is storage. I'd have to do an analysis on whether this service is critical enough)(on the other hand prometheus is very efficient in storage, i wouldn't consider it a problem)

Theoretically it would skew our metrics because 
`Current broken behavior`:
Failed requests: Record latency ✅
Successful requests: Don't record latency ❌
Result: Our Prometheus histogram only would contain data from failed requests, which means:
Average latency is artificially high (only failures, which might be slower)
Percentiles are wrong (P50, P95, P99 based on incomplete data)
HPA decisions could be wrong if you're scaling on latency metrics
Monitoring dashboards show misleading performance data