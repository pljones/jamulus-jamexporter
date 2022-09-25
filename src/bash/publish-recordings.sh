#!/bin/bash -e

#    publish-recordings.sh Prepare and upload recordings off-site
#    Copyright (C) 2020 Peter L Jones <peter@drealm.info>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#    See LICENCE.txt for the full text.

# Set to your Jamulus --recording/-R directory
RECORDING_DIR=/opt/Jamulus/run/recording

# Set to point to your target server ...
RECORDING_HOST=drealm.info
# ... and location on that server
# (ftp adds a leading "/", assuming the path to be relative to the FTP root;
# scp does not, assuming the path to be relative to the SSH user home directory)
RECORDING_HOST_DIR=public_html/jamulus

# Pick "ftp" or "scp" for file transport
TRANSPORT=scp

function do_ftp () {
	local zipFile=$1; shift  || { echo "do_ftp: Missing zip file name argument" >&2; false; return; }
	local lZipSize=$1; shift || { echo "do_ftp: Missing zip file size argument" >&2; false; return; }

	[[ -f "$zipFile" ]]      || { echo "do_ftp: $zipFile is not a file"; false; return; }

	local rZipFile="/${RECORDING_HOST_DIR}/${zipFile}"

	echo put '"'${zipFile}'"' '"'${rZipFile}'"' | ftp -p ${RECORDING_HOST}
	read x x x x rZipSize x < <(echo ls '"'${rZipFile}'"' | ftp -p ${RECORDING_HOST})
	echo lZipFile ${zipFile} $lZipSize';' rZipFile ${rZipFile} $rZipSize

	[[ $lZipSize == $rZipSize ]]
}

function do_scp () {
	local zipFile=$1; shift || { echo "do_scp: Missing zip file argument"; false; return; }
	local lZipSize=$1; shift; # Not a required argument

	[[ -f "$zipFile" ]]     || { echo "do_scp: $zipFile is not a file"; false; return; }

	scp -o ConnectionAttempts=6 "${zipFile}" ${RECORDING_HOST}:${RECORDING_HOST_DIR}
}

cd "${RECORDING_DIR}"

find -maxdepth 1 -type d -name 'Jam-*' | sort | \
while read jamDir
do
	rppFile="${jamDir#./}.rpp"
	[[ -f "${jamDir}/${rppFile}" ]] || continue
	(
		cd "$jamDir"

		find -maxdepth 1 -type f -name '*.wav' | sort | while read wavFile
		do
			lra=0
			integrated=0
			removeWaveFromRpp=false

			duration=$(ffprobe -v 0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$wavFile")
			if [[ ${duration%.*} -lt 60 ]]
			then
				removeWaveFromRpp=true
				echo -n ''
			else
				opusFile="${wavFile%.wav}.opus"
				declare -a stats=($(
					nice -n 19 ffmpeg -y -hide_banner -nostats -nostdin -i "${wavFile}" -af ebur128 -b:a 160k "${opusFile}" 2>&1 | \
						grep '^ *\(I:\|LRA:\)' | { read x y x; read x z x; echo $y $z; }
				))
[[ ${#stats[@]} -eq 2 ]]
				integrated=${stats[0]}
				lra=${stats[1]}
				echo "$duration $lra $integrated" | awk '{ if ( $1 >= 60 && ( $2 > 6 || $3 > -48 ) ) exit 0; exit 1 }' || {
					rm "${opusFile}"
					removeWaveFromRpp=true
				}
			fi

			if $removeWaveFromRpp
			then
				echo "Removed ${wavFile} - duration $duration, lra $lra, integrated $integrated"
				# Magic sed command to remove an item from a track with a particular source wave file
				sed -e '/^    <ITEM */{N;N;N;N;N;N;N;N;N;N;N;N}' \
					-e "\%^ *<SOURCE WAVE\n *FILE *[^>]*${wavFile}\"\n *>\n%Md" \
					"${rppFile}" > "${rppFile}.tmp" && \
					mv "${rppFile}.tmp" "${rppFile}"
			else
				echo "Kept ${opusFile} - duration $duration, lra $lra, integrated $integrated"
			fi

			rm "$wavFile"
		done

		# Magic sed command to remove empty tracks
		sed -e '/^  <TRACK {/{N;N;N}' -e '/^ *<TRACK\([^>]\|\n\)*>$/d' \
			"${rppFile}" > "${rppFile}.tmp" && \
			mv "${rppFile}.tmp" "${rppFile}"

		if grep -q 'ITEM' "${rppFile}"
		then
			# Replace any remaining references to WAV files with OPUS compressed versions
			sed -e 's/\.wav/.opus/' -e 's/WAVE/OPUS/' \
				"${rppFile}" > "${rppFile}.tmp" && \
				mv "${rppFile}.tmp" "${rppFile}"
			# Note, Audacity won't like the OPUS files natively...
		else
			# As no items were left, remove the project
			echo "Removed ${rppFile}"
			rm "${rppFile}"
			echo "Removed ${rppFile/rpp/lof}"
			rm "${rppFile/rpp/lof}"
		fi

	)

	if [[ "$(cd "${jamDir}"; echo *)" == "*" ]]
	then
		rmdir "${jamDir}"
	else
		zip -r "${jamDir}.zip" "${jamDir}" -i '*.opus' '*.rpp' && {
			rm -r "${jamDir}"
			read x x x x lZipSize x < <(ls -l "${jamDir}.zip")
			i=10
			echo ${TRANSPORT} "${jamDir#./}.zip" "(${lZipSize})" to ${RECORDING_HOST}:${RECORDING_HOST_DIR}
			while [[ $i -gt 0 ]] && ! do_${TRANSPORT} "${jamDir#./}.zip" "${lZipSize}"
			do
				(( i-- ))
				sleep $(( 11 - i ))
			done
			[[ $i -gt 0 ]] || { echo Failed to ${TRANSPORT} "${jamDir#./}.zip" "(${lZipSize})" to ${RECORDING_HOST}:${RECORDING_HOST_DIR} >&2; false; }
			echo OK
		}
	fi

done
