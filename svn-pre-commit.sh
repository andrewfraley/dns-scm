#!/bin/sh

REPOS="$1"
TXN="$2"

SVNLOOK=/usr/bin/svnlook
TEMPFILE=/bin/tempfile
CHECKCONF=/usr/sbin/named-checkconf
CHECKZONE=/usr/sbin/named-checkzone
NAMEDTMP=/data/svn/tmp/named

LOGMSG=$($SVNLOOK log -t "$TXN" "$REPOS" | grep [a-zA-Z0-9] | wc -c)

# Check for a proper log message
if [ "$LOGMSG" -lt 5 ]; then
	echo -e "Please provide a meaningful comment when committing changes." 1>&2
	exit 1
fi

TMPDIR=/tmp/svnlook-${RANDOM}-${RANDOM}-${RANDOM}
mkdir $TMPDIR

# Extract the main config files
CONF="$TMPDIR/named.conf"
CONFEXT="$NAMEDTMP/external.zones"
CONFINT="$NAMEDTMP/internal.zones"

$SVNLOOK cat -t "$TXN" "$REPOS" "/trunk/configs/named.conf" > $CONF
$SVNLOOK cat -t "$TXN" "$REPOS" "/trunk/configs/external.zones" > $CONFEXT
$SVNLOOK cat -t "$TXN" "$REPOS" "/trunk/configs/internal.zones" > $CONFINT

# Check if named.conf validates
if ! $CHECKCONF "$CONF"; then
	echo -e "Please fix the following errors:" 1>&2

	CONFESCAPED=$(echo $CONF | sed 's/\//\\\//g')
	$CHECKCONF "$CONF" | sed "s/$CONFESCAPED/named.conf/" 1>&2
	exit 1
fi

# check committed zone files
ZONEFILES=`$SVNLOOK changed -t "$TXN" "$REPOS" | egrep -v '^D' | egrep 'zones/.*/.*.zone$' | awk '{ print $2 }'`

# Serial number checking lower and upper bounds
UNIXTIME=`date +%s`
STODAY=`date "+%Y%m%d00"`
STOMORROW=`date -d "1970-01-01 UTC $[${UNIXTIME}+86400] seconds" "+%Y%m%d00"`

for zonefile in $ZONEFILES; do
  zone=`basename $zonefile .zone`
  tempfile=$TMPDIR/`basename $zonefile`
  $SVNLOOK cat -t "$TXN" "$REPOS" "/$zonefile" > ${tempfile}
  $SVNLOOK cat "$REPOS" "/$zonefile" > ${tempfile}.current 2> /dev/null

  # Serial number checking
  SERIAL=`grep serial ${tempfile} | head -n 1 | awk '{ print $1 }' | sed 's/;//' `
  SERIAL_CURRENT=`grep serial ${tempfile}.current | head -n 1 | awk '{ print $1 }' | sed 's/;//' `

  if [[ ${SERIAL} -lt ${STODAY} ]]; then
    echo "The serial number in $zonefile is not recent enough (${SERIAL}). It should be at least ${STODAY} and not more than ${STOMORROW}." 1>&2
    exit 1
  elif [[ ${SERIAL} -ge ${STOMORROW} ]]; then
    echo "The serial number in $zonefile is in the future (${SERIAL}). It should be at least ${STODAY} and not more than ${STOMORROW}." 1>&2
    exit 1
  elif [[ ${SERIAL} -le ${SERIAL_CURRENT} ]]; then
    echo "The serial number in $zonefile hasn't been updated. It should be set to $[${SERIAL_CURRENT}+1]" 1>&2
    exit 1
  fi

  # Syntax checking
  if ! $CHECKZONE "$zone" "$tempfile"; then
	echo -e "Please fix the following errors in $zonefile ($zone):" 1>&2
	$CHECKZONE "$zone" "$tempfile" 1>&2

	exit 1
  fi
done

# Clean up temporary files
#rm -rf $TMPDIR

echo $SERIAL
echo $SERIAL_CURRENT
exit 0
