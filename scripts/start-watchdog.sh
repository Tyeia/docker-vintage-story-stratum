#!/bin/bash
if [ -f "${DATA_DIR}/StratumServer.exe" ]; then
  killpid="$(pidof mono)"
elif [ -f "${DATA_DIR}/StratumServer" ]; then
  killpid="$(pidof StratumServer)"
fi

while true
do
	tail --pid=$killpid -f /dev/null
	kill "$(pidof tail)"
exit 0
done
