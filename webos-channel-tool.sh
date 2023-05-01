#! /usr/bin/env bash

# webos-channel-tool.sh - Save custom channels from Goldstar webOS channel
# dumps and apply these to new data after a re-tune.

# TODO: Make blocked-channels list configurable.
# TODO: Should we be setting the 'Deleted' flag on channels 790-798? This is
#       the 'graveyard' range for services to be removed, but doesn't offer the
#       chance for the user to recover data if this was not intended.
# TODO: Validate whether 'isUserSelCHNo' is in any way harmful, or even used...

set -u
set -o pipefail
set +o histexpand

declare -r debug="${DEBUG:-}"
declare -r trace="${TRACE:-}"

declare -r STDIN=0
declare -r STDOUT=1

output() {
	echo -e "${*:-}"
} # output

print() {
	if (( debug )); then
		if [[ -n "${*:-}" ]]; then
			output >&2 "DEBUG: ${*}"
		else
			output >&2 "DEBUG"
		fi
	fi
} # print

note() {
	output "NOTE: ${*:-}"
} # note

warn() {
	output >&2 "WARN: ${*:-}"
} # warn

die() {
	output >&2 "FATAL: ${*:-Unknown error}"
	exit 1
} # die

#extract() {
#	local line="${*:-}"
#	local tnsf='' name=''
#	local -i tid=-1 nid=-1 sid=-1 f=-1 deleted=0 channel=-1
#
#	if [[ "${line:-}" == '' ]]; then
#		#output >&2
#		:
#	elif ! [[ "${line:-}" =~ ^.+\ :\ .+\ [=!]\ .+$ ]]; then
#		output >&2 "\\nWARN: Invalid line '${line}'"
#	else
#		tnsf="$( awk '{ print $1 }' <<<"${line}" )"
#		(( tid = $( awk -F':' '{ print $1 }' <<<"${tnsf}" ) ))
#		(( nid = $( awk -F':' '{ print $2 }' <<<"${tnsf}" ) ))
#		(( sid = $( awk -F':' '{ print $3 }' <<<"${tnsf}" ) ))
#		(( f = $( awk -F':' '{ print $4 }' <<<"${tnsf}" ) ))
#		#title="$( awk '{ print $3 }' <<<"${line}" )"
#		#name="$( xxd -p -r <<<"${title}" )"
#		name="$( awk '{ for( i = 3 ; i <= NF - 2 ; i++ ) printf("%s%s", $i, (i == NF - 2) ? "\n" : OFS)	}' <<<"${line}" )"
#		if [[ "$( awk '{ print $(NF - 1 ) }' <<<"${line}" )" == '!' ]]; then
#			deleted=1
#		else
#			deleted=0
#		fi
#		(( channel = $( awk '{ print $NF }' <<<"${line}" ) )) ||
#			die "Error processing numeric last field from final field of line '${line}'"
#
#		echo "${tid} ${nid} ${sid} ${f} ${channel} ${deleted} ${name}"
#	fi
#} # extract

show() {
	local list=''

	printf >&2 "Processing, please wait ..."

	list="$(
		local name=''
		local -i deleted=0 channel=-1
		local -A seen=() 2>/dev/null || die "bash-4 Associative Array support required"

		while read -r line; do
			if [[ "${line:-}" == '' ]]; then
				#printf $'\n'
				:
			elif ! [[ "${line:-}" =~ ^.+\ :\ .+\ [=!]\ .+$ ]]; then
				output >&2 "\\nWARN: Invalid line '${line}'"
			else
				# e.g. '4173:12320:4173:522000 : BBC ONE East = 1'

				name="$( awk '{ for( i = 3 ; i <= NF - 2 ; i++ ) printf("%s%s", $i, (i == NF - 2) ? "\n" : OFS)	}' <<<"${line}" )"
				if [[ "$( awk '{ print $(NF - 1) }' <<<"${line}" )" == '!' ]]; then
					deleted=1
				else
					deleted=0
				fi
				(( channel = $( awk '{ print $NF }' <<<"${line}" ) ))

				if ! (( deleted )); then
					if [[ -n "${seen[${name}]:-}" ]]; then
						output "${channel}\\t${name} [DUPLICATE]"
					else
						output "${channel}\\t${name}"
					fi
				fi
				seen[${name}]+=1

				printf >&2 '.'
			fi
		done < <( sed $'s:\r::g' )
	)"
	printf >&2 $'\n'
	sort -n <<<"${list}"
} # show

save() {
	local title='' name='' tag='' dest=''
	local -i tid=-1 nid=-1 sid=-1 f=-1 svc=-1 number=-1 channel=-1 check=-1 deleted=-1 state=0 count=0
	local -a tags=()
	local -A seen=() vars=() 2>/dev/null || die "bash-4 Associative Array support required"

	output >&2 "Processing, please wait ..."

	# States:
	# 0 - Preamble/between items
	# 1 - Processing ITEM

	# Notes:
	# There is a retuning mode which promises to look for new channels only
	# without disturbind existing ones... which overwrites them anyway.
	# The XML also includes an 'isUserSelCHNo' attribute per channel, which
	# is always zero.  I wonder whether these two facts are related...

	while read -r line; do
		print "Read line '${line}'"

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

			if [[ -z "${title:-}" ]]; then
				warn "No name found for channel #${count}"
			else
				name="$( xxd -p -r <<<"${title}" )"
			fi

			(( tid < 0 )) && die "Found no 'transport_id' for channel '${name:-#${count}}'"
			(( nid < 0 )) && die "Found no 'network_id' for channel '${name:-#${count}}'"
			(( sid < 0 )) && die "Found no 'service_id' for channel '${name:-#${count}}'"
			(( f < 0 )) && die "Found no 'frequency' for channel '${name:-#${count}}'"
			(( svc < 0 )) && die "Found no 'serviceType' for channel '${name:-#${count}}'"
			(( number < 0 )) && warn "Found no 'programNo' for channel '${name:-#${count}}'"
			if (( sid != number )); then
				warn "'service_id'(${sid}) and 'programNo'(${number}) do not match for channel '${name:-}'(#${count})"
			fi
			if [[ -n "${seen["${tid}:${nid}:${sid}:${f}"]:-}" ]]; then
				warn "Duplicate TNSF '${tid}:${nid}:${sid}:${f}' for additional channel '${name:-}'(#${count})"
			else
				seen["${tid}:${nid}:${sid}:${f}"]=1
			fi

			(( check < 0 )) && warn "Found no 'prNum' for channel '${name:-#${count}}'"
			(( channel < 0 )) && warn "Found no 'minorNum' for channel '${name:-#${count}}'"

			# Radio channels have serviceType == 2 and high prNum
			if (( 2 == svc )) && ! (( 0 == channel )); then
				if (( channel < 700 )) || (( channel > 798 )); then
					local -i n=0 t=0

					(( t = channel ))

					for n in {1..99}; do
						if [[ -z "${seen["$(( 700 + n ))"]:-}" ]]; then
							break
						fi
					done
					(( channel = 700 + n ))
					unset n

					warn "Channel '${name:-}'(#${count}) is a radio service, but ${t} is not in channel range 700-798 - relocating to ${channel}"
					unset t
				fi
			elif ! (( check == channel )); then
				if (( check > 798 )); then
					if (( 0 == channel )); then
						warn "'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), possible relocated duplicate channel? - using 'prNum' value ${check}"
						local -i t=0
						(( t = channel ))
						(( channel = check ))
						(( check = t ))
						unset t
					else
						warn "'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), possible relocated duplicate channel? - using 'minorNum' value ${channel}"
					fi
				elif (( check > 699 && check < 799 )); then
					warn "'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}), but 'prNum' indicates a Radio service - using 'minorNum' value ${channel}"
				else
					warn "'prNum'(${check}) and 'minorNum'(${channel}) do not match for channel '${name:-}'(#${count}) - using 'prNum' value ${check}"
					local -i t=0
					(( t = channel ))
					(( channel = check ))
					(( check = t ))
					unset t
				fi
			fi
			if ! (( 2 == svc )) && (( channel > 699 && channel < 799 )) && ! (( 0 == channel )); then
				local -i n=0 t=0

				(( t = channel ))

				for n in {1..199}; do
					if [[ -z "${seen["$(( 800 + n ))"]:-}" ]]; then
						break
					fi
				done
				(( channel = 800 + n ))
				unset n

				warn "Channel '${name:-}'(#${count}) is not a radio service, but ${t} is in channel range 700-798 - relocating to ${channel}"
				unset t
			fi
			if (( 0 == check )) || (( 0 == channel )); then
				if (( deleted )); then
					print "Channel '${name:-}'(#${count}) has been deleted"
				else
					warn "Channel '${name:-}(#${count}) has zero 'prNum'(${check}) or 'minorNum'(${channel}) but is not marked as deleted"
				fi
			else
				if (( deleted )); then
					warn "Channel '${name:-}'(#${count}) has non-zero 'prNum'(${check}) or 'minorNum'(${channel}) but is marked as deleted"
				fi
			fi
			if ! (( 0 == channel )) && [[ -n "${seen["${channel}"]:-}" ]]; then
				local -i n=0 t=0

				(( t = channel ))

				for n in {1..199}; do
					if [[ -z "${seen["$(( 800 + n ))"]:-}" ]]; then
						break
					fi
				done
				(( channel = 800 + n ))
				unset n

				warn "Channel '${name:-}'(#${count}) found on channel ${t}, which is already in use - relocating to channel ${channel}"
			fi
			(( 0 == channel )) || seen["${channel}"]=1

			output "${tid}:${nid}:${sid}:${f} : ${name} $( (( deleted )) && printf '!' || printf '=' ) ${channel}"

			state=0

		else
			vars['prNum']='check'
			vars['minorNum']='channel'
			vars['transport_id']='tid'
			vars['network_id']='nid'
			vars['service_id']='sid'
			vars['frequency']='f'
			vars['serviceType']='svc'
			vars['programNo']='number'
			vars['hexVchName']='title'
			vars['isDeleted']='deleted'
			tags=( # <- Syntax
				prNum
				minorNum
				transport_id
				network_id
				service_id
				frequency
				serviceType
				programNo
				hexVchName
				isDeleted
			)

			for tag in "${tags[@]}"; do
				if [[ "${line}" == "<${tag}>"* ]]; then
					dest="${vars["${tag}"]}"
					if [[ "${dest}" == 'title' ]]; then
						eval "${dest}=$( sed -ne "/${tag}/{s/.*<${tag}>\\(.*\\)<\\/${tag}>.*/\\1/p;q;}" <<<"${line}" )"
					else
						eval "(( ${dest} = $( sed -ne "/${tag}/{s/.*<${tag}>\\(.*\\)<\\/${tag}>.*/\\1/p;q;}" <<<"${line}" ) ))"
					fi
					break
				fi
			done
		fi
	done < <( sed $'s:\r::g' )
} # save

apply() {
	local file="${1:-}"

	[[ -n "${file:-}" ]] ||
		die "${FUNCNAME[0]}(${LINENO}) Required parameter 'file' not set"

	local line='' entry='' title='' name='' newname='' tnsf='' tag=''
	local -i tid=-1 nid=-1 sid=-1 f=-1 number=-1 \
			deleted=0 channel=-1 newdeleted=0 newchannel=-1 \
			check=-1 deleted=-1 state=0 count=0
	local -a item=() tags=()
	local -A channels=() seen=() vars=() 2>/dev/null ||
		die "bash-4 Associative Array support required"

	vars['prNum']='check'
	vars['minorNum']='channel'
	vars['transport_id']='tid'
	vars['network_id']='nid'
	vars['service_id']='sid'
	vars['frequency']='f'
	vars['serviceType']='svc'
	vars['programNo']='number'
	vars['hexVchName']='title'
	vars['isDeleted']='deleted'
	tags=( # <- Syntax
		prNum
		minorNum
		transport_id
		network_id
		service_id
		frequency
		#serviceType
		programNo
		hexVchName
		isDeleted
	)

	# Reserve channels from being re-allocated...
	# ... update: it's back!
	#seen["3"]=1 # Old BBC Three

	output >&2 "Processing channel list ..."

	while read -r line; do
		if ! [[ "${line}" =~ ^.+\ :\ .+\ [=!]\ .+$ ]]; then
			output >&2 "\\nWARN: Invalid line '${line}'"
		else
			# e.g. '4173:12320:4173:522000 : BBC ONE East = 1'

			tnsf="$( awk '{ print $1 }' <<<"${line}" )"
			name="$( awk '{ for( i = 3 ; i <= NF - 2 ; i++ ) printf("%s%s", $i, (i == NF - 2) ? "\n" : OFS)	}' <<<"${line}" )"
			if [[ "$( awk '{ print $(NF - 1 ) }' <<<"${line}" )" == '!' ]]; then
				deleted=1
			else
				deleted=0
			fi
			(( channel = $( awk '{ print $NF }' <<<"${line}" ) )) ||
				die "Error processing numeric last field from final field of line '${line}'"

			channels["${tnsf}"]="${channel} ${deleted} ${name}"

			printf >&2 '.'
		fi
	done < <( sed $'s:\r::g' )
	printf >&2 $'\n\n'

	output >&2 "Processing XML channel data ..."

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

			for entry in "${item[@]}"; do
				for tag in "${tags[@]}"; do
					if [[ "${entry}" == "<${tag}>"* ]]; then
						dest="${vars["${tag}"]}"
						if [[ "${dest}" == 'title' ]]; then
							eval "${dest}=$( sed -ne "/${tag}/{s/.*<${tag}>\\(.*\\)<\\/${tag}>.*/\\1/p;q;}" <<<"${entry}" )"
							name="$( xxd -p -r <<<"${title}" )"
						else
							eval "(( ${dest} = $( sed -ne "/${tag}/{s/.*<${tag}>\\(.*\\)<\\/${tag}>.*/\\1/p;q;}" <<<"${entry}" ) ))"
						fi
						break
					fi
				done
			done

			tnsf="${tid}:${nid}:${sid}:${f}"

			if [[ -z "${channels["${tnsf}"]:-}" ]]; then
				# Ignore entries where channel == 0...
				#
				if (( 0 != channel )); then

					if ! (( deleted )) && (( channel > 699 && channel < 799 )); then
						note >&2 "Channel '${name:-}' (${tnsf}) on channel ${channel} does not exist in provided channel list, keeping current values"
						seen["${channel}"]=1

						#for entry in "${item[@]}"; do
						#	output "${entry}"
						#done
						(( newchannel = channel ))
						(( newdeleted = deleted ))
						newname="${name:-}"
					else
						local -i n=0
						for n in {1..199}; do
							if [[ -z "${seen["$(( 800 + n ))"]:-}" ]]; then
								break
							fi
						done
						(( newchannel = 800 + n ))
						unset n

						(( newdeleted = deleted ))
						newname="${name:-}"

						if [[ -z "${seen["${channel}"]:-}" ]]; then
							warn "$( (( deleted )) && printf 'Deleted c' || printf 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} does not exist in provided channel list, relocating to ${newchannel}"
						else # [[ -n "${seen["${channel}"]:-}" ]]; then
							warn "$( (( deleted )) && printf 'Deleted c' || printf 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} does not exist in provided channel list, but channel ${channel} is already in use, relocating to ${newchannel}"
						fi
						seen["${newchannel}"]=1
					fi
				fi
			else # [[ -n "${channels["${tnsf}"]:-}" ]]; then

				# channels["${tnsf}"]="${channel} ${deleted} ${name}"

				(( newchannel = $( awk '{ print $1 }' <<<"${channels["${tnsf}"]}" ) ))

				case "$( awk '{ print $2 }' <<<"${channels["${tnsf}"]}" )" in
					1)
						(( newdeleted = 1 ))
						;;
					0)
						(( newdeleted = 0 ))
						;;
					*)
						die "Logic error: Read deleted flag '$( awk '{ print $2 }' <<<"${channels["${tnsf}"]}" )' from channel-list entry '${channels["${tnsf}"]}'"
						;;
				esac

				newname="$( cut -d' ' -f 3- <<<"${channels["${tnsf}"]}" )"

				if (( 0 != newchannel )) && [[ -n "${seen["${newchannel}"]:-}" ]]; then
					declare -i n=0
					for n in {1..199}; do
						if [[ -z "${seen["$(( 800 + n ))"]:-}" ]]; then
							break
						fi
					done
					# The following two lines intentionally ordered as below...
					warn "$( (( newdeleted )) && printf 'Deleted c' || printf 'C' )hannel '${name:-}' (${tnsf}) on channel ${channel} is set to move to ${newchannel}), which is already in use - relocating to channel $(( 800 + n ))"
					(( newchannel = 800 + n ))
					unset n
				fi

				seen["${newchannel}"]=1
			fi

			# FIXME: We always discard a newname, and there's not even logic
			#        to output a new value?!
			if [[ "${newname}" != "${name}" ]]; then
				if ! { (( 1 == newdeleted )) && (( 0 == channel )) && (( 0 == newchannel )) ; }; then
					warn "$( (( newdeleted )) && printf 'Deleted c' || printf 'C' )hannel ${channel} (${tnsf}, ${channel} -> ${newchannel}) has changed name from '${newname}' to '${name}' - keeping new name '${name}'"
				fi
				newname="${name}"
			fi

			if (( 0 == newchannel )) && ! (( newdeleted )); then
				warn "$( (( deleted )) && printf 'Deleted c' || printf 'C' )hannel '${name}' (${tnsf}, ${channel}) is being moved to channel ${newchannel} - setting deleted flag"
				(( newdeleted = 1 ))
			fi

			if (( newdeleted != deleted )); then
				if (( deleted )); then
					note >&2 "$( (( deleted )) && printf 'Deleted c' || printf 'C' )hannel '${name}' (${tnsf}, ${channel} -> ${newchannel}) was deleted, is now active"
				else
					note >&2 "$( (( deleted )) && printf 'Deleted c' || printf 'C' )hannel '${name}' (${tnsf}, ${channel} -> ${newchannel}) was active, is now deleted"
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

				elif
					[[ "${entry}" == '<isUserSelCHNo>'* ]] &&
						(( channel != newchannel ))
				then
					echo "<isUserSelCHNo>1</isUserSelCHNo>"

				else
					echo "${entry}"
				fi
			done

		elif (( 1 == state )); then
			item+=( "${line}" )

		else # (( 0 == state )); then
			echo "${line}"
		fi
	done < <( sed $'s:\r::g' "${file}" )
} # apply

main() {
	local mode='' file='GlobalClone00001.TLL'

	case "${*:-}" in
		-h|--help)
			output 'Usage:'
			output "\\t$( basename "${0}" ) --save < ${file} | tee channel.list"
			output "\\t$( basename "${0}" ) --show < channel.list"
			output "\\t$( basename "${0}" ) --apply [${file}] < channel.list | tee GlobalClone00001.TLL"
			exit 0
			;;
		-s|--save)
			mode='save'
			;;
		-a\ *|--apply\ *)
			mode='apply'
			if [[ -z "${2:-}" ]]; then
				warn "Using default XML file name '${file}'"
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

	[[ -t "${STDIN}" ]] && die 'Expected input file connected to stdin'
	if [[ "${mode}" != 'show' ]]; then
		[[ -t "${STDOUT}" ]] && warn 'No output file connected to stdout'
	fi
	#[[ -r "${file}" ]] || die "Cannot read XML file '${file}'"

	(( trace )) && set -o xtrace

	declare line=''

	if [[ "${mode}" == 'show' ]]; then
		show
	elif [[ "${mode}" == 'save' ]]; then
		save
	elif [[ "${mode}" == 'apply' ]]; then
		apply "${file}"
	else
		die "Unknown mode '${mode}'"
	fi

	(( trace )) && set +o xtrace
} # main

main "${@}"
exit ${?}

# vi: set noet foldmethod=marker foldmarker=()\ {,}\ #\  sw=4 ts=4:
