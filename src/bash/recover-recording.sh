#!/bin/bash -e
fHelp() {
cat <<-HELPMSG
	Recreate the Reaper RPP or Audacity LOF project files from a Jamulus recording directory.

	$(basename "$0") [--help] [--nofastupdate] [--servername 'server name']
	                 [--rpp [ - | filename.rpp ] ] [--lof [ - | filename.lof ] ]
	  --help          display this help message
	  --nofastupdate  by default, processing assumes "fastupdate" was enabled for
	                  the recording being recovered.  Use this if it was not.
	  --servername    anything you want - used in RPP UUID generation.
	  --rpp           if specified, write RPP output to the named file.  If --lof
	                  is not specified as well, only the RPP will be written.
	  --lof           if specified, write RPP output to the named file.  If --rpp
	                  is not specified as well, only the LOF will be written.

	The intent of this script is to take an existing collection of Jamulus recorded
	WAVE files and generate the Reaper RPP and Audacity LOF project files that match
	the one the server should have created.  It may sometimes be needed, for example
	when the server fails to terminate the recording correctly (as that is when the
	project files gets written).

	The script should be run from the directory containing the "failed" recording.
	By default, the script writes both RPP and LOF projects to files, using the working
	directory name and appropriate suffix.  "--rpp" and "--lof" can optionally be
	followed by a filename, which can be "-" for stdout.  If only one of the two is
	specified, the other is not written at all.

HELPMSG
}

# Set the variable defaults
JAMULUS_SERVERNAME=jamulus.drealm.info
frameRate=64

is_rpp=false
is_lof=false
do_rpp=false
do_lof=false
unset RPP_NAME
unset LOF_NAME
while { arg=$1; shift; }
do
	case "$arg" in
	"-h" | "--help") fHelp; exit 0
		;;
	"--nofastupdate") frameRate=128; is_rpp=false; is_lof=false
		;;
	"--servername")
		[[ $# -gt 0 ]] || { echo '--servername requires a server name'; exit 1; }
		JAMULUS_SERVERNAME="$1"; is_rpp=false; is_lof=false; shift
		;;
	"--rpp")
		is_rpp=true; is_lof=false; do_rpp=true
		;;
	"--lof")
		is_rpp=false; is_lof=true; do_lof=true
		;;
	*)
		if $is_rpp
		then
			RPP_NAME="$arg"
			is_rpp=false
		elif $is_lof
		then
			LOF_NAME="$arg"
			is_lof=false
		else
			echo "Unrecognised argument '$arg'.  Use '--help' for help." >&2
			exit 1
		fi
	esac
done

# Neither argument specified, write both
$do_rpp || $do_lof || {
	do_rpp=true
	do_lof=true
}

projectName="$(basename "$(realpath "$(pwd)")")"

if [[ "${projectName:0:4}" != "Jam-" ]]
then
	echo "Run this script from the failed recording directory." >&2
	exit 1
fi

if [[ "$(echo *.wav)" == "*.wav" ]]
then
	echo "There are no WAVE files in this directory from which to create a project." >&2
	exit 1
fi

echo "Project will be recovered with a frame rate of $frameRate samples per frame"

$do_rpp && RPP_NAME="${RPP_NAME:-$projectName.rpp}"
$do_lof && LOF_NAME="${LOF_NAME:-$projectName.lof}"

[[ "x$RPP_NAME" == "x-" ]] && RPP_NAME="/dev/stdout"
[[ "x$LOF_NAME" == "x-" ]] && LOF_NAME="/dev/stdout"

siteNamespace=$(uuidgen -n @url -N "jamulus:${JAMULUS_SERVERNAME}" --sha1)

projectNamespace=$(uuidgen -n $siteNamespace -N "${projectName}" --sha1)
projectDate=$( p=${projectName#Jam-}; echo ${p:0:4}-${p:4:2}-${p:6:2} ${p:9:2}:${p:11:2}:${p:13:2}.${p:15} )

secondsAt48K () {
	echo $1 | awk '{ printf "%.14f\n", $1 / 48000; }'
}

$do_rpp && { {
echo '<REAPER_PROJECT 0.1 "5.0"' $(date -d "$projectDate" -u '+%s')
echo ' RECORD_PATH "" ""'
echo ' SAMPLERATE 48000 0 0'
echo ' TEMPO 120 4 4'
} > $RPP_NAME; }
$do_lof && { {
echo -n ;# do nothing
} > $LOF_NAME
}

iid=0
prevIP=''

ls -1v *.wav | sort -t- -k2 | while read x
do

	# Some initial cleaning up
	if [[ -z "$x" ]]
	then
		rm "$x"
		continue
	fi
	# If ffmpeg/ffprobe and sox cannot cope then give up
	if ! ffprobe -v error -i "$x" >/dev/null 2>&1
	then
		if sox --ignore-length "$x" "FIXED-$x" >/dev/null 2>&1
		then
			mv "FIXED-$x" "$x"
		else
			rm -f "$x" "FIXED-$x"
			continue
		fi
	fi

	IP=${x#*-}
	IP=${IP%%-*}
	if [[ "$prevIP" != "$IP" ]]
	then
		iidt=0
		if [[ "$prevIP" != "" ]]
		then
$do_rpp && { {
			echo '  NAME '$trackName
			echo ' >'
} >> $RPP_NAME; }
		fi
		prevIP="$IP"
$do_rpp && { {
		echo ' <TRACK {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
		echo '  TRACKID {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
} >> $RPP_NAME; }
		trackName="${x%-*-*.wav}"
	else
		[[ "${trackName:0:5}" == "____-" ]] && trackName="${x%-*-*.wav}"
	fi
	(( iid++ )) || true
	(( iidt++ )) || true
	filePos="${x#*-*-}"
	filePos="${filePos%-*.wav}"
	position=$(secondsAt48K $(( $filePos * $frameRate )) )
	length=$(secondsAt48K $(soxi -s "$x"))
$do_rpp && { {
	echo '  <ITEM'
	echo '   FADEIN 0 0 0 0 0 0'
	echo '   FADEOUT 0 0 0 0 0 0'
	echo '   POSITION '$position
	echo '   LENGTH '$length
	echo '   IGUID {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
	echo '   IID '$iid
	echo '   NAME '$IP' ('$iidt')'
	echo '   GUID {'$(uuidgen -n $projectNamespace -N "$IP-$iidt" --sha1)'}'
	echo '   <SOURCE WAVE'
	echo '    FILE "'$x'"'
	echo '   >'
	echo '  >'
} >> $RPP_NAME; }
$do_lof && { {
        echo 'file "'${x}'" offset '$(secondsAt48K $(( $filePos * $frameRate )) )
} >> $LOF_NAME; }
done
if [[ "$prevIP" != "" ]]
then
$do_rpp && { {
	echo '  NAME '$trackName
	echo ' >'
} >> $RPP_NAME; }
fi
$do_rpp && { {
echo '>'
} >> $RPP_NAME; }
