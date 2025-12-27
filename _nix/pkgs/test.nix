dirname: inputs: {
    writeShellScriptBin, writeShellScript, dockerTools, extract-docker-image,
}: let
    lib = inputs.self.lib.__internal__;
    imageDerivations = lib.mapAttrs (name: imageAttrs: (extract-docker-image (dockerTools.pullImage imageAttrs)) // {
      inherit (imageAttrs) finalImageName finalImageTag;
    }) {
        # use `nix-prefetch-docker --os linux <image>` to get these:
        python = { arch = "amd64"; os = "linux"; } // {
          imageName = "python";
          imageDigest = "sha256:a6af772cf98267c48c145928cbeb35bd8e89b610acd70f93e3e8ac3e96c92af8";
          hash = "sha256-JgQyAIf8h3rSiDx5xo5pYdLg9RQO1sTQrQey5vUpEVc=";
          finalImageName = "python";
          finalImageTag = "3.10.6-alpine";
        };
        hello-world = { arch = "amd64"; os = "linux"; } // {
          imageName = "hello-world";
          imageDigest = "sha256:6dc565aa630927052111f823c303948cf83670a3903ffa3849f1488ab517f891";
          hash = "sha256-kclFt+m19RWucr8o1QxlCxH1SH7DMoS6H+lsIGFUwLY=";
          finalImageName = "hello-world";
          finalImageTag = "latest";
        };
        php = { arch = "amd64"; os = "linux"; } // {
          imageName = "php";
          imageDigest = "sha256:277cad196d7bcc9120e111b94ded8bfb8b9f9f88ebeebf6fd8bec2dd6ba03122";
          hash = "sha256-YERyqIw6IGx3zQ+OBQz/EQ/PGqNdzVdlHnYOrSjdXzU=";
          finalImageName = "php";
          finalImageTag = "latest";
        };
        tomcat = { arch = "amd64"; os = "linux"; } // {
          imageName = "tomcat";
          imageDigest = "sha256:1fb0037abb88abb3ff2fbeb40056f82f616522a92f1f4f7dc0b56cdb157542db";
          hash = "sha256-FAEn/msK3Ds4ecr7Z2YqJ+WBpD2tmBiOco4S7+Qc+vI=";
          finalImageName = "tomcat";
          finalImageTag = "latest";
        };
        nextcloud = { arch = "amd64"; os = "linux"; } // {
          imageName = "nextcloud";
          imageDigest = "sha256:f9bec5c77a8d5603354b990550a4d24487deae6e589dd20ce870e43e28460e18";
          hash = "sha256-KkUy9S7Zd8Z1AxVB8fSSGkeSWO/yYysdfK14mPB9d/o=";
          finalImageName = "nextcloud";
          finalImageTag = "latest";
        };
        python-numpy = { arch = "amd64"; os = "linux"; } // {
          imageName = "quoinedev/python3.7-pandas-alpine";
          imageDigest = "sha256:1be9b10c0ce3daf62589b0fabcc2585372eaad4783c74d08bcb137142d52c9ea";
          hash = "sha256-qhZZfICVjU9+4p+VghuPA09n/KE2CHKmRsNXNnZZQCc=";
#          finalImageName = "quoinedev/python3.7-pandas-alpine";
          finalImageName = "docker.io/quoinedev/python3.7-pandas-alpine";
          finalImageTag = "latest";
        };
    };
    images = lib.mapAttrs (_: image: image.out) imageDerivations;
    imageNames = lib.mapAttrs (_: image: "${image.finalImageName}:${image.finalImageTag}") imageDerivations;
    infos = lib.mapAttrs (_: image: image.info) imageDerivations;
    imageInfo = lib.mapAttrsToList (name: value: "${value.finalImageName}:${value.finalImageTag} to ${value.out}") imageDerivations;

in writeShellScriptBin "test" ''
    >&2 echo "Done preparing docker images: ${lib.concatStringsSep ",\n" imageInfo}"
''
