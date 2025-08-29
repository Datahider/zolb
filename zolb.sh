#!/bin/sh
EXITSTATUS=0

debug() {
        echo "--DEBUG-- - $1 $2 $3 $4 $5 $6 $7 $8 $9"
}

self_update() {


        DIR="$(cd "$(dirname "$0")" && pwd)"
        TMP_DIR="$DIR/tmp_zolb"
        ARCHIVE="$DIR/release.zip"


        # Получаем последний тег с GitHub через fetch (корректно для BSD fetch)
        LOCATION=$(fetch -q -o - https://github.com/Datahider/zolb/releases/latest 2>&1 | grep -Eo 'https://github.com/Datahider/zolb/releases/tag/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d '\r\n')
        TAG=$(basename "$LOCATION")


        if [ -z "$TAG" ]; then
        echo "Failed to determine the latest release."
        exit 1
        fi


        # Скачиваем архив с последнего релиза
        fetch -o "$ARCHIVE" -q "https://github.com/Datahider/zolb/archive/refs/tags/$TAG.zip"


        mkdir -p "$TMP_DIR"
        unzip -q "$ARCHIVE" -d "$TMP_DIR"


        INNER_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)

        # Обновляем только zolb.sh если содержимое изменилось
        if [ -f "$INNER_DIR/zolb.sh" ]; then
                if [ ! -f "$DIR/zolb.sh" ] || ! cmp -s "$INNER_DIR/zolb.sh" "$DIR/zolb.sh"; then
                        cp "$INNER_DIR/zolb.sh" "$DIR/zolb.sh"
                        chmod +x "$DIR/zolb.sh"
                        echo "zolb.sh has been updated to release $TAG."
                else
                        echo "zolb.sh is already up-to-date (release $TAG)."
                fi
        fi

        rm -rf "$TMP_DIR" "$ARCHIVE"
        exit 0
}

usage() {
        echo 'Usage: zolb [-nv] [-f filesystem] [-c command [parameters]]'
        echo '  -c command - supress normal operation and execute a command (see below)'
        echo '  -d - debug mode'
        echo '  -f filesystem - doing with filesystem only'
        echo '  -F - use zfs receive -F while receiving'
        echo '  -l - list affected filesystems and exit'
        echo '  -m - use mbuffer (must be installed)'
        echo '  -n - dry-run'
        echo '  -p - power off when done'
        echo '  -s - sleep random (0..99) seconds before processing (use for cron)'
        echo '  -u - self-update to latest release'
        echo '  -v - verbose'
        echo ''
        echo 'COMMANDS'
        echo '  init MASTER SOURCE [PORT]'
        echo '          - create a new filesystem provided at -f as a slave'
        echo '            for MASTER SOURCE. Filesystem must not exist or you'
        echo '            must use -F option to overwrite existing filesystem'
        echo '            MASTER is something like root@example.com'
        echo '            SOURCE is something like tank/example/filesystem'
        echo '            PORT is TCP port to use while connecting to MASTER (default 22)'
        echo '  master'
        echo '          - become the master for filesystem provided at -f'
        echo "            if -f is a slave then also switch it's master to be slave"
        echo '  pause'
        echo '          - set ru.zolb:pause=true for filesystem provided at -f'
        echo '  resume'
        echo '          - set ru.zolb:pause=false for filesystem provided at -f'
        echo '  nomore'
        echo '          - deinit all ru.zolb properties for filesystem provided at -f'
}

ru_zolb_set() {
        if [ "x$3" = "x" ]; then # two params is for local fs
                zfs set ru.zolb:$1 $2
        else # four params is for remote fs
                ssh -o "BatchMode yes" -q -p $4 $2 "zfs set ru.zolb:$1 $3"
        fi
}

ru_zolb_unset() {
        if [ "x$3" = "x" ]; then # two params is for local fs
                zfs inherit ru.zolb:$1 $2
        else # four params is for remote fs
                ssh -o "BatchMode yes" -q -p $4 $2 "zfs inherit ru.zolb:$1 $3"
        fi
}

ru_zolb_get() {
        if [ "x$3" = "x" ]; then # two params is for local fs
                zfs get -H -o value ru.zolb:$1 $2
        else # four params is for remote fs
                ssh -o "BatchMode yes" -q -p $4 $2 "zfs get -H -o value ru.zolb:$1 $3"
        fi
}

check_fs_syntax() {
        [ $opt_d ] && debug ""
        [ $opt_d ] && debug "function check_fs_syntax"
        [ $opt_d ] && debug "param: $1"
        if [ "x${1%/}" = "x$1" ] && [ "x${1#/}" = "x$1" ]; then
                if [ "x${1%*?/?*}" = "x$1" ]; then
                        [ $opt_d ] && debug "return 1"
                        [ $opt_d ] && debug ""
                        return 1
                else
                        [ $opt_d ] && debug "return 0"
                        [ $opt_d ] && debug ""
                        return 0
                fi
        else
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1
        fi
}


fs_exists() {
        [ $opt_d ] && debug ""
        [ $opt_d ] && debug "function fs_exists"
        [ $opt_d ] && debug "param: $1"
        zfs list $1 2>/dev/null >/dev/null
        es=$?
        [ $opt_d ] && debug "return $es"
        [ $opt_d ] && debug ""
        return $es
}

remote_fs_exists() {
        [ $opt_d ] && debug ""
        [ $opt_d ] && debug "function remote_fs_exists"
        [ $opt_d ] && debug "param1: $1"
        [ $opt_d ] && debug "param2: $2"
        [ $opt_d ] && debug "param3: $3"
        ex=`ssh -o "BatchMode yes" -q -p $3 $1 "sh -c 'zfs list $2 2>&- >&- && echo -n exists'"`
        if [ "$ex" = "exists" ]; then
                [ $opt_d ] && debug "return 0"
                [ $opt_d ] && debug ""
                return 0;
        else
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1;
        fi
}

check_arg_init() {
        [ $opt_d ] && debug ""
        [ $opt_d ] && debug "function check_arg_init"
        [ $opt_d ] && debug "param1: $1"
        [ $opt_d ] && debug "param2: $2"
        [ $opt_d ] && debug "param3: $3"
        [ $opt_v ] && echo -n filesystem $opt_fs...

        if fs_exists $opt_fs; then
                [ $opt_v ] && echo "Failed! - (destroy $opt_fs and run again)"
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1
        else
                if fs_exists ${opt_fs%/*}; then
                        [ $opt_v ] && echo will create
                        init_local=create
                else
                        [ $opt_v ] && echo "Failed! - (no parent or path error)"
                        [ $opt_d ] && debug "return 1"
                        [ $opt_d ] && debug ""
                        return 1
                fi
        fi

        [ $opt_v ] && echo -n master $1...
        if ssh -o "BatchMode yes" -q -p $3 $1 "echo '' >/dev/null"; then
                [ $opt_v ] && echo ok
        else
                [ $opt_v ] && echo Failed to connect!
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1
        fi

        [ $opt_v ] && echo -n source exists $2...
        if remote_fs_exists $1 $2 $3; then
                [ $opt_v ] && echo yes
        else
                [ $opt_v ] && echo "No!"
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1
        fi

        [ $opt_v ] && echo -n is master $2...
        if [ `ru_zolb_get master $1 $2 $3` = $1 ]; then
                [ $opt_v ] && echo yes
        else
                [ $opt_v ] && echo "No! The master is `ru_zolb_get master $1 $2 $3`"
                [ $opt_d ] && debug "return 1"
                [ $opt_d ] && debug ""
                return 1
        fi


        return 0
}


args=`getopt c:df:Flmnpsuv $*`

if [ $? -ne 0 ]; then
        usage
        exit 2
fi

error_check() {
        if [ $1 -ne 0 ]; then
                echo "**ERROR** - $2"
                EXITSTATUS=3
        fi
}

# HOW TO BECOME THE MASTER
# - pause remote & local filesystems
# - check that filesystems are not busy (possible transfer in progress) and wait
# - take snapshot on remote
# - receive that snapshot
# - set ru.zolb:master & ru.zolb:source to me on local
# - set same on remote
# - start filesystems

set -- $args
while true; do
        case "$1" in
                -c)
                        opt_c=true
                        opt_command=$2
                        shift; shift
                        ;;
                -d)
                        opt_d=true
                        shift; shift
                        ;;
                -f)
                        opt_f=true
                        opt_fs=$2
                        check_fs_syntax $opt_fs
                        error_check $? "invald filesystem name $opt_fs"
                        shift; shift
                        ;;
                -F)
                        opt_F="-F"
                        shift
                        ;;
                -l)     opt_l="-l"
                        shift
                        ;;
                -m)
                        opt_m="-m"
                        shift
                        ;;
                -n)
                        opt_n="-n"
                        shift
                        ;;
                -p)
                        opt_p="-p"
                        shift
                        ;;
                -s)     opt_s=`grep -ao -m1 -E "[0-9]{2}" /dev/random | head -n 1`
                        shift
                        ;;
                -u)     opt_u="-u"
                        shift
                        ;;
                -v)
                        opt_v="-v"
                        shift
                        ;;
                --)
                        shift; break
                        ;;
        esac
done
[ $EXITSTATUS -ne 0 ] && exit $EXITSTATUS

if [ $opt_u ]; then
        self_update
        exit 0
fi

if [ "$opt_c" = "true" ] && [ "$opt_f" != "true" ]; then
        [ ]; error_check $? "-c requires -f"
        usage
        exit 2
fi


recv() {
        [ $opt_d ] && debug ""
        [ $opt_d ] && debug "function recv"
        [ $opt_d ] && debug "param1: $1"
        [ $opt_d ] && debug "param2: $2"
        [ $opt_d ] && debug "param3: $3"
        [ $opt_d ] && debug "param4: $4"
        if ssh -p $4 $1 "zfs list -H $2" >/dev/null 2>&1 </dev/null; then
                remote_snapshots=""
                first_remote=""
                for rs in `ssh -p $4 $1 "zfs list -t snapshot -d 1 -H -o name $2" </dev/null`
                do
                        if [ "x$first_remote" = "x" ]; then
                                first_remote=$rs
                        fi
                        remote_snapshots="$rs $remote_snapshots"
                done

        else
                [ ]
                error_check $? "remote filesystem $2 does not exists!"
                continue
        fi

        local_snapshots=""
        for ls in `zfs list -t snapshot -d 1 -H -o name $3 2> /dev/null`
        do
                local_snapshots="$ls $local_snapshots"
        done

        for last_snapshot in $remote_snapshots
        do
                break;
        done;

        starting_snapshot=""
        for ls in $local_snapshots
        do
                for rs in $remote_snapshots
                do
                        if [ ${rs#*@} = ${ls#*@} ]; then
                                starting_snapshot=${rs#*@}
                                break 2;
                        fi
                done
        done

        [ $opt_v ] && echo First remote snapshot is: $first_remote
        [ $opt_v ] && echo Last remote snapshot is: $last_snapshot
        [ $opt_v ] && echo Starting snapshot is: $starting_snapshot

        if [ "x$starting_snapshot" = "x" ]; then

            [ $opt_v ] && echo -n "Checking if should we make an initial copy..."
            fs_init=`ru_zolb_get 'init' $3`
            if [ x$fs_init = x ]; then
                local_F=$opt_F
                [ $opt_v ] && echo "No we don't. (but it is quite strange)"
            else
                local_F="-F"
                [ $opt_v ] && echo "Yeah. Ok, we will do"
            fi

            [ $opt_v ] && echo "Making an initial copy remote:$first_remote to local:$3"
            # Загружаем только первый снимок чтобы сразу сбросить ru.zolb:init при успехе
            if [ $opt_m ]; then
                ssh -p $4 $1 "zfs send $first_remote | gzip" < /dev/null | mbuffer | gunzip | zfs receive $local_F $opt_n $opt_v $3 && ru_zolb_unset "init" $3
                #ssh -p $4 $1 "zfs send -I ${first_remote#*@} $last_snapshot | gzip" < /dev/null | mbuffer | gunzip | zfs receive $local_F $opt_n $opt_v $3
                #TODO - должна работать опция -n для сброса ru.zolb:init выше и ниже этой строчки
            else
                ssh -p $4 $1 "zfs send $first_remote | gzip" < /dev/null | gunzip | zfs receive $local_F $opt_n $opt_v $3 && ru_zolb_unset "init" $3
                #ssh -p $4 $1 "zfs send -I ${first_remote#*@} $last_snapshot | gzip" < /dev/null | gunzip | zfs receive $local_F $opt_n $opt_v $3
            fi
        elif [ ${last_snapshot#*@} != $starting_snapshot ]; then
                [ $opt_v ] && echo "Receiving incremental copy remote:$last_snapshot-$starting_snapshot to local:$3"
                if [ $opt_m ]; then
                        ssh -p $4 $1 "zfs send -I $starting_snapshot $last_snapshot | gzip" < /dev/null | mbuffer | gunzip | zfs receive $opt_F $opt_n $opt_v $3
                else
                        ssh -p $4 $1 "zfs send -I $starting_snapshot $last_snapshot | gzip" < /dev/null | gunzip | zfs receive $opt_F $opt_n $opt_v $3
                fi
        else
                [ $opt_v ] && echo "No new snapshots for $3"
        fi
}

clean() {
        snapshots=""
        for ss in `zfs list -t snapshot -d 1 -H -o name $1`
        do
                snapshots="$ss $snapshots"
        done

        last_snapshot=""
        for ss in $snapshots
        do
                if [ "$last_snapshot" = "" ]; then
                        last_snapshot=$ss
                        [ $opt_v ] && echo Doing with $last_snapshot
                else
                        case $last_snapshot in
                                *@*-01-01_00:00) # Do nothing if last snapshot is New Year one
                                        ;;
                                *@*-*-01_00:00) # Destroy snapshot of same month in another year
                                        if [ ${last_snapshot#*@*-} = ${ss#*@*-} ]; then
                                                [ $opt_v ] && echo zfs destroy $ss
                                                [ $opt_n ] || zfs destroy $ss
                                        fi
                                        ;;
                                *@*-*-*_00:00) # Destroy snapshot of same date in another month
                                        if [ ${last_snapshot#*@*-*-} = ${ss#*@*-*-} ]; then
                                                [ $opt_v ] && echo zfs destroy $ss
                                                [ $opt_n ] || zfs destroy $ss
                                        fi
                                        ;;
                                *@*-*-*_*:00) # Destroy snapshot of same hour another day
                                        if [ ${last_snapshot#*@*-*-*_} = ${ss#*@*-*-*_} ]; then
                                                [ $opt_v ] && echo zfs destroy $ss
                                                [ $opt_n ] || zfs destroy $ss
                                        fi
                                        ;;
                                *) # Destroy snapshot of the same minute another hour
                                        if [ ${last_snapshot#*@*-*-*_*:} = ${ss#*@*-*-*_*:} ]; then
                                                [ $opt_v ] && echo zfs destroy $ss
                                                [ $opt_n ] || zfs destroy $ss
                                        fi
                                        ;;
                        esac
                fi
        done
}

get_lock() {
    exec 9</tmp/zolb.lock
    flock -n 9
}

eval `date -u "+year=%Y;month=%m;day=%d;hour=%H;minute=%M"`

if [ $opt_s ]; then
        get_lock
        if [ $? != 0 ]; then
                echo "Already running. Exiting..."
                exit 1
        fi
        [ $opt_v ] && echo Going to sleep $opt_s seconds...
        sleep $opt_s
fi

if [ $opt_c ]; then
        case $opt_command in
                pause) # pause filesystem
                        [ $opt_v ] && echo "setting ru.zolb:pause for $opt_fs to true"
                        [ $opt_n ] || zfs set ru.zolb:pause=true $opt_fs
                        ;;
                resume) # start filesystem
                        [ $opt_v ] && echo "resetting ru.zolb:pause for $opt_fs"
                        [ $opt_n ] || zfs inherit ru.zolb:pause $opt_fs
                        ;;
                init) # initializing a slave filesystem
                        [ $opt_v ] && echo checking args
                        if [ "x$3" = "x" ]; then
                                fs_port=22
                        else
                                fs_port=$3
                        fi
                        if check_arg_init $1 $2 $fs_port; then
                                if [ $init_local = create ]; then
                                        zfs create $opt_fs
                                        ru_zolb_set "pause=true" $opt_fs
                                        ru_zolb_set "init=true" $opt_fs
                                        ru_zolb_set "master=$1" $opt_fs
                                        ru_zolb_set "source=$2" $opt_fs
                                        ru_zolb_unset "pause" $opt_fs
                                fi
                        else
                                [ ]; error_check $? "init argument error (use -v for details)"
                        fi
                        ;;
                master) # become a new master (if it is slave) or just init master if ru.zolb:master is not set
                        [ $opt_v ] && echo -n "checking if $opt_fs is initialized..."
                        master_name=`zfs get -o value -H ru.zolb:master $opt_fs`
                        case $master_name in
                                -) # not initialized
                                        [ $opt_v ] && echo "no"
                                        [ $opt_v ] && echo -n "initializing ru.zolb:* properties..."
                                        [ $opt_n ] || zfs set ru.zolb:pause=true $opt_fs
                                        [ $opt_n ] || zfs set ru.zolb:master=`whoami`\@`hostname` $opt_fs
                                        [ $opt_n ] || zfs set ru.zolb:source=$opt_fs $opt_fs
                                        [ $opt_n ] || zfs inherit ru.zolb:pause $opt_fs
                                        [ $opt_v ] && echo "done"
                                        ;;
                                `hostname`) # wrong master
                                        [ $opt_v ] && echo -n "wrong! Correcting..."
                                        [ $opt_n ] || zfs set ru.zolb:master=`whoami`\@`hostname` $opt_fs
                                        [ $opt_v ] && echo "done"
                                        ;;
                                root\@`hostname`) # already master
                                        [ $opt_v ] && echo "yes!. Nothing to do."
                                        ;;
                                *) # another host is master
                                        master_source=`zfs get -o value -H ru.zolb:source $opt_fs`
                                        [ $opt_v ] && echo "yes. Slave for ${master_name} : ${master_source}"
                                        [ $opt_n ] || [ ]; error_check $? "this is not implemented yet. Use migrate.sh"
                                        ;;
                        esac
                        ;;
                nomore) # deinitialize ru.zolb properties for the filesystem
                        [ $opt_v ] && echo "deinitializing all ru.zolb:* for $opt_fs"
                        [ $opt_n ] || zfs set ru.zolb:pause=true $opt_fs
                        [ $opt_n ] || zfs inherit ru.zolb:master $opt_fs
                        [ $opt_n ] || zfs inherit ru.zolb:source $opt_fs
                        [ $opt_n ] || zfs inherit ru.zolb:init $opt_fs
                        [ $opt_n ] || zfs inherit ru.zolb:pause $opt_fs
                        ;;
        esac
else
        if [ $opt_f ]; then
                zfs get -o name,value -H -r -t filesystem ru.zolb:master $opt_fs
        else
                zfs get -o name,value -H -r -t filesystem ru.zolb:master

        fi | while read fs_name fs_master; do
                if [ "x$fs_master" != "x-" ]; then
                        fs_pause=`zfs get -o value -H ru.zolb:pause $fs_name`
                        if [ $opt_l ]; then
                                [ "x$fs_pause" = "xtrue" ] && echo -n " ||"
                                [ "x$fs_pause" = "xtrue" ] || echo -n ">>"
                                [ "`hostname`" = "${fs_master#*@}" ] && echo "*" `zfs list -t all -d 1 -o name ${fs_name} | tail -n 1`
                                [ "`hostname`" = "${fs_master#*@}" ] || echo "_" `zfs list -t all -d 1 -o name,ru.zolb:master,ru.zolb:source ${fs_name} | tail -r -n 1`
                                continue
                        fi
                        if [ "x$fs_pause" != "xtrue" ]; then
                                [ $opt_v ] && echo "Processing $fs_name..."
                                if [ "`hostname`" = "${fs_master#*@}" ]; then
                                        [ $opt_v ] && echo "I'm the master. Taking a snapshot..."
                                        snapname=${fs_name}@${year}-${month}-${day}_${hour}:${minute}
                                        [ $opt_n ] || zfs snapshot ${snapname} 2>/dev/null
                                        error_check $? "can't create snapshot $snapname"
                                else
                                        [ $opt_v ] && echo "I'm a slave. Receiving incremental stream..."
                                        source_fs=`zfs get -o value -H ru.zolb:source $fs_name`
                                        fs_port=`zfs get -o value -H ru.zolb:port $fs_name`
                                        if [ "$fs_port" = "-" ]; then
                                                fs_port=22
                                        fi
                                        recv $fs_master $source_fs $fs_name $fs_port
                                fi
                                [ $opt_v ] && echo "Cleaning snapshots, no matter who am I..."
                                clean $fs_name
                        else
                                [ $opt_v ] && echo "Skipping $fs_name (ru.zolb:pause=true)"
                        fi
                fi
        done
fi
exit $EXITSTATUS
