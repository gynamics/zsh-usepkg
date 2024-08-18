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

defpkg_keys=( :name :ensure :fetcher :from :path :branch :source )

typeset -gA pkg_proto

function defpkg-satus() {
    if (( $# % 2 != 0 )); then
        usepkg-error "Expecting an even number of arguments (:key value pairs)."
        return -22 # -EINVAL
    fi

    local i
    for (( i = 1; i <= $#; i += 2 )); do
        local key=${(P)i}   # Get the key (1st, 3rd, 5th argument, etc.)
        local value=${(P)$((i + 1))} # Get the corresponding value (2nd, 4th, 6th argument, etc.)

        if [[ -n "${defpkg_keys[(R)${key}]}" ]]; then
            usepkg-debug "set proto: $key <- $value"
            pkg_proto[$key]="$value"
        else
            usepkg-error "$key is not a valid key"
        fi
    done
}

typeset -gA packages

# declare one package
function defpkg() {
    if (( $# % 2 != 0 )); then
        usepkg-error "Expecting an even number of arguments (:key value pairs)."
        return -22 # -EINVAL
    fi

    typeset -A pkg

    # initialize pkg with default values
    local key
    for key in ${(k)pkg_proto}; do
        pkg[$key]="${pkg_proto[$key]}"
    done

    # parse recipe and save key-value pairs into an associate array
    local i
    for (( i = 1; i <= $#; i += 2 )); do
        local key=${(P)i}   # Get the key (1st, 3rd, 5th argument, etc.)
        local value=${(P)$((i + 1))} # Get the corresponding value (2nd, 4th, 6th argument, etc.)

        if [[ -n ${defpkg_keys[(R)$key]} ]]; then
            usepkg-debug "declare package: $key <- $value"
            pkg[$key]="$value"
        else
            usepkg-error "No handler registered for $key"
        fi
    done

    # figure out :name and :source
    if [[ -n ${pkg[:path]} ]]; then
        if [[ -z ${pkg[:name]} ]]; then
            pkg[:name]=${pkg[:path]##*/}
        fi

        if [[ -z ${pkg[:source]} ]]; then
            pkg[:source]=${pkg[:name]}.plugin.zsh
        fi
    else
        usepkg-error "Value under key :path can not be empty."
    fi

    # store it as a plist
    usepkg-debug "package declared: ${pkg[:name]}"
    packages[${pkg[:name]}]=${(kv)pkg}
}

typeset -gA package_status

# check, fetch and load given package
function defpkg-finis-1() {
    if [[ -z ${packages[$1]} ]]; then
        return -22 # -EINVAL
    fi

    # check and load package
    usepkg-message "Loading package ${1} ..."

    # extract one pkg
    typeset -A pkg
    for key value in ${(s/ /)packages[$1]}; do
        usepkg-debug "extract ($key, $value)"
        pkg[$key]="$value"
    done

    if [[ ${pkg[:fetcher]} == nope ]]; then
        if [[ ! -e ${pkg[:from]%/}/${pkg[:path]%/}/${pkg[:source]} ]]; then
            package_status[$1]="\e[33mNOT_FOUND\e[0m"
            if ${pkg[:ensure]}; then
                usepkg-error "Failed to find ${pkg[:name]} at " \
                         "${pkg[:from]%/}/${pkg[:path]%/}/${pkg[:source]}!"
                return -2 # -ENOENT
            else
                return
            fi
        else
            source ${pkg[:from]%/}/${pkg[:path]%/}/${pkg[:source]}
        fi
    else
        if [[ ! -d ${USEPKG_DATA}/${pkg[:name]} ]]; then
            package_status[$1]="\e[33mNOT_FOUND\e[0m"
            if ${pkg[:ensure]}; then
                # fetch package (single thread)
                usepkg-message "Start fetching package ${pkg[:name]} ..."

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
                        ;;
                    curl)
                        mkdir -p ${USEPKG_DATA}/${pkg[:name]}
                        # here we simply download one file
                        curl ${pkg[:from]%/}/${pkg[:path]%/}/${pkg[:source]} \
                             -o ${USEPKG_DATA%/}/${pkg[:name]%/}/${pkg[:source]}
                        ;;
                    *)
                        usepkg-error "Unknown fetcher ${pkg[:fetcher]}"
                        return -22 # -EINVAL
                        ;;
                esac

                if [[ $? != 0 ]]; then
                    local ret=$?
                    package_status[$1]="\e[31m[FETCH_FAILURE]\e[0m"
                    usepkg-error "Failed to fetch package ${pkg[:name]}"
                    return $ret
                fi
            else # just neglect it
                return
            fi
        fi
        # load plugin
        source ${USEPKG_DATA%/}/${pkg[:name]%/}/${pkg[:source]}
    fi

    if [[ $? == 0 ]]; then
        package_status[$1]="\e[32m[OK]\e[0m"
    fi
}

function defpkg-finis() {
    mkdir -p ${USEPKG_DATA}

    for key in ${(k)packages}; do
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
    for key value in ${(s/ /)packages[$1]}; do
        pkg[$key]="$value"
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
    for key value in ${(s/ /)packages[$1]}; do
        pkg[$key]="$value"
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
        dashboard)

        ;;
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
        open)
            if [[ -n $2 ]]; then
               cd ${USEPKG_DATA%/}/$2
            fi
        ;;
        update)
            for key in ${@:2}; do
                usepkg-update-1 $key
            done
        ;;
        reload)
            for key in ${@:2}; do
                defpkg-finis-1 $key
            done
        ;;
        remove)
            for key in ${@:2}; do
                usepkg-remove-1 $key
            done
            ;;
        status)
            local max_len=0
            # calculate width of the first column
            for key in ${(k)package_status}; do
                local key_len=${#key}
                if (( $key_len > $max_len )); then
                    max_len=$key_len
                fi
            done
            for key value in ${(kv)package_status}; do
                printf "%-*s : %b\n" $max_len $key $value
            done
            ;;
        clean)
            for dir in $(ls -A ${USEPKG_DATA}); do
                if [[ -z ${packages[(R)$dir]} ]]; then
                    rm -rf $dir
                fi
            done
        ;;
        *)
            usepkg-error "Unknown command: $cmd"
            return -22 # -EINVAL
        ;;
    esac
}

# set default value
defpkg-satus :ensure true :fetcher git :from 'https://github.com'

# the recipe of this package itself
defpkg :path gynamics/zsh-usepkg
