#!/bin/bash

# ======================================
#  Constants
# ======================================
theme='Adara'

theme_dir="$HOME/.themes"

sass_input='scss/cinnamon.scss'
sass_output='cinnamon.css'
sass_style='expanded'
sass_optfile='scss/base/_options.scss'

assets_dirs=(
    'img'
    'dark-img'
)

watch_dirs=(
    ${assets_dirs[@]}
    'scss'
)


zip_name="$theme.zip"

# Relative to the project's root
package_files=(
    "$theme/cinnamon/cinnamon.css"
    "$theme/cinnamon/thumbnail.png"
    "$theme/cinnamon/img/"
)

# Files that need to be moved into the $theme folder
extra_files=(
    'LICENSE'
    'README.md'
    'screenshot.png'
)

# ======================================
#  Operations
# ======================================
compile_sass () {
    sassc -t "$sass_style" "$sass_input" > "$sass_output"
}

restart_theme () {
    gsettings set org.cinnamon.theme name 'cinnamon'
    gsettings set org.cinnamon.theme name "$theme"
}

symlink_theme () {
    mkdir -p "$theme_dir"
    rm -rf "$theme_dir/$theme"
    ln -rfs "$theme" "$theme_dir/"
}

# Set variable color in the options file (sass)
set_color () {
    local varname="$1"
    local value="$2"

    sed -i "s/\$$varname:.*;/\$$varname: $value;/g" "$sass_optfile"
}

compile_theme () {
    cd "$theme/cinnamon/"
    if [[ $2 == 'dark' ]]; then
        set_color 'dark-mode' 'true'
    else
        set_color 'dark-mode' 'false'
    fi && \
    compile_sass
    cd -
}

install_theme () {
    package_theme &> /dev/null
    mkdir -p "$theme_dir"
    rm -rf "$theme_dir/$theme"
    pwd
    unzip $zip_name -d "$theme_dir"
    rm $zip_name

    restart_theme
}

package_theme () {
    if type sassc; then
        (cd "$theme/cinnamon/" && compile_sass)
    fi

    rm -f "$zip_name"
    zip -r "$zip_name" "${package_files[@]}"

    for ef in ${extra_files[@]} ;do
        local filename=`basename $ef`
        ln -rfs "$ef" "$theme/$filename"
        zip -r "$zip_name" "$theme/$filename"
        rm -rf "$theme/$filename"
    done

    echo "Files compressed into $zip_name"
}

package_all () {
    local build=$(mktemp -d)

    compile_theme ' ' dark > /dev/null
    package_theme > /dev/null
    unzip -q "$zip_name" -d $build
    mv "$build/$theme" "$build/$theme Dark"

    compile_theme > /dev/null
    package_theme > /dev/null
    unzip -q "$zip_name" -d $build

    cd $build
    zip -r "$zip_name" *
    cd -
    mv -f "$build/$zip_name" .
    rm -rf $build
}

spices_package () {
    if [ "$2" == "all" ]; then
        package_all
    else
        package_theme
    fi
}

simplify_assets () {
    simplify () {
        scour -i "$1" -o "$2"\
            --remove-metadata \
            --enable-id-stripping \
            --protect-ids-noninkscape \
            --disable-simplify-colors
    }

    # Usage: print_progress PROGRESS TOTAL
    print_progress () {
        local n_cols=$(($(tput cols)-7))
        local cols_completed=$(($1*n_cols/$2))
        local percent_completed=$(($1*100/$2))

        echo -n "$percent_completed% "
        for ((i=0; i<$cols_completed; i++)) {
            echo -n '#'
        }
    }

    cd "$theme/cinnamon/"

    if type scour &> /dev/null ; then

        # temp dir for the output (can't output to self)
        local tmp_dir=$(mktemp -d)
        local assets_list=$(find ${assets_dirs[@]} -name '*.svg')
        local n_assets=$(echo "$assets_list" | wc -l)
        local completed=0

        for res in $assets_list ; do
            echo -e "> Simplifying \e[34m$(basename $res)\e[0m"
            print_progress $completed $n_assets

            output=$(simplify "$res" "$tmp_dir/out.svg")
            mv "$tmp_dir/out.svg" "$res"

            echo -en '\033[2K\r' # clear old progress bar
            echo "  $output"
            ((completed=completed+1))
        done

        echo 'Simplify assets task finished'
    else
        echo 'scour not found'
    fi
}

watch_files () {
    symlink_theme
    cd "$theme/cinnamon/"
    echo 'Started watching files (Ctrl+C to exit)'
    while true; do
        compile_sass
        restart_theme
        notify-send "Theme $theme reloaded" \
            --icon='preferences-desktop-theme' \
            --hint=int:transient:1 &> /dev/null

        # Wait until any file changes
        inotifywait --format '%T > %e %w%f' --timefmt '%H:%M:%S' -qre modify "${watch_dirs[@]}"
    done
}

show_help () {
    local bold=$(tput bold)
    local normal=$(tput sgr0)

    echo "\
${bold}USAGE${normal}
    ./$(basename $0) --OPTION

${bold}OPTIONS${normal}
  --install         Install the theme into the system.

  --help            Show help.

${bold}DEVELOPMENT OPTIONS${normal}
  --compile [dark]  Convert SASS files into CSS.
                    dark: compile the dark variant (optional).

  --pkg [all]       Package files ready to be uploaded to the Cinnamon Spices.
                    Add 'all' to generate all the color variants provided.

  --simplify        Optimize SVG assets for a smaller size and a better theme
                    performance stripping metadata and other stuff.

  --watch           Refresh the theme while making changes to files and images.
"
}

# ======================================
#  Start point
# ======================================

declare -A operations
operations[install]=install_theme
operations[compile]=compile_theme
operations[help]=show_help
operations[pkg]=spices_package
operations[simplify]=simplify_assets
operations[watch]=watch_files

if [[ $1 == --?* ]]
then
    opname=${1:2}
    opfunc="${operations[$opname]}"

    if [[ -n "$opfunc" ]]
    then $opfunc "$@"
    else
        echo "$opname: command not found"
        show_help
    fi
else
    show_help
fi