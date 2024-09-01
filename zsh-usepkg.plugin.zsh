#!/usr/bin/zsh
# SPDX-License-Identifier: MIT
# a minimal declarative zsh plugin manager
# by gynamics

# debug toggle
export USEPKG_DEBUG=${USEPKG_DEBUG:=false}
# message toggle
export USEPKG_SILENT=${USEPKG_SILENT:=true}
# directory to store git repositories
export USEPKG_DATA=${USEPKG_DATA:=${HOME}/.local/share/zsh-usepkg}

function usepkg-error() {
    echo -e "\e[31m[USEPKG_ERROR]\e[0m $*" >&2
}

function usepkg-message() {
    if ! $USEPKG_SILENT; then
        echo -e "\e[32m[USEPKG]\e[0m $*"
    fi
}

function usepkg-debug() {
    if $USEPKG_DEBUG; then
        echo -e "\e[33m[USEPKG_DEBUG]\e[0m $*" >&2
    fi
}

defpkg_keys=( :name :ensure :fetcher :from :path :branch :source :depends :after )

typeset -gA USEPKG_PKG_PROTO

function defpkg-satus() {
    local key
    local tuple
    for tuple in "${(s/ :/)*#:}"; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            USEPKG_PKG_PROTO[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done
}

typeset -gA USEPKG_PKG_STATUS

function usepkg-status() {
    case $1 in
        LOAD_FAILURE) # found but failed to load
            echo -ne "\e[31m[$1]\e[0m"
            ;;
        OK) # loaded successfully
            echo -ne "\e[32m[$1]\e[0m"
            ;;
        NOT_FOUND) # declared but not found
            echo -ne "\e[33m[$1]\e[0m"
            ;;
        READY) # package has been found
            echo -ne "\e[34m[$1]\e[0m"
            ;;
        DECL_ONLY) # just declared
            echo -ne "\e[35m[$1]\e[0m"
            ;;
        *) # otherwise
            echo -ne "\e[36m[$1]\e[0m"
            ;;
    esac
}

typeset -gA USEPKG_PKG_DECL

# declare one package
function defpkg() {
    typeset -A pkg

    # initialize pkg with default values
    local key
    for key in ${(k)USEPKG_PKG_PROTO}; do
        pkg[$key]="${USEPKG_PKG_PROTO[$key]}"
    done

    # parse recipe and save key-value pairs into an associate array
    local tuple
    for tuple in "${(s/ :/)*#:}"; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    # figure out :name and :source
    if [[ -n "${pkg[:path]}" ]]; then
        if [[ -z "${pkg[:name]}" ]]; then
            pkg[:name]="${pkg[:path]##*/}"
        fi

        if [[ -z "${pkg[:source]}" ]]; then
            pkg[:source]="${pkg[:name]}.plugin.zsh"
        fi
    else
        usepkg-error "Value under key :path can not be empty."
    fi

    # store it as a plist
    usepkg-debug "package declared: ${pkg[:name]}"
    USEPKG_PKG_DECL[${pkg[:name]}]=${(kv)pkg}
    USEPKG_PKG_STATUS[${pkg[:name]}]=DECL_ONLY
}

# check & fetch given package
function defpkg-ensure() {
    if [[ -z ${USEPKG_PKG_DECL[$1]} ]]; then
        return -22 # -EINVAL
    fi

    usepkg-debug "Checking package ${1} ..."

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)USEPKG_PKG_DECL[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    if [[ ${pkg[:fetcher]} == nope ]]; then
        if [[ ! -d ${pkg[:from]%/}/${pkg[:path]} ]]; then
            USEPKG_PKG_STATUS[$1]=NOT_FOUND
            if ${pkg[:ensure]}; then
                usepkg-error "Failed to find ${pkg[:from]%/}/${pkg[:path]}!"
                return -2 # -ENOENT
            else
                usepkg-debug "Failed to find ${pkg[:from]%/}/${pkg[:path]}!"
            fi
        else
            USEPKG_PKG_STATUS[$1]=READY
        fi
        return 0
    else
        if [[ ! -d ${USEPKG_DATA}/${pkg[:name]} ]]; then
            USEPKG_PKG_STATUS[$1]=NOT_FOUND
            if ${pkg[:ensure]}; then
                # fetch package (single thread)
                usepkg-message "Start fetching package ${pkg[:name]} ..."

                local ret=0
                case ${pkg[:fetcher]} in
                    git)
                        if [[ -n ${pkg[:branch]} ]]; then
                            git clone \
                                ${pkg[:from]%/}/${pkg[:path]} \
                                -b ${pkg[:branch]} \
                                ${USEPKG_DATA%/}/${pkg[:name]%/}
                        else
                            git clone \
                                ${pkg[:from]%/}/${pkg[:path]} \
                                ${USEPKG_DATA%/}/${pkg[:name]%/}
                        fi
                        ret=$?
                        ;;
                    curl)
                        mkdir -p ${USEPKG_DATA}/${pkg[:name]}
                        # here we simply download files needed
                        local f
                        for f in ${(s/ /)pkg[:source]}; do
                            curl ${pkg[:from]%/}/${pkg[:path]%/}/${f} \
                                 -o ${USEPKG_DATA%/}/${pkg[:name]%/}/${f}
                            ret=$?
                            if [[ $ret != 0 ]]; then
                                break
                            fi
                        done
                        ;;
                    *)
                        usepkg-error "Unknown fetcher ${pkg[:fetcher]}"
                        return -22 # -EINVAL
                        ;;
                esac

                if [[ $ret != 0 ]]; then
                    usepkg-error "Failed to fetch package ${pkg[:name]}"
                    return $ret
                else
                    USEPKG_PKG_STATUS[$1]=READY
                fi
            fi
        else
            USEPKG_PKG_STATUS[$1]=READY
        fi
        return 0
    fi
}

function defpkg-load() {
    if [[ -z ${USEPKG_PKG_DECL[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)USEPKG_PKG_DECL[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    usepkg-message "Loading package ${1} ..."

    # load weak deps
    for key in ${(s/ /)pkg[:after]}; do
        usepkg-debug "Found weak dependency $key ..."
        if [[ ${USEPKG_PKG_STATUS[$key]} != OK ]]; then
            defpkg-load "$key"
            if [[ $? != 0 ]]; then
                usepkg-debug "Dependency $key not found, continue."
            fi
        fi
    done

    # load strong deps
    for key in ${(s/ /)pkg[:depends]}; do
        usepkg-debug "Found strong dependency $key ..."
        if [[ ${USEPKG_PKG_STATUS[$key]} != OK ]]; then
            defpkg-load "$key"
            if [[ $? != 0 ]]; then
                usepkg-error "Dependency $key broken, abort."
                return -1
            fi
        fi
    done

    # load plugins
    local f
    local ent
    local ret
    for f in ${(s/ /)pkg[:source]}; do
        case "${pkg[:fetcher]}" in
            nope)
                ent=${pkg[:from]%/}/${pkg[:path]%/}/${f}
                ;;
            *)
                ent=${USEPKG_DATA%/}/${pkg[:name]%/}/${f}
                ;;
        esac

        if [[ -e "${ent}" ]]; then
            usepkg-debug "Loading file ${ent} ..."
            source ${ent}
            ret=$?
            if [[ $ret != 0 ]]; then
                USEPKG_PKG_STATUS[$1]=LOAD_FAILURE
                usepkg-error "Failed to load ${ent} !"
                return $ret
            fi
        else
            USEPKG_PKG_STATUS[$1]=LOAD_FAILURE
            if ${pkg[:ensure]}; then
                usepkg-error "Failed to find ${ent} !"
                return -2 # -ENOENT
            else
                usepkg-debug "Failed to find ${ent} !"
                return 0
            fi
        fi
    done
    USEPKG_PKG_STATUS[$1]=OK
    return 0
}

function defpkg-finis() {
    mkdir -p ${USEPKG_DATA}

    local pids=()
    local key
    set +m # hide monitor message
    # concurrent downloading
    for key in ${(k)USEPKG_PKG_DECL}; do
        defpkg-ensure "$key" & pids+=($!)
    done
    for pid in ${pids[@]}; do
        wait "$pid"
    done
    set -m # recover monitor message
    # sequential loading
    for key in ${(k)USEPKG_PKG_DECL}; do
        if [[ ${USEPKG_PKG_STATUS[$key]} == OK ]]; then
            continue # do not load a package twice
        fi
        defpkg-load "$key"
    done
}

function usepkg-update() {
    if [[ -z ${USEPKG_PKG_DECL[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)USEPKG_PKG_DECL[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    case ${pkg[:fetcher]} in
        git)
            usepkg-message "${pkg[:name]}.git: "\
                           $(git -C ${USEPKG_DATA%/}/${pkg[:name]} pull --rebase 2>&1)
            if [[ $? != 0 ]]; then
                local ret=$?
                usepkg-error "Failed to fetch package ${pkg[:name]}"
                return $ret
            fi
            ;;
        curl)
            mkdir -p ${USEPKG_DATA}/${pkg[:name]}
            local f
            for f in ${(s/ /)pkg[:source]}; do
                usepkg-debug "Fetching ${pkg[:from]%/}/${pkg[:path]%/}/${f} ..."
                curl ${pkg[:from]%/}/${pkg[:path]%/}/${f} \
                     -o ${USEPKG_DATA%/}/${pkg[:name]%/}/${f}
                if [[ $ret != 0 ]]; then
                    local ret=$?
                    usepkg-error "Failed to fetch file ${pkg[:name]}/${f}"
                    return $ret
                fi
            done
            ;;
        *)
            usepkg-message "${pkg[:name]} is not of updatable type."
            return -22 # -EINVAL
            ;;
    esac
}

function usepkg-remove() {
    if [[ -z ${USEPKG_PKG_DECL[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)USEPKG_PKG_DECL[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    if [[ ${pkg[:fetcher]} != nope ]]; then
        usepkg-message "Removing ${pkg[:name]} ..."
        rm -rf ${USEPKG_DATA%/}/${pkg[:name]}
    else
        usepkg-error "${pkg[:name]} is a local package\n" \
                     "local packages won't be removed, " \
                     "please remove it manually."
        return -1 # -EPERM
    fi
}

function usepkg() {
    local cmd="$1"

    case $cmd in
        help)
            echo "Usage: usepkg [command] [args..]"
            echo "Manage installed plugins."
            echo ""
            echo "Commands:"
            echo "help"
            echo "    show this help."
            echo "list"
            echo "    list installed packages in one line."
            echo "open [package]"
            echo "    open the directory of a package."
            echo "info [[package]..]"
            echo "    check information of a package."
            echo "update [[package]..]"
            echo "    update a list of packages."
            echo "    by default it runs git pull --rebase"
            echo "reload [[package]..]"
            echo "    reload a list of packages."
            echo "remove [[package]..]"
            echo "    remove a list of packages."
            echo "    local packages won't be removed."
            echo "status"
            echo "    list package loading status."
            echo "clean [[package]..]"
            echo "    remove undeclared packages in ${USEPKG_DATA}."
            echo ""
            ;;
        list)
            echo ${(k)USEPKG_PKG_DECL}
            ;;
        info)
            local key
            for key in ${@:2}; do
                if [[ -n $key && -n ${USEPKG_PKG_DECL[$key]} ]]; then
                    echo "package: $key"
                    echo "status: ${USEPKG_PKG_STATUS[$key]}"
                    echo "definition:"
                    local tuple=''
                    for tuple in ${(s/ :/)USEPKG_PKG_DECL[$key]#:}; do
                        echo "  :${tuple%% *} ${tuple#* }"
                    done
                else
                    echo "package $key not declared."
                fi
                echo ""
            done
            ;;
        open)
            if [[ -n $2 ]]; then
                cd ${USEPKG_DATA%/}/$2
            fi
            ;;
        update)
            local pids=()
            local key
            set +m
            for key in ${@:2}; do
                usepkg-update $key & pids+=($!)
            done
            for pid in ${pids[@]}; do
                wait $pid >/dev/null
            done
            set -m
            ;;
        reload)
            local pids=()
            local key
            set +m
            for key in ${@:2}; do
                defpkg-ensure $key & pids+=($!)
            done
            for pid in ${pids[@]}; do
                wait $pid >/dev/null
            done
            set -m
            local key
            for key in ${@:2}; do
                defpkg-load $key
            done
            ;;
        remove)
            local key
            for key in ${@:2}; do
                usepkg-remove $key
            done
            ;;
        status)
            local max_len=0
            local key
            # calculate width of the first column
            for key in ${(k)USEPKG_PKG_STATUS}; do
                local key_len=${#key}
                if (( $key_len > $max_len )); then
                    max_len=$key_len
                fi
            done
            local value
            for key value in ${(kv)USEPKG_PKG_STATUS}; do
                printf "%-*s : %b\n" $max_len $key $(usepkg-status $value)
            done
            ;;
        clean)
            local dir
            for dir in $(ls -A ${USEPKG_DATA}); do
                if [[ -z ${USEPKG_PKG_DECL[$dir]} ]]; then
                    usepkg-message "Removing $dir ..."
                    rm -rf $dir
                fi
            done
            ;;
        *)
            if [[ -n $cmd ]]; then
                echo "Unknown command: $cmd"
            fi
            echo -e "Run \e[1musepkg help\e[0m for help."
            return -22 # -EINVAL
            ;;
    esac
}

# set default value
defpkg-satus :ensure true :fetcher git :from 'https://github.com'
# the recipe of this package itself
defpkg :path gynamics/zsh-usepkg
# no need to load it twice
USEPKG_PKG_STATUS[zsh-usepkg]=OK
