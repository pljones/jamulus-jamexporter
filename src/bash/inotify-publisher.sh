#!/bin/bash -e

#    inotify-publisher.sh Trigger jam publishing automatically
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

# Configuration
JAMULUS_ROOT=/opt/Jamulus
JAMULUS_RECORDING_DIR=${JAMULUS_ROOT}/run/recording
NEW_JAMDIR_INTERVAL=$(( 5 * 60 ))
JAMULUS_LOGFILE=${JAMULUS_ROOT}/log/Jamulus.log
PUBLISH_SCRIPT=${JAMULUS_ROOT}/bin/publish-recordings.sh
NO_CLIENT_CONNECTED=',, server \(stopped\|idling\) --*-$'
NO_CLIENT_INTERVAL=$(( 30 ))
LOG_WRITE_INTERVAL=$(( 5 * 60 ))

# Most recent processing check
MOST_RECENT=9999999999

# Do not return until a new jamdir exists in the recording dir
wait_for_new_jamdir () {
echo "wait_for_new_jamdir"
	while true
	do
		[[ ! -z $(find -L "${JAMULUS_RECORDING_DIR}" -mindepth 1 -type d -prune) ]] && {
echo "wait_for_new_jamdir: there is definitely a directory awaiting processing - go wait for end of session"
			break
		}
		[[ ${MOST_RECENT} -lt $(date -r "${JAMULUS_RECORDING_DIR}" "+%s") ]] && {
echo "wait_for_new_jamdir: jamdir changed since last check - go check"
			break
		}
echo "wait_for_new_jamdir: otherwise sleep for a while or until something happens"
		inotifywait -q -t ${NEW_JAMDIR_INTERVAL} -e create -e close_write "${JAMULUS_RECORDING_DIR}"
	done
echo "wait_for_new_jamdir: new jamdir created"
	true
}
#

# Do not return until the server has no connections
wait_for_quiet () {
echo "wait_for_quiet"
	# wait until the log file exists
	while true
	do
		[ -f "${JAMULUS_LOGFILE}" ] && {
echo "wait_for_quiet: logfile exists"
			break
		}
		inotifywait -q -e create -e close_write "${JAMULUS_LOGFILE}"
	done

	# we may get lucky and no client is connected - but need to wait briefly
	sleep ${NO_CLIENT_INTERVAL}

echo "wait_for_quiet: wait for no client connected"
	# otherwise wait until no one connected, check on each log write
	while true
	do
		{ tail -1 "${JAMULUS_LOGFILE}" | grep -q -- "${NO_CLIENT_CONNECTED}"; } && {
echo "wait_for_quiet: no one connected"
			break
		}
echo "wait_for_quiet: otherwise sleep for a while or until something happens"
		inotifywait -q -t ${LOG_WRITE_INTERVAL} -e close_write "${JAMULUS_LOGFILE}"
	done
	true
}

while wait_for_new_jamdir && wait_for_quiet
do
echo "jamdir and quiet... publishing"
	"${PUBLISH_SCRIPT}" || true
echo "updating MOST_RECENT"
	MOST_RECENT=$(date -r "${JAMULUS_RECORDING_DIR}" "+%s")
	if [[ ! -z $(find -L "${JAMULUS_RECORDING_DIR}" -mindepth 1 -type d -prune) ]]
	then
		echo >&2 "${JAMULUS_RECORDING_DIR} has subdirectories"
	fi
done
