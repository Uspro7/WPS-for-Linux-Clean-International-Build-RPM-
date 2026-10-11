#!/bin/sh
# Sourced by the three WPS launchers; only update WPS's interface language.
linuxwps_set_language() (
    umask 077
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Kingsoft"
    config="$config_dir/Office.conf"
    mkdir -p "$config_dir" || exit 1
    if [ ! -f "$config" ]; then
        printf '[6.0]\nlanguages=zh_CN\n' > "$config"
        exit "$?"
    fi

    temporary=$(mktemp "$config_dir/.Office.conf.XXXXXX") || exit 1
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    # QSettings stores the languages key directly in the [6.0] section.
    # Preserve all other settings and do not rewrite an already-correct file.
    awk '
        function ensure_language() {
            if (office && !written) {
                print "languages=zh_CN"
                written = 1
            }
        }
        /^\[/ {
            ensure_language()
            office = ($0 ~ /^\[6\.0\]\r?$/)
            if (office) seen = 1
        }
        office && /^[ \t]*languages[ \t]*=/ {
            if (!written) print "languages=zh_CN"
            written = 1
            next
        }
        { print }
        END {
            ensure_language()
            if (!seen) print "[6.0]\nlanguages=zh_CN"
        }
    ' "$config" > "$temporary" || exit 1
    cmp -s "$config" "$temporary" && exit 0
    if [ ! -e "$config.linuxwps-backup" ]; then
        cp -p "$config" "$config.linuxwps-backup" || exit 1
    fi
    mv -f "$temporary" "$config"
)

linuxwps_set_language || printf '%s\n' 'WPS: could not set Chinese interface language.' >&2
unset -f linuxwps_set_language
export LANGUAGE=zh_CN:zh
