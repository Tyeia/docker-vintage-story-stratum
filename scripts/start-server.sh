#!/bin/bash
# Stratum is distributed as GitHub release zips (not through the VS mod API),
# and it is server *software* (a patched VintagestoryServer replacement),
# not a mod. It bootstraps/manages the underlying vanilla server files itself
# on first launch, so all we need to do here is keep the StratumServer binary
# itself up to date and run it in place of VintagestoryServer.
#
# STATIC_V pins a *Vintage Story game version* (e.g. "1.22.6"), same meaning
# as it always had. Stratum tags releases as v<game version>-stratum.<n>, so
# when STATIC_V is set we look up the newest stratum.<n> build for that game
# version instead of a specific Stratum release tag.
STRATUM_REPO="StratumServer/Stratum"
STRATUM_ARCH="linux-x64"

# Probes GitHub release assets directly (no API calls, so no rate limiting)
# to find the highest stratum.<n> build published for a given game version.
resolve_pinned_tag() {
  local GAME_V="$1" n TAG URL
  for n in $(seq 40 -1 1); do
    TAG="v${GAME_V}-stratum.${n}"
    URL="https://github.com/${STRATUM_REPO}/releases/download/${TAG}/stratum-${GAME_V}-stratum.${n}-${STRATUM_ARCH}.zip"
    if wget -q --spider "${URL}" 2>/dev/null; then
      echo "${TAG}"
      return 0
    fi
  done
  return 1
}

CUR_V="$(find ${DATA_DIR} -name 'installed-*' | cut -d '-' -f2-)"
if [ ! -z "${STATIC_V}" ] && [ "${CUR_V#${STATIC_V}-stratum.}" != "${CUR_V}" ]; then
  echo "---Static version: ${STATIC_V} locally found (${CUR_V})!---"
  LAT_V="${CUR_V}"
  DL_URL="local"
elif [ ! -z "${STATIC_V}" ]; then
  echo "---Static version: ${STATIC_V} set, looking up matching Stratum build!---"
  LAT_TAG="$(resolve_pinned_tag "${STATIC_V}")"
  if [ -n "${LAT_TAG}" ]; then
    LAT_V="${LAT_TAG#v}"
    DL_URL="https://github.com/${STRATUM_REPO}/releases/download/${LAT_TAG}/stratum-${LAT_V}-${STRATUM_ARCH}.zip"
  else
    echo "---No Stratum build found for game version ${STATIC_V}!---"
    LAT_V=""
    DL_URL=""
  fi
else
  # GitHub's "latest" release redirect always points at the newest
  # non-prerelease tag, so indev/prerelease builds are skipped automatically.
  LAT_TAG="$(wget --max-redirect=0 -S -O /dev/null "https://github.com/${STRATUM_REPO}/releases/latest" 2>&1 | awk -F'/releases/tag/' '/^  [Ll]ocation:/{print $2}' | tr -d '\r')"
  LAT_V="${LAT_TAG#v}"
  DL_URL="https://github.com/${STRATUM_REPO}/releases/download/${LAT_TAG}/stratum-${LAT_V}-${STRATUM_ARCH}.zip"
fi
if [ -z "${DL_URL}" ] || [ -z "${LAT_V}" ]; then
  if [ -z "${CUR_V}" ]; then
    echo "---Something went wrong, can't get latest version and found no local version, putting server into sleep mode!---"
    sleep infinity
  fi
  echo "---Can't get lateste version but found local version, continuing with local version..."
  LAT_V="${CUR_V}"
  DL_URL=""
fi

echo "---Version Check---"
if [ -z "${CUR_V}" ]; then
  echo "---Stratum not found, downloading...---"
  cd ${DATA_DIR}
  rm -f ${DATA_DIR}/stratum-*.zip
  if wget -q -nc --show-progress --progress=bar:force:noscroll -O ${DATA_DIR}/stratum-${LAT_V}.zip "${DL_URL}" ; then
    echo "---Successfully downloaded Stratum v${LAT_V}---"
  else
    echo "---Can't download Stratum v${LAT_V}, putting server into sleep mode!---"
    sleep infinity
  fi
  unzip -o -q ${DATA_DIR}/stratum-${LAT_V}.zip -d ${DATA_DIR}
  rm ${DATA_DIR}/stratum-${LAT_V}.zip
  chmod +x ${DATA_DIR}/StratumServer
  touch ${DATA_DIR}/installed-${LAT_V}
elif [ "${LAT_V}" != "${CUR_V}" ]; then
  echo "---Newer version found, installing!---"
  rm ${DATA_DIR}/installed-${CUR_V}
  cd ${DATA_DIR}
  find . -maxdepth 1 -not -name 'data' -print0 | xargs -0 -I {} rm -R {} 2&>/dev/null
  rm -f ${DATA_DIR}/stratum-*.zip
  if wget -q -nc --show-progress --progress=bar:force:noscroll -O ${DATA_DIR}/stratum-${LAT_V}.zip "${DL_URL}" ; then
    echo "---Successfully downloaded Stratum v${LAT_V}---"
  else
    echo "---Can't download Stratum v${LAT_V}, putting server into sleep mode!---"
    sleep infinity
  fi
  unzip -o -q ${DATA_DIR}/stratum-${LAT_V}.zip -d ${DATA_DIR}
  rm ${DATA_DIR}/stratum-${LAT_V}.zip
  chmod +x ${DATA_DIR}/StratumServer
  touch ${DATA_DIR}/installed-${LAT_V}
elif [ "${LAT_V}" == "${CUR_V}" ]; then
  echo "---Stratum version up-to-date---"
fi

echo "---Preparing Server---"
chmod -R ${DATA_PERM} ${DATA_DIR}
echo "---Checking for old logs---"
find ${DATA_DIR} -name "masterLog.*" -exec rm -f {} \;
screen -wipe 2&>/dev/null

echo "---Starting Server---"
cd ${DATA_DIR}
if [ -f "${DATA_DIR}/StratumServer" ]; then
  screen -S VintageStory -L -Logfile ${DATA_DIR}/masterLog.0 -d -m ${DATA_DIR}/StratumServer --dataPath ${DATA_DIR}/data ${GAME_PARAMS}
  sleep 2
  screen -S watchdog -d -m /opt/scripts/start-watchdog.sh
  tail -f ${DATA_DIR}/masterLog.0
else
  echo "Can't find game executable, putting container into sleep mode!"
  sleep infinity
fi
