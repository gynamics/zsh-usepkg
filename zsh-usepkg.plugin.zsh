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

defpkg_keys=( :name :ensure :fetcher :from :path :branch :source :after )

typeset -gA pkg_proto

function defpkg-satus() {
    local key
    local tuple
    for tuple in "${(s/ :/)*#:}"; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg_proto[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done
}

typeset -gA packages

# declare one package
function defpkg() {
    typeset -A pkg

    # initialize pkg with default values
    local key
    for key in ${(k)pkg_proto}; do
        pkg[$key]="${pkg_proto[$key]}"
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
    packages[${pkg[:name]}]=${(kv)pkg}
}

typeset -gA package_status

function usepkg-status() {
    case $1 in
        FETCH_FAILURE)
            echo -ne "\e[31m[$1]\e[0m"
            ;;
        OK)
            echo -ne "\e[32m[$1]\e[0m"
            ;;
        NOT_FOUND)
            echo -ne "\e[33m[$1]\e[0m"
            ;;
        REMOVED)
            echo -ne "\e[34m[$1]\e[0m"
            ;;
        LOAD_FAILURE)
            echo -ne "\e[35m[$1]\e[0m"
            ;;
        *)
            echo -ne "\e[36m[$1]\e[0m"
            ;;
    esac
}

# check, fetch and load given package
function defpkg-finis-1() {
    if [[ -z ${packages[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # check and load package
    usepkg-message "Loading package ${1} ..."

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)packages[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    # dependency check
    for key in ${(s/ /)pkg[:after]}; do
        if [[ -z ${package_status[$key]} ]]; then
            usepkg-debug "Dependency $key not loaded"
            defpkg-finis-1 ${key}
        fi
    done


    if [[ ${pkg[:fetcher]} == nope ]]; then
        local f
        for f in ${(s/ /)pkg[:source]}; do
            if [[ ! -e ${pkg[:from]%/}/${pkg[:path]%/}/${f} ]]; then
                package_status[$1]=NOT_FOUND
                if ${pkg[:ensure]}; then
                    usepkg-error "Failed to find ${pkg[:name]} at " \
                                 "${pkg[:from]%/}/${pkg[:path]%/}/${f}!"
                    return -2 # -ENOENT
                else
                    usepkg-debug "${pkg[:from]%/}/${pkg[:name]%/}/${f} not found"
                    return 0
                fi
            else
                usepkg-debug "Loading file ${pkg[:from]%/}/${pkg[:name]%/}/${f} ..."
                source ${pkg[:from]%/}/${pkg[:path]%/}/${f}
            fi
        done
    else
        if [[ ! -d ${USEPKG_DATA}/${pkg[:name]} ]]; then
            package_status[$1]=NOT_FOUND
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
                    package_status[$1]=FETCH_FAILURE
                    usepkg-error "Failed to fetch package ${pkg[:name]}"
                    return $ret
                fi
            else # just neglect it
                return 0
            fi
        fi
        # load plugins
        local f
        for f in ${(s/ /)pkg[:source]}; do
            usepkg-debug "Loading file ${USEPKG_DATA%/}/${pkg[:name]%/}/${f} ..."
            source ${USEPKG_DATA%/}/${pkg[:name]%/}/${f}
            local ret=$?
            if [[ $ret != 0 ]]; then
                package_status[$1]=LOAD_FAILURE
                usepkg-error "Failed to load ${USEPKG_DATA%/}/${pkg[:name]%/}/${f}"
                return $ret
            fi
        done
    fi
    package_status[$1]=OK
    return 0
}

function defpkg-finis() {
    mkdir -p ${USEPKG_DATA}

    local key
    for key in ${(k)packages}; do
        if [[ ${package_status[$key]} == OK ]]; then
            continue # do not load a package twice
        fi
        defpkg-finis-1 "$key"

        if [[ $? != 0 ]]; then
            usepkg-error "Failed to load package $key"
        fi
    done
}

function usepkg-update-1() {
    if [[ -z ${packages[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)packages[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    if [[ ${pkg[:fetcher]} != git ]]; then
        usepkg-error "${pkg[:name]} is not a git repository"
        return -22 # -EINVAL
    else
        usepkg-message "Updating ${pkg[:name]} ..."
        git -C ${USEPKG_DATA%/}/${pkg[:name]} pull --rebase
        if [[ $? != 0 ]]; then
            local ret=$?
            usepkg-error "Failed to fetch package ${pkg[:name]}"
            return $ret
        fi
    fi
}

function usepkg-remove-1() {
    if [[ -z ${packages[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # extract one pkg
    typeset -A pkg
    local key
    local tuple
    for tuple in ${(s/ :/)packages[$1]#:}; do
        key=":${tuple%% *}"
        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            pkg[$key]="${tuple#* }"
        else
            usepkg-error "$key is not a valid key!"
        fi
    done

    if [[ ${pkg[:fetcher]} != nope ]]; then
        usepkg-message "Removing ${pkg[:name]} ..."
        rm -I -rf ${USEPKG_DATA%/}/${pkg[:name]}
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
            echo "check [[package]..]"
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
            echo ${(k)packages}
            ;;
        check)
            local key
            for key in ${@:2}; do
                if [[ -n $key && -n ${packages[$key]} ]]; then
                    echo "package: $key"
                    echo "status: ${package_status[$key]}"
                    echo "definition:"
                    local tuple=''
                    for tuple in ${(s/ :/)packages[$key]#:}; do
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
            local key
            for key in ${@:2}; do
                usepkg-update-1 $key
            done
        ;;
        reload)
            local key
            for key in ${@:2}; do
                defpkg-finis-1 $key
            done
        ;;
        remove)
            local key
            for key in ${@:2}; do
                usepkg-remove-1 $key
            done
            ;;
        status)
            local max_len=0
            local key
            # calculate width of the first column
            for key in ${(k)package_status}; do
                local key_len=${#key}
                if (( $key_len > $max_len )); then
                    max_len=$key_len
                fi
            done
            local value
            for key value in ${(kv)package_status}; do
                printf "%-*s : %b\n" $max_len $key $(usepkg-status $value)
            done
            ;;
        clean)
            local dir
            for dir in $(ls -A ${USEPKG_DATA}); do
                usepkg-message "Removing $dir ..."
                if [[ -z ${packages[(R)$dir]} ]]; then
                    rm -I -rf $dir
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
