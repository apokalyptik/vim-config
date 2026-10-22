# Sourced by launchers; no processes or host probes are needed here.
# These reduce concurrency. They are not a kernel-enforced process/thread cap.
vim_config_set_resources() {
    case "$1" in
        container)
            export VIM_CONFIG_LOW_RESOURCE=1
            export GOMAXPROCS=1
            export GOMEMLIMIT="${GOMEMLIMIT:-256MiB}"
            export UV_THREADPOOL_SIZE=1
            export RAYON_NUM_THREADS=1
            export TOKIO_WORKER_THREADS=1
            # A server launcher and its guarded helper share this policy.
            # Reassert scalar limits each time, append flags only once.
            if [ "${VIM_CONFIG_RESOURCE_POLICY-}" != container-v1 ]; then
                export GOFLAGS="${GOFLAGS-} -mod=readonly -p=1"
                export NODE_OPTIONS="${NODE_OPTIONS-} --v8-pool-size=1"
            fi
            export VIM_CONFIG_RESOURCE_POLICY=container-v1
            ;;
        *) export VIM_CONFIG_LOW_RESOURCE=0 VIM_CONFIG_RESOURCE_POLICY= ;;
    esac
}
