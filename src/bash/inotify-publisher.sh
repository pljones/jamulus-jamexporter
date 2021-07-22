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
JAMULUS_STATUSPAGE=${JAMULUS_ROOT}/run/status.html
PUBLISH_SCRIPT=${JAMULUS_ROOT}/bin/publish-recordings.sh
CHECK_INTERVAL=$(( 5 * 60 ))
NO_CLIENT_CONNECTED="No client connected"

# Most recent processing check
MOST_RECENT=0

# Do not return until a new jamdir exists in the recording dir
wait_for_new_jamdir () {
	while [[ ${MOST_RECENT} -lt $(date -r "${JAMULUS_RECORDING_DIR}" "+%s") &&
		-z $(find -L "${JAMULUS_RECORDING_DIR}" -mindepth 1 -type d -prune) ]]
	do
		inotifywait -q -t ${CHECK_INTERVAL} -e create -e close_write "${JAMULUS_RECORDING_DIR}"
	done
	MOST_RECENT=$(date -r "${JAMULUS_RECORDING_DIR}" "+%s")
	true
}
#

# Do not return until the server has no connections
wait_for_quiet () {
	# wait until the status page exists
	while ! test -f "${JAMULUS_STATUSPAGE}"
	do
		inotifywait -q -e create -e close_write "${JAMULUS_STATUSPAGE}"
	done

	# wait until no one connected
	while ! grep -q "${NO_CLIENT_CONNECTED}" "${JAMULUS_STATUSPAGE}"
	do
		inotifywait -q -e close_write "${JAMULUS_STATUSPAGE}"
	done
	true
}

while wait_for_new_jamdir && wait_for_quiet
do
	"${PUBLISH_SCRIPT}" || true
	if [[ ! -z $(find -L "${JAMULUS_RECORDING_DIR}" -mindepth 1 -type d -prune) ]]
	then
		echo >&2 "${JAMULUS_RECORDING_DIR} has subdirectories"
	fi
done
