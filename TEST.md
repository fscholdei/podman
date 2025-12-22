
## Test Steps
1. make clean
2. make bin/podman
3. podman images
4. podman image rm -f tomcat
5. ./bin/podman --log-level=info run -it docker.io/tomcat


## Changes
* runtime.go, Init Nixstore
* Definition in nixstore.go and image_loader.go
* Image lockup in local through container.go

## Mounts
Suche nach `spec.Mount`:
* Linux-Defaults `/proc`, `/dev`, `/dev/{pts,shm,mqueue}`, `/sys` in `runtime-tools/generate/generate.go`
* Dann Podman-Tweaks `/sys`, `/sys/fs/cgroup`, `/dev/{pts,mqueue}`, `/proc` in `pkg/specgen/generate/oci_linux.go`
* Sowie Image-Volumes und `tmpfs` in `storage.go`, (`specgen.go`, `podmanspecgen.go`) 


The nixbld group is used by Nix to run builds in a sandboxed environment.
This typically happens on non-NixOS systems if Nix is not fully configured. To fix this, you need to create the nixbld group on your system.
You can do this by running the following command in your terminal:
sudo groupadd --system nixbld


sudo usermod -aG nixbld flo