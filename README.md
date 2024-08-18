# zsh-usepkg

A minimal declarative zsh plugin manager.

Supports:
- fetch & load plugin(s) with declared methods
- list, reload, update & remove plugin(s) with commands

Dependencies:
- zsh
- gnu coreutils
- git (optional, if you want to clone git repositories from internet)
- curl (optional, if you want to fetch a script file by url)

## Installation

You can also simply download `zsh-usepkg.plugin.zsh`from github and source it.

``` shell
# Bootstrap, run it once
function zsh-usepkg-bootstrap() {
    # put it at anywhere you like
    USEPKG_DATA=${HOME}/.local/share/zsh

    # check if zsh-usepkg exists
    if ! [[ -d ${USEPKG_DATA}/zsh-usepkg ]]; then
        mkdir -p ${USEPKG_DATA} && \
        git clone https://github.com/gynamics/zsh-usepkg ${USEPKG_DATA}/zsh-usepkg
    fi
    # load the plugin
    source ${USEPKG_DATA}/zsh-usepkg/zsh-usepkg.plugin.zsh
}

zsh-usepkg-bootstrap
```

## Configuration

After installation, you can simply load it in your `.zshrc`.

``` shell
#!/bin/zsh
# .zshrc -- my zsh initialization scripts

# ... (bootstrap here)

# declare a recipe
defpkg \
    :name "zsh-config"
    :fetcher "git" \
    :from "https://github.com" \
    :path "gynamics/zsh-config" \
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
    - `git`: clone a repository to `USEPKG_DATA`, you can use `:branch` to specify a branch
    - `curl`: download a single script file with given URL
    - `nope`: simply find a file in given local path
  - default value: `git`
- `:from` specifies an upstream domain name, or server address. (or local path, only for `nope`)
  - default value: `https://github.com`
- `:path` specifies the bottom part of an URL to the package, which will be combined with `:from`
  - this part is necessary and have no default value, if missed, an error will be raised.
- `:source` specifies which file is the entry of this package on loading.
  - default value: `<NAME>.plugin.zsh`, where `<NAME>` is specified by `:name`
  - currently you can not specify multiple files to source at once

`defpkg-finis` will proceed all declarations and make calls.

To avoid writing duplicated recipes, use `defpkg-satus` to modify the default values.

``` shell
# this will change the default value of :fetcher and :from for all subsequent declarations.
defpkg-satus :ensure false :fetcher nope :from /usr/share/zsh/plugins

defpkg :path zsh-autosuggestions # you may installed it as a system package
defpkg :path zsh-syntax-highlighting # you may installed it as a system package

# if you need to source multiple files, you need to separate them into different packages
# this is relatively fair for local and curl, because they are single-file targeted
# but problematic with git, becuase multiple packages may cause repeated removal & update
defpkg-satus :from /usr/share :path fzf

defpkg :name fzf-completion  :source completion.zsh
defpkg :name fzf-keybindings :source key-bindings.zsh 

# an alternative way is to override that package with the same name later:
# however, this approach will make reload operation broken.
# we may discuss for a better solution later. (e. g. introduce more separators like zplug?)
#defpkg :name fzf :source completion.zsh
#defpkg-finis-1 fzf
#defpkg :name fzf :source key-bindings,zsh

# fetch from github
defpkg-satus :ensure true :fetcher git :from https://github.com
defpkg :path gynamics/zsh-config
defpkg :path gynamics/zsh-dirstack
defpkg :path gynamics/zsh-gitneko

# ...

defpkg-finis # do not miss this at the end of declarations
```

However, we can not reset the default values of `:name`, `:path` and `:source`.

Not recommended, if you really want to do that, you can make an extension framework for it first, then, why not switch to a more powerful manager like `oh-my-zsh`?

## Management

Use command `usepkg` for package management.

```shell
# show this help
usepkg help

# list installed packages
# just a one-line list, no more fascinating things
usepkg list

# run a git pull --rebase on selected package dir
# you can pass multiple packages once
usepkg update PACKAGE_NAME

# reload specified package
# you can pass multiple packages once
usepkg reload PACKAGE_NAME

# remove specified package
# you can pass multiple packages once
# packages of local type won't be removed
usepkg remove PACKAGE_NAME

# remove undeclared packages in ${USEPKG_DATA}
usepkg clean
```

Hint: If you want to update a curl downloaded script, you can simply run 

``` shell
usepkg remove PACKAGE_NAME && usepkg reload PACKAGE_NAME

```

## Debugging

- set `USEPKG_SILENT` to `false` to display `usepkg-message` prints.
- set `USEPKG_DEBUG` to `true` to display `usepkg-debug` prints.

Currently there are no much debug prints, and it does not panic at somewhere it should.
