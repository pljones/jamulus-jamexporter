# Jamulus Jam Exporter

_General note:_

The scripts here are derived from what I use on my own server - they have been altered to be less dependent
on the way I run my server and hence are not scripts I actually run.  Which means my changes are subject to bugs.

This comprises two scripts:
* A bash script to monitor the Jamulus recording base directory for new recordings
* A bash script to apply some judicious rules and compression before uploading the recordings offsite

## Systemd Service
Also supplied is a systemd service file to start the monitor script:
* `src/systemd/inotify-publisher.service`

This contains the path to the monitor script in the `ExecStart=` line and the `User=` and `Group=` lines need to
match how you usually run Jamulus.

## inotify-publisher.sh monitoring script
The configuration section at the top has the following:
* `JAMULUS_ROOT=/opt/Jamulus`
* `JAMULUS_RECORDING_DIR=${JAMULUS_ROOT}/run/recording`
* `JAMULUS_STATUSPAGE=${JAMULUS_ROOT}/run/status.html`
* `PUBLISH_SCRIPT=${JAMULUS_ROOT}/bin/publish-recordings.sh`
* `NO_CLIENT_CONNECTED="No client connected"`

You may need to edit more than just `JAMULUS_ROOT` - adjust to suit.
I'm not sure if the status file entry `NO_CLIENT_CONNECT` gets translated - if so, the local value is needed here.

The script uses one program that you might not have installed by default, `inotifywait`.
* http://inotify-tools.sourceforge.net/

I would expect your distribution makes this available.


## publish-recordings.sh prepare and upload script
**NOTE** PLEASE read and understand, at least basically, what this does _before_ using it.  It makes _destructive edits_
to recordings that you might not want.  It was written to do what I needed and is provided for people to have a base to
work from, _not_ as a working solution to your needs.

### What it does
Given the right `RECORDING_DIR`, this iterates over all subdirectories, looking for Reaper RPP files.
(Currently, the Audacity LOF files are ignored and become wrong.)

The logical processing is as follows.

For each RPP file, the WAV files are examined to determine their audio length and (EBU) volume.  Where the file
is considered "too short" or "too quiet", it is removed (deleted on disk and edited out of the RPP file).
Retained files then have audio compression applied, updating the RPP file with the new name (i.e. WAV -> OPUS).
Any _track_ that now has no entries is also removed.  If the project has no tracks, the recording directory is deleted.

After the above processing, any remaining recording directory gets zipped (without the broken LOF)
and uploaded to `RECORDING_HOST_DIR`.

### Configuration

There is one main dependency here: the FFMpeg suite - both `ffprobe` and `ffmpeg` itself are used.
* https://ffmpeg.org/

It also uses `zip`.
* http://infozip.sourceforge.net/

Most distributions provide versions that will be adequate.

The configuration section here is simpler:
* `RECORDING_DIR=/opt/Jamulus/run/recording`
* `RECORDING_HOST_DIR=drealm.info:html/jamulus/`

The script off-sites the recordings - `RECORDING_HOST_DIR` is the target.  It uses `scp` as the user running the script.
If run from `inotify-publisher.sh` under the systemd service, that will be the `User=` user.  Make sure you have installed
that user's public key in your hosting provider's `authorized_keys` (using the expected key type).


## recover-recording.sh
Also included is a "recovery mode" script.  This helps you recreate any lost Reaper RPP or Audacity LOF
project files from a Jamulus recording directory.  There is a `--help` option that provides the full syntax.

The intent of this script is to take an existing collection of Jamulus recorded WAVE files and generate the
Reaper RPP and Audacity LOF project files that match the one the server should have created.
It may sometimes be needed, for example when the server fails to terminate the recording correctly
(as that is when the project files gets written).

The script should be run from the directory containing the "failed" recording.
By default, the script writes both RPP and LOF projects to files, using the working directory name and appropriate suffix.
`--rpp` and `--lof` can optionally be followed by a filename, which can be `-` for stdout.
If only one of the two is specified, the other is not written at all.
