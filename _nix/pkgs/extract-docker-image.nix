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
    layers=( $( ${jq}/bin/jq -r '.[0].Layers|.[]' manifest.json ) )
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
    # Copy the main manifest file.
    ${jq}/bin/jq '.[0]' manifest.json > $info/manifest.json
    # Copy the image config file.
    config=$( ${jq}/bin/jq -r '.[0].Config' manifest.json || true )
    [[ ! $config ]] || cp ./"$config" $info/config.json
    # Create a file with layer sizes and names.
    stat --printf='%s\t%n\n' "''${layers[@]}" | LC_ALL=C sort -k2 > $info/layers
''
