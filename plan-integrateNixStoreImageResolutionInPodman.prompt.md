## Plan: Integrate Nix Store Image Resolution in Podman

This updated plan refines the approach for integrating Nix-based image management directly into Podman. It leverages Nix's command-line tools for reliable store path resolution. This will enable `podman run <image-name>` for images present in the Nix store, making the process seamless.

### Steps

1.  **Define Images in a Nix File**: Instead of JSON, we'll use a Nix file (e.g., `~/.config/podman/images.nix`) to define the images. This allows us to leverage the full power of Nix. This file will look very similar to the `images` attribute set in `test.nix`. It will use the existing `extract-docker-image.nix` implementation.

    ```nix
    # ~/.config/podman/images.nix
    { pkgs ? import <nixpkgs> {} }:

    let
      extract-docker-image = import /path/to/extract-docker-image.nix { inherit pkgs; };
    in
    {
      "python:3.10.6-alpine" = extract-docker-image (pkgs.dockerTools.pullImage {
        imageName = "python";
        imageDigest = "sha256:a6af772cf98267c48c145928cbeb35bd8e89b610acd70f93e3e8ac3e96c92af8";
        hash = "sha256-JgQyAIf8h3rSiDx5xo5pYdLg9RQO1sTQrQey5vUpEVc=";
        finalImageName = "python";
        finalImageTag = "3.10.6-alpine";
        os = "linux";
        arch = "amd64";
      });
      # ... other images
    }
    ```

2.  **Resolve Image Path with `nix eval`**: In `pkg/nixstore/nixstore.go`, when resolving an image, Podman will construct and execute a `nix eval` command. This command will evaluate the `images.nix` file and return the store path for the requested image. If the command fails, a clear error message will be provided and the process will exit.

    For an image named `python:3.10.6-alpine`, the command would be:

    ```bash
    nix eval --raw --file ~/.config/podman/images.nix --apply 'img: img."python:3.10.6-alpine"'
    ```

    This command will directly return the final Nix store path, like `/nix/store/s39hyv9ndvyaq1da99mhk9jcwpqg6bdv-docker-image-python-3.10.6-alpine`, which can then be used by the image loader. This avoids intermediate derivation paths and is much cleaner.

3.  **Enhance image name resolution**: Modify Podman's image pull logic in `libpod/runtime.go`. When an image is not found locally, it should check for the image using the Nix resolution mechanism before attempting to pull from a remote registry.

4.  **Adapt image loading for Nix**: Update the `loadImageFromNixStore` function in `pkg/nixstore/image_loader.go` to use the resolved Nix store path from the previous step. This function will handle the directory structure of the extracted Docker image in the Nix store, loading the image manifest, configuration, and layers into Podman's storage.

### Further Considerations
1. **Configuration Discovery**: Podman should search for `images.nix` in standard locations, such as `/etc/podman/` for system-wide configuration and `~/.config/podman/` for user-specific overrides.
2. **Performance**: Executing `nix` commands may introduce latency. We should consider caching the resolved store paths to speed up subsequent lookups.
3. **Error Handling**: The integration should gracefully handle cases where the `nix` command is not available or fails, providing clear error messages to the user.

