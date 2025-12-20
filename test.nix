dirname: inputs: {
    writeShellScriptBin, writeShellScript, dockerTools, extract-docker-image, coreutils, util-linux, time, jq, podman, emptyDirectory,
}: let
    lib = inputs.self.lib.__internal__;
    images = lib.mapAttrs (name: imageAttrs: (extract-docker-image (dockerTools.pullImage imageAttrs)) // {
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
    imageNames = lib.mapAttrs (_: image: "${image.finalImageName}:${image.finalImageTag}") images;
    infos = lib.mapAttrs (_: image: image.info) images;

    # setupImageTar = dockerTools.saveImage setupImage;
    mySetupScript = writeShellScript "my-setup-script" ''
        new=$1 ; shift ; cmd=$1 ; shift ; cwd=$1 ; shift
        set -x # enable command echoing for debugging

        # If no command arguments provided, use the default cmd from config
        if [[ $# -eq 0 ]]; then
            echo "[DEBUG] No command arguments provided" >&2
            if [[ -n "$cmd" ]]; then
                echo "[DEBUG] Using default cmd from config: $cmd" >&2
                set -- $cmd
            fi
        fi

        # Print script arguments
        ( :  "$@" )

        ${coreutils}/bin/mkdir -p /run || exit
        ${util-linux}/bin/mount -t tmpfs tmpfs /run || exit
        ${util-linux}/bin/mount --bind /nix $new/nix || exit

        # debug: list paths
#        ${coreutils}/bin/ls -la $new || true
#        ${coreutils}/bin/ls -la $new/$old || true

        # ensure pseudo-filesystems exist inside the new root
#        ${coreutils}/bin/mkdir -p $new/{proc,sys,tmp,dev} || true # read-only
        ${util-linux}/bin/mount -t proc proc $new/proc || true
        ${util-linux}/bin/mount -t sysfs sysfs $new/sys || true
        ${util-linux}/bin/mount -t tmpfs tmpfs $new/tmp || true
        ${util-linux}/bin/mount --bind /dev $new/dev || true

        cd /
        exec ${coreutils}/bin/chroot $new ${writeShellScript "chroot-script" ''
            # / is now the previous $new, . is still the previous /
            cwd=$1 ; shift
            set -x
#            ${coreutils}/bin/ls -la . || true

            ${util-linux}/bin/umount --lazy --recursive /nix || true
            cd / || exit
            cd $cwd || exit
            exec "$@"
        ''} "$cwd" "$@"
    '';
in writeShellScriptBin "test" ''
    # we want to behave like »docker run [OPTIONS] IMAGE [COMMAND] [ARG...]«
    debug() {
        >&2 echo "[DEBUG] $@"
    }
    debug "Arguments: $@"
    native=0
    run_number=0
    index_number=0
    flags=() ; while [[ $# != 0 ]]; do
        debug "Processing argument: $1"
        if [[ $1 == -- ]]; then
            shift
            debug "Breaking loop"
            break
        fi
        if [[ $1 == --native ]]; then
            native=1
            shift
            debug "Native mode enabled"
            continue
        fi
        if [[ $1 == --run ]]; then
            shift
            run_number="$1"
            shift
            debug "Run number set to: $run_number"
            continue
        fi
        if [[ $1 == --index ]]; then
            shift
            index_number="$1"
            shift
            debug "Index number set to: $index_number"
            continue
        fi
        flags+=( "$1" )
        debug "Added to flags: $1"
        shift
    done
    declare -A images=( ${lib.fun.asBashDict { } images} )
    declare -A imageNames=( ${lib.fun.asBashDict { } imageNames} )
    declare -A infos=( ${lib.fun.asBashDict { } infos} )
    requested_image_name="$1"
    image=''${images[$requested_image_name]:-}
    imageName=''${imageNames[$requested_image_name]:-}
#
#    debug "Requested image name: $requested_image_name"
#    debug "Resolved image path: $image"
#    debug "Resolved image full name: $imageName"

    info=''${infos[$requested_image_name]:-}

    # Extract cmd and cwd from config.json
    if [[ -f "$info/config.json" ]]; then
        default_cmd=$(${jq}/bin/jq -r '.config.Cmd // [] | join(" ")' "$info/config.json")
        default_cwd=$(${jq}/bin/jq -r '.config.WorkingDir // "/"' "$info/config.json")
    else
        default_cmd=""
        default_cwd="/"
    fi
    debug "default_cmd from config: $default_cmd"
    debug "default_cwd from config: $default_cwd"

    # advance past the image name so $@ contains only the positionals (command + args)
    shift
    positionals=( "$@" )
    debug "Flags: ''${flags[@]}"
    debug "Positionals: ''${positionals[@]}"
    if [[ -z "$image" ]] ; then echo "unexpected image '$requested_image_name'" >&2 ; exit 1 ; fi
    if [[ ! -d "$image" ]] ; then echo "image path '$image' not found or not a directory" >&2 ; exit 1 ; fi

    mkdir -p evaluation
    log_file="evaluation/log.log"

    # Add CSV header if log file doesn't exist
    if [[ ! -f "$log_file" ]]; then
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "timestamp" "type" "image_name" "run_number" "index_number" "command" \
            "elapsed_time_s" "user_cpu_time_s" "system_cpu_time_s" "cpu_percent" \
            "max_rss_kb" "avg_rss_kb" "major_page_faults" "minor_page_faults" \
            "involuntary_context_switches" "exit_code" > "$log_file"
    fi

    # Set type based on native flag
    if [[ $native -eq 1 ]]; then
        run_type="native"
    else
        run_type="nix"
    fi

#    debug "Podman history for $imageName:"
#    ${lib.getExe podman} history "$imageName" >&2 || true

    if [[ $native -eq 1 ]]; then
        cmd=(
            ${lib.getExe podman} run
            --rm
            --privileged
            "''${flags[@]}"
            "$imageName"
            "''${positionals[@]}"
        )
    else
        load_output=$(${lib.getExe podman} load -i ${inputs.self.packages.x86_64-linux.empty-image} 2>&1)
        # Extract the reference from load output (Loaded image: ...)
        loaded_image_name=$(echo "$load_output" | grep -i "Loaded image:" | sed 's/.*Loaded image: *//' | head -n1)

#    debug "Podman history for $loaded_image_name:"
#    ${lib.getExe podman} history "$loaded_image_name" >&2 || true


        [[ -n "$loaded_image_name" ]] || { >&2 echo "[ERROR] No image found after loading. Load output: $load_output"; exit 1; }
        cmd=(
            ${lib.getExe podman} run
            --rm # remove container after exit
            --privileged # allow mounts inside the container
            -v /nix:/nix:ro
            "''${flags[@]}"
            --entrypoint ${mySetupScript}
            "$loaded_image_name"
            $image "$default_cmd" "$default_cwd" "''${positionals[@]}"
        )
    fi

    # Prepare command string (with proper quoting)
    cmd_str=$( printf " %q" "''${cmd[@]}" )
    # Escape command for CSV: wrap in quotes and escape internal quotes by doubling them
    cmd_str_csv="\"''${cmd_str//\"/\"\"}\""

    # Create temp file to capture time output
    time_output_file=$(mktemp)

    # CSV Log format:
    # 1. Timestamp: Unix timestamp when the command was executed.
    # 2. Type: 'native' or 'nix' to distinguish the run type.
    # 3. Image Name: The name of the Docker image being tested.
    # 4. Run Number: Test run identifier (multiple stages per run).
    # 5. Index Number: Stage index within the run (counting upwards).
    # 6. Command: The full command that was executed (CSV escaped).
    # Time metrics from https://man7.org/linux/man-pages/man1/time.1.html:
    # 7. %e - elapsed_time_s: Elapsed Real Time (s): Total time taken for the command to execute.
    # 8. %U - user_cpu_time_s: User CPU Time (s): Time spent in user mode.
    # 9. %S - system_cpu_time_s: System CPU Time (s): Time spent in kernel mode.
    # 10. %P - cpu_percent: CPU Percentage: CPU usage percentage ((user + system) / real).
    # 11. %M - max_rss_kb: Max Resident Set Size (KB): Maximum physical memory used.
    # 12. %t - avg_rss_kb: Avg Resident Set Size (KB): Average physical memory used.
    # 13. %F - major_page_faults: Major Page Faults: Page faults requiring disk I/O.
    # 14. %R - minor_page_faults: Minor Page Faults: Page faults not requiring disk I/O.
    # 15. %c - involuntary_context_switches: Involuntary Context Switches: Number of times the process was involuntarily context-switched.
    # 16. Exit Code: Docker exec exit code.
    ${time}/bin/time -f "%e,%U,%S,%P,%M,%t,%F,%R,%c"  --quiet --output "$time_output_file" "''${cmd[@]}"

    exit_code=$? # exit status of most recently executed foreground command

    # Read time output (strip trailing newline with tr) and write complete line to log
    time_metrics=$(cat "$time_output_file" | tr -d '\n\r')
    rm -f "$time_output_file"

    printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$(date +%s)" "$run_type" "$requested_image_name" "$run_number" "$index_number" "$cmd_str_csv" "$time_metrics" "$exit_code" >>$log_file

    exit $exit_code
''
