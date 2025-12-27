# This function extracts the contents of a Docker image tarball.
# It takes an image path (as produced by pkgs.dockerTools.pullImage)
# and produces a directory with the merged filesystem of all layers.
# It also produces an "info" output with metadata about the image.
dirname: inputs: {
    runCommandLocal, jq,
lib }: image: let # result of pkgs.dockerTools.pullImage
    name = if lib.isString image then "container-image" else "docker-image-${image.imageName}-${image.imageTag}";

in runCommandLocal name {
    inherit image; outputs = [ "out" "info" ];
} ''
    set -x
    # Unpack the image tarball provided by dockerTools.pullImage
    tar -xf $image
    ls -al .
    # Extract layer tarball names from manifest.json
    layers=( $( ${jq}/bin/jq -r 'if type == "array" then .[0] else . end | .Layers|.[]' manifest.json ) )
    config=$( ${jq}/bin/jq -r 'if type == "array" then .[0] else . end | .Config' manifest.json )
    mkdir -p $out
    # Process layers in order
    for layer in "''${layers[@]}" ; do
        # First, process whiteout files to remove deleted files from previous layers.
        # See https://github.com/opencontainers/image-spec/blob/main/layer.md#whiteout-files
        tar --anchored --exclude='dev/*' -tf $layer | ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            if [[ $path == */.wh..wh..opq ]] ; then
                # Opaque whiteout: remove all files in the directory
                ( shopt -s dotglob ; rm -rf $out/"''${path%%.wh..wh..opq}"/* )
            else
                # Regular whiteout: remove a single file
                name=$( basename "$path" ) ; rm -rf $out/"$( dirname "$path" )"/''${name##.wh.}
            fi
        done
        # Then, extract the layer contents into the output directory.
        # We also remove the whiteout files themselves during extraction.
        tar --anchored --exclude='dev/*' -C $out -xf $layer -v |
        ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            name=$( basename "$path" ) ; rm -rf $out/"$path"
        done
        # Make all extracted files writable.
        chmod -R +w $out
    done

    # Create some standard directories that might be expected.
    # much ugly
    mkdir -p -m1777 $out/tmp
    mkdir -p -m755 $out/nix


    # --- Populate the "info" output ---
    mkdir -p $info

    # Generate OCI-compliant manifest
    config_file_name=$config
    config_sha256=$(sha256sum "$config_file_name" | cut -d' ' -f1)
    config_size=$(stat -c%s "$config_file_name")

    # Copy config file to info output, named by its digest
    cp "$config_file_name" "$info/$config_sha256"

    # Generate layers JSON and copy layers
    layers_json="[]"
    for layer in "''${layers[@]}"; do
        layer_digest_hash="$(sha256sum "$layer" | cut -d' ' -f1)"
        layer_digest_full="sha256:$layer_digest_hash"
        layer_size=$(stat -c%s "$layer")
        layers_json=$(echo "$layers_json" | ${jq}/bin/jq --argjson size "$layer_size" --arg digest "$layer_digest_full" '. + [{mediaType: "application/vnd.oci.image.layer.v1.tar+gzip", digest: $digest, size: $size}]')
        cp "$layer" "$info/$layer_digest_hash"
    done

    # Assemble the final manifest
    ${jq}/bin/jq -n \
      --argjson config_size "$config_size" \
      --arg config "sha256:$config_sha256" \
      --argjson layers "$layers_json" \
      '{
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
          "mediaType": "application/vnd.oci.image.config.v1+json",
          "digest": $config,
          "size": $config_size
        },
        "layers": $layers
      }' > "$info/manifest.json"

      stat --printf='%s\t%n\n' "''${layers[@]}" | LC_ALL=C sort -k2 > $info/layers
''
