# zsh-usepkg

A minimal declarative zsh plugin manager.

Supports:
- fetch & load plugin(s) with declared methods
- list, check, reload, update & remove plugin(s) with commands

Dependencies:
- zsh
- gnu coreutils
- git (optional, if you want to clone git repositories from internet)
- curl (optional, if you want to fetch a script file by url)

Pros:
- extremely simple and light, but enough to use.
- compared to similar packages like `zplug`, it has a much simpler configuration grammar.

## Installation

You can also simply download `zsh-usepkg.plugin.zsh`from github and source it. However, once it starts fetch plugins, all plugins fetched will be saved in directory path `$USEPKG_PLUGIN_PATH`(default value is `$HOME/.local/share/zsh/plugins`). You can overwrite this variable before running `defpkg-finis`.

``` shell
# Bootstrap, put it at the top of your configuration
function zsh-usepkg-bootstrap() {
    # put it at anywhere you like
    USEPKG_PLUGIN_PATH=${HOME}/.local/share/zsh/plugins

    # check if zsh-usepkg exists
    if ! [[ -d ${USEPKG_PLUGIN_PATH}/zsh-usepkg ]]; then
        mkdir -p ${USEPKG_PLUGIN_PATH} && \
        git clone https://github.com/gynamics/zsh-usepkg ${USEPKG_PLUGIN_PATH}/zsh-usepkg
    fi
    # load the plugin
    source ${USEPKG_PLUGIN_PATH}/zsh-usepkg/zsh-usepkg.plugin.zsh
}

zsh-usepkg-bootstrap
```

## Configuration

After installation, you can simply load it in your `.zshrc`.

``` shell
#!/bin/zsh
# .zshrc -- my zsh initialization scripts

# ... (bootstrap here)

# uncomment this line if you do not want to see any message
#USEPKG_SILENT=true

# declare a recipe
defpkg \
    :name "zsh-config" \
    :fetcher "git" \
    :from "https://github.com" \
    :path "gynamics/zsh-config" \
    :branch "master" \
    :source "zsh-config.plugin.zsh"

# do not forget to add this at the end of your declarations
defpkg-finis
```

- `:name` specifies a customized package name.
  - default value: the last section in `:path`
- `:ensure` try to fetch this plugin if not found, or print an error if it is missed.
  - default value: `true`
- `:fetcher` specifies which program is used for fetching the package, here we use `git`
  - available options:
    - `git`: clone a repository to `USEPKG_PLUGIN_PATH`
      - use `:branch` to specify a branch name
      - use `:rev` to specify that is should be freezed by `--revision=<rev>` option for `git clone`.
        this option is not compatible with `:branch`, and such packages will be neglected by `usepkg-update`.
    - `curl`: download a single script file with given URL
    - `nope`: simply find a file in given local path
  - default value: `git`
  - Currently, this package implements concurrent downloading and sequential loading.
- `:from` specifies an upstream domain name, or server address. (or local path, only for `nope`)
  - default value: `https://github.com`
- `:path` specifies the bottom part of an URL to the package, which will be combined with `:from`
  - this part is necessary and have no default value, if missed, an error will be raised.
- `:source` specifies which file is the entry of this package on loading.
  - default value: `<NAME>.plugin.zsh`, where `<NAME>` is specified by `:name`
  - you can specify multiple files once, e. g. `:source file1 file2 file3`
- `:after` specifies which packages should be loaded before this package.
  - you can specify multiple packages once, e. g. `:after pkg1 pkg2 pkg3`
- `:depends` just like `:after`, but aborts if one of specified dependency is missing.
- `:comp` specifies zsh compdef files, these files will be copied to `${USEPKG_FUNC_PATH}`.
  - you can specify multiple files once, e. g. `:comp file1 file2 file3`.
  - if that package is loaded after `compinit`, the compdefs may not work at the first time.
- `:preface` allows you evaluate given string before the package is loaded.
- `:config` allows you evaluate given string after the package is loaded.
  - keep in mind that `defpkg` just makes a declaration, everything happens at `defpkg-finis`, keep some configuration commands together with the declaration will be helpful.
  - you can nest commands in a string to evaluate multiple commands once, e. g. `:config 'cmd1; cmd2; cmd3'`.
  - Don't abuse this option, if you really have a lot of commands to run, consider write them in a separate script, and declare it to be loaded `:after` your package.

By default, `defpkg-finis` will proceed all declarations and make calls. Note that `defpkg` only make declarations and these data are stored in hashed order. Consequently, in `defpkg-finis`, package loadings are usually not executed in declared order. `:after`can ensure that before a package is loaded, all its dependencies have been loaded.

To avoid writing duplicated recipes, use `defpkg-satus` to modify the default values. However, we can not reset the default values of `:name`, `:path` and `:source`.

``` shell
# this will change the default value of :fetcher and :from for all subsequent declarations.
defpkg-satus :ensure false :fetcher nope :from /usr/share/zsh/plugins
defpkg :path zsh-autosuggestions     # you may installed it as a system package
defpkg :path zsh-syntax-highlighting # you may installed it as a system package

# the `fzf' system package provides some zsh integration scripts
defpkg :from /usr/share :path fzf \
    :source completion.zsh key-bindings.zsh

# fetch from github
defpkg-satus :ensure true :fetcher git :from https://github.com
defpkg :path gynamics/zsh-config
defpkg :path gynamics/zsh-dirstack
defpkg :path gynamics/zsh-gitneko :after zsh-config :comp _gitneko
# load it after zsh-config, since only zsh-config calls compinit,
# _gitneko will not be scanned at the first time.

# ...

defpkg-finis # do not miss this at the end of declarations
```

- Since usepkg is declarative, that means package declarations are not processed until you run `defpkg-finis`. You can write any pre-loading configurations before it, at any position. If you need to add some post-loading configuration for a set of packages, you may create a package with `:depends` declared for it.
- `defpkg-finis`can also be called repeatedly, although it is functional to all package declarations before, it does nothing to those packages that already loaded. So you may call it multiple times to control the actual evaluation time.

## Management

Use command `usepkg` for package management.

```shell
# show this help
usepkg help

# list installed packages
# just a one-line list, no more fascinating things
usepkg list

# open a git/curl directory
# not work for local packages
usepkg open PACKAGE_NAME

# check definition of selected packages
# you can pass multiple packages once
usepkg info PACKAGE_NAME

# run a git pull --rebase on selected package dirs
# you can pass multiple packages once
# updating tasks by default in parallel
usepkg update PACKAGE_NAME

# reload specified packages, if not present, fetch it first
# you can pass multiple packages once
# downloading tasks by default in parallel
usepkg reload PACKAGE_NAME

# remove specified packages
# you can pass multiple packages once
# packages of local type won't be removed
usepkg remove PACKAGE_NAME

# remove undeclared packages in ${USEPKG_PLUGIN_PATH}
usepkg clean
```

Hints:
- If you want to update a curl downloaded script, you can simply run
  ``` shell
  usepkg remove PACKAGE_NAME && usepkg reload PACKAGE_NAME
  ```
- If you want to run info/update/remove/reload on all packages at once, you can simply run
  ```shell
  usepkg info $(usepkg list)
  ```
- If you want to remove some packages permanently, simply delete corresponding `defpkg` blocks and run `usepkg clean`. Do not use `remove`, because `remove` does not remove your declaration.
- If you do not want to see any usepkg message at startup, but still want to see usepkg messages, simple replace `usepkg-finis` to:
  ``` shell
  usepkg-finis >/dev/null
  ```
- If you got some packages broken on installing or updating, simple run `usepkg-remove <NAME>` to get rid of broken data.
  However, if it has left some broken configuration data outside of its directory, we can't track it, ask the package maintainer.
- The `update` command uses `--rebase` by default so it is not suitable to be used for managing a develop version.
  If you want to use a local repository on developing, you should use `none` with a local path rather than `git` for fetcher.

## Debugging toggles

- set `USEPKG_SILENT` to `true` to hide `usepkg-message` prints, default `false`.
- set `USEPKG_DEBUG` to `true` to display `usepkg-debug` prints, default `false`.

Currently there are no much debug prints, and it does not panic at somewhere it should.
