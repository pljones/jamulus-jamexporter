#!/bin/bash -e
if [[ "$1" == "--help" ]]
then
cat <<-HELPMSG
	Recreate a Reaper RPP project file from a Jamulus recording directory.

	$(basename "$0") [--help]
	  --help  display this help message

	The intent of this script is to take an existing collection of Jamulus recorded
	WAVE files and generate a Reaper RPP project file that matches the one the server
	should have created.  It may sometimes be needed, for example when the server fails
	to terminate the recording correctly (as that is when the RPP file gets written).

	The script should be run from the directory containing the "failed" recording.
	It outputs the RPP file on stdout - redirect this to your chosen project filename.

	It requires  /etc/init.d/Jamulus  to be the provided start up script, so it can
	read the configuration settings.

HELPMSG
	exit 0
fi

# Set the variables
JAMULUS_SERVERNAME=jamulus.drealm.info
JAMULUS_OPTS=("-F")

siteNamespace=$(uuidgen -n @url -N jamulus:${JAMULUS_SERVERNAME} --sha1)
projectName=$(basename "$(pwd)")

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

projectNamespace=$(uuidgen -n $siteNamespace -N "${projectName}" --sha1)
projectDate=$( p=${projectName#Jam-}; echo ${p:0:4}-${p:4:2}-${p:6:2} ${p:9:2}:${p:11:2}:${p:13:2}.${p:15} )
frameRate=$([[ ${JAMULUS_OPTS[@]} =~ " -F" ]] && echo 64 || echo 128)

secondsAt48K () {
	echo $1 | awk '{ printf "%.14f\n", $1 / 48000; }'
}

echo '<REAPER_PROJECT 0.1 "5.0"' $(date -d "$projectDate" -u '+%s')
echo ' RECORD_PATH "" ""'
echo ' SAMPLERATE 48000 0 0'
echo ' TEMPO 120 4 4'

iid=0
prevIP=''
for x in $(ls -1 *.wav | sort -t- -k2)
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
			echo '  NAME '$trackName
			echo ' >'
		fi
		prevIP="$IP"
		echo ' <TRACK {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
		echo '  TRACKID {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
		trackName="${x%-*-*.wav}"
	else
		[[ "${trackName:0:5}" == "____-" ]] && trackName="${x%-*-*.wav}"
	fi
	(( iid++ )) || true
	(( iidt++ )) || true
	echo '  <ITEM'
	echo '   FADEIN 0 0 0 0 0 0'
	echo '   FADEOUT 0 0 0 0 0 0'
	filePos="${x#*-*-}"
	filePos="${filePos%-*.wav}"
	echo '   POSITION '$(secondsAt48K $(( $filePos * $frameRate )) )
	echo '   LENGTH '$(secondsAt48K $(soxi -s "$x"))
	echo '   IGUID {'$(uuidgen -n $projectNamespace -N $IP --sha1)'}'
	echo '   IID '$iid
	echo '   NAME '$IP' ('$iidt')'
	echo '   GUID {'$(uuidgen -n $projectNamespace -N "$IP-$iidt" --sha1)'}'
	echo '   <SOURCE WAVE'
	echo '    FILE "'$x'"'
	echo '   >'
	echo '  >'
done
if [[ "$prevIP" != "" ]]
then
	echo '  NAME '$trackName
	echo ' >'
fi
echo '>'
