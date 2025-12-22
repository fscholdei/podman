dirname: inputs: {
    runCommandLocal, jq,
lib }: image: let # result of pkgs.dockerTools.pullImage
    name = if lib.isString image then "container-image" else "docker-image-${image.imageName}-${image.imageTag}";

in runCommandLocal name {
    inherit image; outputs = [ "out" "info" ];
} ''
    set -x
    tar -xf $image
    ls -al .
    layers=( $( ${jq}/bin/jq -r '.[0].Layers|.[]' manifest.json ) )
    mkdir -p $out
    for layer in "''${layers[@]}" ; do
        tar --anchored --exclude='dev/*' -tf $layer | ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            if [[ $path == */.wh..wh..opq ]] ; then
                ( shopt -s dotglob ; rm -rf $out/"''${path%%.wh..wh..opq}"/* )
            else
                name=$( basename "$path" ) ; rm -rf $out/"$( dirname "$path" )"/''${name##.wh.}
            fi
        done
        tar --anchored --exclude='dev/*' -C $out -xf $layer -v |
        ( grep -Pe '(^|/)[.]wh[.]' || true ) | while IFS= read -r path ; do
            name=$( basename "$path" ) ; rm -rf $out/"$path"
        done
        chmod -R +w $out
    done

    # much ugly
    mkdir -p -m1777 $out/tmp
    mkdir -p -m755 $out/nix


    mkdir -p $info
    ${jq}/bin/jq '.[0]' manifest.json > $info/manifest.json
    config=$( ${jq}/bin/jq -r '.[0].Config' manifest.json || true )
    [[ ! $config ]] || cp ./"$config" $info/config.json
    stat --printf='%s\t%n\n' "''${layers[@]}" | LC_ALL=C sort -k2 > $info/layers
''
