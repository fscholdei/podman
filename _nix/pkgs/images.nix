dirname: inputs: {
    lib, pkgs, dockerTools, extract-docker-image,
}: let
  image-list = import ./image-list.nix;
  images = lib.mapAttrs (name: imageAttrs: (extract-docker-image (dockerTools.pullImage imageAttrs))) image-list;
in
let
  imagesJson = pkgs.runCommand "images.json-data" { } ''
    cat <<EOF > $out
    {
      "images": {
        ${lib.concatStringsSep "," (lib.mapAttrsToList (name: image: ''
          "${name}": {
            "rootfs": "${image.out}",
            "manifest": "${image.info}/manifest.json",
            "config": "${image.info}/config.json"
          }
        '') images)}
      }
    }
    EOF
  '';
in
pkgs.runCommand "images.json" { } ''
  mkdir -p $out/bin
  cat <<EOF > $out/bin/images.json
  #!${pkgs.runtimeShell}
  cat ${imagesJson}
  EOF
  chmod +x $out/bin/images.json
''

