#! /usr/bin/env bash

# webos-channel-tool.sh - Save custom channels from Goldstar webOS channel
# dumps and apply these to new data after a re-tune.

# TODO: Make blocked-channels list configurable.
# TODO: Should we be setting the 'Deleted' flag on channels 790-799? This is
#       the 'graveyard' range for services to be removed, but doesn't offer the
#       chance for the user to recover data if this was not intended.
# TODO: Validate whether 'isUserSelCHNo' is in any way harmful, or even used...

set -u
set -o pipefail
set +o histexpand

function die() {
	echo >&2 "FATAL: ${*:-Unknown error}"
	exit 1
} # die

declare -r debug="${DEBUG:-}"
declare -r trace="${TRACE:-}"

declare mode='' file='GlobalClone00001.TLL'

case "${*:-}" in
	-h|--help)
		echo 'Usage:'
		echo -e "\\t$( basename "${0}" ) --save < ${file} | tee channel.list"
		echo -e "\\t$( basename "${0}" ) --show < channel.list"
		echo -e "\\t$( basename "${0}" ) --apply [${file}] < channel.list | tee GlobalClone00001.TLL"
		exit 0
		;;
	-s|--save)
		mode='save'
		;;
	-a\ *|--apply\ *)
		mode='apply'
		if ! [[ -n "${2:-}" ]]; then
			echo >&2 "WARN: Using default XML file name '${file}'"
		else
			if ! [[ -r "${2}" ]]; then
				die "Cannot read file '${2}'"
			else
				file="${2}"
				shift
			fi
		fi
		;;
	-w|--show)
		mode='show'
		;;
	'')
		die "Mode of operation required - see $( basename "${0}" ) --help"
		;;
	*)
		die "Unknown argument '${*:-}'"
		;;
esac

declare -r STDIN=0
declare -r STDOUT=1

[[ -t $STDIN ]] && die 'Expected input file connected to stdin'
if [[ "${mode}" != 'show' ]]; then
	[[ -t $STDOUT ]] && echo >&2 'WARN: No output file connected to stdout'
fi
#[[ -r "${file}" ]] || die "Cannot read XML file '${file}'"

(( trace )) && set -o xtrace

declare line=''

if [[ "${mode}" == 'show' ]]; then
	declare title name tnsf
	declare -i tid nid sid f deleted=0 channel
	declare -A seen=() 2>/dev/null || die "bash-4 Associative Array support required"

	echo >&2 "Processing, please wait ..."

	while read -r line; do
		if [[ "${line:-}" == '' ]]; then
			echo
		elif ! [[ "${line:-}" =~ ^.*\ :\ .*\ [=!]\ .*$ ]]; then
			echo >&2 -e "\\nWARN: Invalid line '${line}'"
		else
			tnsf="$( cut -d' ' -f 1 <<<"${line}" )"
			(( tid = $( cut -d':' -f 1 <<<"${tnsf}" ) ))
			(( nid = $( cut -d':' -f 2 <<<"${tnsf}" ) ))
			(( sid = $( cut -d':' -f 3 <<<"${tnsf}" ) ))
			(( f = $( cut -d':' -f 4 <<<"${tnsf}" ) ))
			#title="$( cut -d' ' -f 3 <<<"${line}" )"
			#name="$( xxd -p -r <<<"${title}" )"
			name="$( cut -d' ' -f 3- <<<"${line}" | rev | cut -d' ' -f 3- | rev)"
			if [[ "$( rev <<<"${line}" | cut -d' ' -f 2 )" == '!' ]]; then
				deleted=1
			else
				deleted=0
			fi
			(( channel = $( rev <<<"${line}" | cut -d' ' -f 1 | rev ) ))

			if ! (( deleted )); then
				if [[ -n "${seen[${name}]:-}" ]]; then
					echo -e "${channel}\\t${name} [DUPLICATE]"
				else
					echo -e "${channel}\\t${name}"
				fi
			fi
			seen[${name}]+=1

			echo >&2 -n '.'
		fi
	done < <( echo ; sed $'s:\r::g' ) | sort -n

elif [[ "${mode}" == 'save' ]]; then
	declare title name
	declare -i tid nid sid f svc number channel check deleted state=0 count=0
	declare -A seen=() 2>/dev/null || die "bash-4 Associative Array support required"

	# States:
	# 0 - Preamble/between items
	# 1 - Processing ITEM

	# Notes:
	# There is a retuning mode which promises to look for new channels only
	# without disturbind existing ones... which overwrites them anyway.
	# The XML also includes an 'isUserSelCHNo' attribute per channel, which
	# is always zero.  I wonder whether these two facts are related...

	while read -r line; do
		(( debug )) && echo >&2 "DEBUG: Read line '${line}'"

		if [[ "${line}" == '<ITEM>' ]]; then
			(( 0 == state )) || die "Logic error: Found ITEM whilst processing ITEM"

			title=''
			name=''
			tid=-1
			nid=-1
			sid=-1
			f=-1
			svc=-1
			number=-1
			channel=-1
			check=-1
			deleted=-1
			state=1
			(( count ++ ))

		elif [[ "${line}" == '</ITEM>' ]]; then
			(( 1 == state )) || die "Logic error: Found ITEM end whilst not processing ITEM"

			if ! [[ -n "${title:-}" ]]; then
				echo >&2 "WARN: No name found for channel #${count}"
			else
				name="$( xxd -p -r <<<"${title}" )"
			fi

			(( tid < 0 )) && die "Found no 'transport_id' for channel '${name:-#${count}}'"
			(( nid < 0 )) && die "Found no 'network_id' for channel '${name:-#${count}}'"
			(( sid < 0 )) && die "Found no 'service_id' for channel '${name:-#${count}}'"
			(( f < 0 )) && die "Found no 'frequency' for channel '${name:-#${count}}'"
			(( svc < 0 )) && die "Found no 'serviceType' for channel '${name:-#${count}}'"
			(( number < 0 )) && echo >&2 "WARN: Found no 'programNo' for channel '${name:-#${count}}'"
			if (( sid != number )); then
				echo >&2 "WARN: 'service_id'(${sid}) and 'programNo'(${number}) do not match for channel '${name:-}'(#${count})"
			fi
			if [[ -n "${seen["${tid}:${nid}:${sid}:${f}"]:-}" ]]; then
				echo >&2 "WARN: Duplicate TNSF '${tid}:${nid}:${sid}:${f}' for additional channel '${name:-}'(#${count})"
			else
				seen["${tid}:${nid}:${sid}:${f}"]=1
			fi

			(( check < 0 )) && echo >&2 "WARN: Found no 'prNum' for channel '${name:-#${count}}'"
			(( channel < 0 )) && echo >&2 "WARN: Found no 'minorNum' for channel '${name:-#${count}}'"

			# Radio channels have serviceType == 2 and high prNum
			if (( 2 == svc )) && ! (( 0 == channel )); then
				if (( channel < 700 )) || (( channel > 799 )); then
					declare -i n=0 t=0

					(( t = channel ))

					for n in $( seq 0 99 ); do
						if ! [[ -n "${seen["$(( 700 + n ))"]:-}" ]]; then
							break
						fi
					done
					(( channel = 700 + n ))
					unset n

					echo >&2 "WARN: Channel '${name:-}'(#${count}) is a radio service, but ${t} is not in channel range 700-799 - relocating to ${channel}"
					unset t
				fi
			elif ! (( check == channel )); then
				if (( check > 799 )); then
					if (( 0 == channel )); then
						echo >&2 "WARN: 'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), possible relocated duplicate channel? - using 'prNum' value ${check}"
						declare -i t=0
						(( t = channel ))
						(( channel = check ))
						(( check = t ))
						unset t
					else
						echo >&2 "WARN: 'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), possible relocated duplicate channel? - using 'minorNum' value ${channel}"
					fi
				elif (( check > 699 && check < 800 )); then
					echo >&2 "WARN: 'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), but 'prNum' indicates a Radio service - using 'minorNum' value ${channel}"
				else
					echo >&2 "WARN: 'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}) - using 'prNum' value ${check}"
					declare -i t=0
					(( t = channel ))
					(( channel = check ))
					(( check = t ))
					unset t
				fi
			fi
			if ! (( 2 == svc )) && (( channel > 699 && channel < 800 )) && ! (( 0 == channel )); then
				declare -i n=0 t=0

				(( t = channel ))

				for n in $( seq 0 99 ); do
					if ! [[ -n "${seen["$(( 800 + n ))"]:-}" ]]; then
						break
					fi
				done
				(( channel = 800 + n ))
				unset n

				echo >&2 "WARN: Channel '${name:-}'(#${count}) is not a radio service, but ${t} is in channel range 700-799 - relocating to ${channel}"
				unset t
			fi
			if (( 0 == check )) || (( 0 == channel )); then
				if (( deleted )); then
					(( debug )) && echo >&2 "DEBUG: Channel '${name:-}'(#${count}) has been deleted"
				else
					echo >&2 "WARN: Channel '${name:-}(#${count}) has zero 'prNum'(${check}) or 'minorNum'(${channel}) but is not marked as deleted"
				fi
			else
				if (( deleted )); then
					echo >&2 "WARN: Channel '${name:-}'(#${count}) has non-zero 'prNum'(${check}) or 'minorNum'(${channel}) but is marked as deleted"
				fi
			fi
			if ! (( 0 == channel )) && [[ -n "${seen["${channel}"]:-}" ]]; then
				declare -i n=0 t=0

				(( t = channel ))

				for n in $( seq 0 99 ); do
					if ! [[ -n "${seen["$(( 800 + n ))"]:-}" ]]; then
						break
					fi
				done
				(( channel = 800 + n ))
				unset n

				echo >&2 "WARN: Channel '${name:-}'(#${count}) found on channel ${t}, which is already in use - relocating to channel ${channel}"
			fi
			(( 0 == channel )) || seen["${channel}"]=1

			echo "${tid}:${nid}:${sid}:${f} : ${name} $( (( deleted )) && echo -n '!' || echo -n '=' ) ${channel}"

			state=0

		elif [[ "${line}" == '<prNum>'* ]]; then
			(( check = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<minorNum>'* ]]; then
			(( channel = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<transport_id>'* ]]; then
			(( tid = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<network_id>'* ]]; then
			(( nid = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<service_id>'* ]]; then
			(( sid = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<frequency>'* ]]; then
			(( f = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<serviceType>'* ]]; then
			(( svc = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<programNo>'* ]]; then
			(( number = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		elif [[ "${line}" == '<hexVchName>'* ]]; then
			title="$( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 )"

		elif [[ "${line}" == '<isDeleted>'* ]]; then
			(( deleted = $( cut -d'>' -f 2- <<<"${line}" | cut -d'<' -f 1 ) ))

		fi
	done < <( sed $'s:\r::g' )

elif [[ "${mode}" == 'apply' ]]; then
	declare line=''
	declare -a item=()
	declare -A channels=() seen=() 2>/dev/null || die "bash-4 Associative Array support required"

	declare name='' newname='' tnsf=''
	declare -i tid nid sid f deleted=0 channel newdeleted=0 newchannel

	declare -i state=0

	# Reserve channels from being re-allocated...
	# ... update: it's back!
	#seen["3"]=1 # Old BBC Three

	echo >&2 "INFO: Processing channel list ..."

	while read -r line; do
		if ! [[ "${line}" =~ ^.*\ :\ .*\ [=!]\ .*$ ]]; then
			echo >&2 -e "\\nWARN: Invalid line; '${line}'"
		else
			tnsf="$( cut -d' ' -f 1 <<<"${line}" )"
			name="$( cut -d' ' -f 3- <<<"${line}" | rev | cut -d' ' -f 3- | rev)"
			if [[ "$( rev <<<"${line}" | cut -d' ' -f 2 )" == '!' ]]; then
				deleted=1
			else
				deleted=0
			fi
			(( channel = $( rev <<<"${line}" | cut -d' ' -f 1 | rev ) ))

			channels["${tnsf}"]="${name} ${channel} ${deleted}"

			echo >&2 -n '.'
		fi
	done < <( sed $'s:\r::g' )
	echo >&2

	echo >&2 "INFO: Processing XML channel data ..."

	# States:
	# 0 - Preamble/between items
	# 1 - Processing ITEM

	while read -r line; do
		if [[ "${line}" == '<ITEM>' ]]; then
			item=()
			item+=( "${line}" )
			state=1

		elif [[ "${line}" == '</ITEM>' ]]; then
			item+=( "${line}" )
			state=0

			declare entry title name
			declare -i tid nid sid f number channel check deleted state=0 count=0

			for entry in "${item[@]}"; do
				if [[ "${entry}" == '<prNum>'* ]]; then
					(( check = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<minorNum>'* ]]; then
					(( channel = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<transport_id>'* ]]; then
					(( tid = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<network_id>'* ]]; then
					(( nid = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<service_id>'* ]]; then
					(( sid = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<frequency>'* ]]; then
					(( f = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<programNo>'* ]]; then
					(( number = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				elif [[ "${entry}" == '<hexVchName>'* ]]; then
					title="$( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 )"
					name="$( xxd -p -r <<<"${title}" )"

				elif [[ "${entry}" == '<isDeleted>'* ]]; then
					(( deleted = $( cut -d'>' -f 2- <<<"${entry}" | cut -d'<' -f 1 ) ))

				fi
			done

			tnsf="${tid}:${nid}:${sid}:${f}"

			if ! [[ -n "${channels["${tnsf}"]:-}" ]] && ( (( 0 == channel )) || ! [[ -n "${seen["${channel}"]:-}" ]] ); then
				if ! (( channel == 0 )) && ! (( deleted )); then
					echo >&2 "NOTE: $( (( deleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} does not exist in provided channel list, keeping current values"
				fi
				seen["${channel}"]=1
				for entry in "${item[@]}"; do
					echo "${entry}"
				done

			else
				if ! [[ -n "${channels["${tnsf}"]:-}" ]]; then # && (( 0 != channel )) && [[ -n "${seen["${channel}"]:-}" ]]; then
					declare -i n=0
					for n in $( seq 0 99 ); do
						if ! [[ -n "${seen["$(( 800 + n ))"]:-}" ]]; then
							break
						fi
					done
					(( newchannel = 800 + n ))
					unset n
					newname="${name:-}"
					(( newdeleted = deleted ))
					echo >&2 "WARN: $( (( deleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} does not exist in provided channel list, but channel ${channel} is already in use, relocating to ${newchannel}"
					seen["${newchannel}"]=1

				else
					newname="$( rev <<<"${channels["${tnsf}"]}" | cut -d' ' -f 3- | rev )"
					(( newchannel = $( rev <<<"${channels["${tnsf}"]}" | cut -d' ' -f 2 | rev ) ))
					case "$( rev <<<"${channels["${tnsf}"]}" | cut -d' ' -f 1 | rev )" in
						1)
							(( newdeleted = 1 ))
							;;
						0)
							(( newdeleted = 0 ))
							;;
						*)
							die "Logic error: Read deleted flag '$( rev <<<"${channels["${tnsf}"]}" | cut -d' ' -f 1 | rev )' from channel-list entry '${channels["${tnsf}"]}'"
							;;
					esac

					if (( 0 != newchannel )) && [[ -n "${seen["${newchannel}"]:-}" ]]; then
						declare -i n=0
						for n in $( seq 0 99 ); do
							if ! [[ -n "${seen["$(( 800 + n ))"]:-}" ]]; then
								break
							fi
						done
						echo >&2 "WARN: $( (( newdeleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} is set to move to ${newchannel}), which is already in use - relocating to channel $(( 800 + n ))"
						(( newchannel = 800 + n ))
						unset n
					fi
					seen["${newchannel}"]=1
				fi

				if ! [[ "${newname}" == "${name}" ]]; then
					if ! ( (( 1 == newdeleted )) && (( 0 == channel )) && (( 0 == newchannel )) ); then
						echo >&2 "WARN: $( (( newdeleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel ${channel} (${tnsf}, -> ${newchannel}) has changed name from '${newname}' to '${name}' - keeping new name '${name}'"
					fi
					newname="${name}"
				fi

				if (( 0 == newchannel )); then
					if ! (( newdeleted )); then
						echo >&2 "WARN: $( (( deleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name}' (${tnsf}, ${channel}) is being moved to channel ${newchannel} - setting deleted flag"
					fi
					(( newdeleted = 1 ))
				fi
				if ! (( newdeleted == deleted )); then
					if (( deleted )); then
						echo >&2 "NOTE: $( (( deleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name}' (${tnsf}, ${channel} -> ${newchannel}) was deleted, is now active"
					else
						echo >&2 "NOTE: $( (( deleted )) && echo -n 'Deleted c' || echo -n 'C' )hannel '${name}' (${tnsf}, ${channel} -> ${newchannel}) was active, is now deleted"
					fi
				fi

				for entry in "${item[@]}"; do
					# N.B. We read channel number from minorNum, but write to prNum
					# minorNum appears to hold the actual channel number useed in
					# the TV Guide.  However, Radio channels have very high prNum
					# values, and user edits also appear to use the prNum field.
					if [[ "${entry}" == '<prNum>'* ]]; then
						echo "<prNum>${newchannel}</prNum>"
					elif [[ "${entry}" == '<isDeleted>'* ]]; then
						echo "<isDeleted>${newdeleted}</isDeleted>"
					elif [[ "${entry}" == '<isUserSelCHNo>'* ]]; then
						if ! (( channel == newchannel )); then
							echo "<isUserSelCHNo>1</isUserSelCHNo>"
						else
							echo "${entry}"
						fi
					else
						echo "${entry}"
					fi
				done
			fi

		elif (( 1 == state )); then
			item+=( "${line}" )

		else # (( 0 == state )); then
			echo "${line}"

		fi
	done < <( sed $'s:\r::g' "${file}" )

else
	die "Unknown mode '${mode}'"

fi

(( trace )) && set +o xtrace

exit 0
