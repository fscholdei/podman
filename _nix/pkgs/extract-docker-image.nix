# This function extracts the contents of a Docker image tarball.
# It takes an image path (as produced by pkgs.dockerTools.pullImage)
# and produces a directory with the merged filesystem of all layers.
# It also produces an "info" output with metadata about the image.
dirname: inputs: {
    runCommandLocal, jq,
lib }: image: let # result of pkgs.dockerTools.pullImage
    name = if lib.isString image then "container-image" else "docker-image-${image.imageName}-${image.imageTag}";

in runCommandLocal name {
    inherit image; outputs = [ "out" ];
    jq = "${jq}/bin/jq";
} ''
    set -x
    # Unpack the image tarball provided by dockerTools.pullImage
    tar -xf $image
    ls -al .
    # Extract layer tarball names and config from manifest.json
    eval $($jq -r '
      if type == "array" then .[0] else . end
      | "layers=(\(.Layers|map(select(. != null))|join(" "))) config=\(.Config)"
    ' manifest.json)
    tmp_out=$(mktemp -d)
    # Process layers in order
    for layer in "''${layers[@]}" ; do
        # First, process whiteout files to remove deleted files from previous layers.
        # See https://github.com/opencontainers/image-spec/blob/main/layer.md#whiteout-files
        tar --anchored --exclude='dev/*' -tf $layer | ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            if [[ $path == */.wh..wh..opq ]] ; then
                # Opaque whiteout: remove all files in the directory
                ( shopt -s dotglob ; rm -rf $tmp_out/"''${path%%.wh..wh..opq}"/* )
            else
                # Regular whiteout: remove a single file
                name=$( basename "$path" ) ; rm -rf $tmp_out/"$( dirname "$path" )"/''${name##.wh.}
            fi
        done
        # Then, extract the layer contents into the output directory.
        # We also remove the whiteout files themselves during extraction.
        tar --anchored --exclude='dev/*' -C $tmp_out -xf $layer -v |
        ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            name=$( basename "$path" ) ; rm -rf $tmp_out/"$path"
        done
        # Make all extracted files writable.
        chmod -R +w $tmp_out
    done

    # --- Populate the "out" output ---
    mkdir -p $out

    # Make tar archive out of $tmp_out and save it in out dir
    tar -C $tmp_out -cf $out/rootfs.tar .

    # Calculate the DiffID of the new layer (sha256 of uncompressed tarball)
    diff_id_sha256=$(sha256sum "$out/rootfs.tar" | cut -d' ' -f1)

    # Create a new config file with the correct DiffID and cleared history
    updated_config_json=$( $jq \
      --arg diff_id "sha256:$diff_id_sha256" \
      --arg created "$(date -Iseconds --utc)" \
      ' .rootfs.diff_ids = [$diff_id] | .history = [{"created": $created, "created_by": "nix", "comment": "Unpacked file trees"}] | .created = $created' \
      "$config")
    echo "$updated_config_json" > "$out/config.json"

    # Generate OCI-compliant manifest using the new config
    config_file_name="$out/config.json"
    config_sha256=$(sha256sum "$config_file_name" | cut -d' ' -f1)
    config_size=$(stat -c%s "$config_file_name")

    # Move config file to out output, named by its digest
    mv "$config_file_name" "$out/$config_sha256"

    # Generate layers JSON for the rootfs tarball
    layer_path="$out/rootfs.tar"
    layer_digest_hash="$(sha256sum "$layer_path" | cut -d' ' -f1)"
    layer_digest_full="sha256:$layer_digest_hash"
    layer_size=$(stat -c%s "$layer_path")
    layers_json=$( $jq -n \
        --argjson size "$layer_size" \
        --arg digest "$layer_digest_full" \
        '[{
            "mediaType": "application/vnd.oci.image.layer.v1.tar",
            "digest": $digest,
            "size": $size
        }]'
    )
    mv "$layer_path" "$out/$layer_digest_hash"

    # Assemble the final manifest
    $jq -n \
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
      }' > "$out/manifest.json"
''
